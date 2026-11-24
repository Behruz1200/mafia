import 'package:contracts/contracts.dart';

import 'deal.dart';
import 'event_keys.dart';
import 'memory.dart';

/// The rules of Mafia as a pure state machine.
///
/// Everything it needs comes in through the arguments, so the server and
/// tests can replay any match from its seed and action list. See the
/// package README for the rules in plain words.
class MafiaEngine implements GameEngine {
  const MafiaEngine();

  // ---------------------------------------------------------------- deal

  @override
  GameState newMatch({
    required RoomId roomId,
    required MatchId matchId,
    required List<Player> players,
    required RoomSettings settings,
    required int seed,
    required DateTime now,
  }) {
    final ids = {for (final p in players) p.userId};
    if (ids.length != players.length) {
      throw ArgumentError('players must have distinct user ids');
    }
    final counts = resolveRoleCounts(players.length, settings.roleCounts);
    final roles = dealRoles(players, counts, seed);
    final seated = [...players]..sort((a, b) => a.seat.compareTo(b.seat));
    return GameState(
      public: PublicGameState(
        roomId: roomId,
        matchId: matchId,
        phase: GamePhase.roleReveal,
        round: 0,
        phaseEndsAt: now.add(settings.durations.roleReveal),
        players: [
          for (final p in seated) p.copyWith(isAlive: true, isConnected: true),
        ],
        log: const [
          PublicEvent(
            round: 0,
            phase: GamePhase.roleReveal,
            message: EventKeys.rolesDealt,
          ),
        ],
      ),
      roles: roles,
      settings: settings,
      seed: seed,
      engineData: const EngineMemory().toJson(),
    );
  }

  // --------------------------------------------------------------- apply

  @override
  ApplyResult apply(
    GameState state,
    GameAction action, {
    required DateTime now,
  }) {
    final phase = state.public.phase;
    if (phase == GamePhase.ended) return const Rejected(RejectCodes.matchEnded);
    if (phase == GamePhase.lobby) return const Rejected(RejectCodes.wrongPhase);

    return switch (action) {
      StartMatch() => _startMatch(state, action, now),
      NightKill() => _nightAction(state, action, now),
      NightHeal() => _nightAction(state, action, now),
      NightCheck() => _nightAction(state, action, now),
      NightGuard() => _nightAction(state, action, now),
      NightSleep() => _nightAction(state, action, now),
      CastVote() => _castVote(state, action, now),
      SkipPhase() => _skipPhase(state, action, now),
      SayLastWord() => _sayLastWord(state, action),
      PhaseTimeout() => _timeout(state, now),
      PlayerLeft() => _playerLeft(state, action, now),
    };
  }

  /// The host may skip the rest of the role reveal.
  ApplyResult _startMatch(GameState s, StartMatch a, DateTime now) {
    if (s.public.phase != GamePhase.roleReveal) {
      return const Rejected(RejectCodes.wrongPhase);
    }
    final actor = _player(s, a.actorId);
    if (actor == null) return const Rejected(RejectCodes.unknownPlayer);
    if (!actor.isHost) return const Rejected(RejectCodes.notHost);
    return Accepted(_startNight(s, now));
  }

  ApplyResult _timeout(GameState s, DateTime now) {
    final endsAt = s.public.phaseEndsAt;
    if (endsAt != null && now.isBefore(endsAt)) {
      return const Rejected(RejectCodes.tooEarly);
    }
    return switch (s.public.phase) {
      GamePhase.roleReveal => Accepted(_startNight(s, now)),
      GamePhase.night => _resolveNight(s, now),
      GamePhase.day => Accepted(_startVoting(s, now)),
      GamePhase.voting => _resolveVoting(s, now),
      GamePhase.lastWord => Accepted(_endLastWord(s, now)),
      GamePhase.lobby ||
      GamePhase.ended => const Rejected(RejectCodes.wrongPhase),
    };
  }

  // --------------------------------------------------------------- night

  ApplyResult _nightAction(GameState s, GameAction a, DateTime now) {
    if (s.public.phase != GamePhase.night) {
      return const Rejected(RejectCodes.wrongPhase);
    }
    final actor = _player(s, a.actorId);
    if (actor == null) return const Rejected(RejectCodes.unknownPlayer);
    if (!actor.isAlive) return const Rejected(RejectCodes.actorDead);

    final targetId = switch (a) {
      NightKill(:final targetId) => targetId,
      NightHeal(:final targetId) => targetId,
      NightCheck(:final targetId) => targetId,
      NightGuard(:final targetId) => targetId,
      NightSleep(:final targetId) => targetId,
      _ => throw StateError('not a night action: ${a.type}'),
    };
    final target = _player(s, targetId);
    if (target == null) return const Rejected(RejectCodes.unknownPlayer);
    if (!target.isAlive) return const Rejected(RejectCodes.targetDead);

    final role = s.roles[a.actorId]!;
    final mem = _memory(s);
    switch (a) {
      case NightKill() when role == Role.maniac:
        if (targetId == a.actorId) {
          return const Rejected(RejectCodes.targetSelf);
        }
      case NightKill():
        if (role.team != Team.mafia) {
          return const Rejected(RejectCodes.notYourRole);
        }
        if (s.roles[targetId]!.team == Team.mafia) {
          return const Rejected(RejectCodes.targetTeammate);
        }
      case NightGuard():
        if (role != Role.bodyguard) {
          return const Rejected(RejectCodes.notYourRole);
        }
        if (targetId == a.actorId) {
          return const Rejected(RejectCodes.targetSelf);
        }
        if (targetId == mem.lastGuard) {
          return const Rejected(RejectCodes.sameGuardTwice);
        }
      case NightSleep():
        if (role != Role.hypnotist) {
          return const Rejected(RejectCodes.notYourRole);
        }
        if (targetId == a.actorId) {
          return const Rejected(RejectCodes.targetSelf);
        }
        if (targetId == mem.lastSleep) {
          return const Rejected(RejectCodes.sameSleepTwice);
        }
      case NightHeal():
        if (role != Role.doctor) return const Rejected(RejectCodes.notYourRole);
        if (targetId == mem.lastHeal) {
          return const Rejected(RejectCodes.sameHealTwice);
        }
        if (targetId == a.actorId && mem.selfHealUsed) {
          return const Rejected(RejectCodes.selfHealUsed);
        }
      case NightCheck():
        if (role != Role.detective && role != Role.don) {
          return const Rejected(RejectCodes.notYourRole);
        }
        if (targetId == a.actorId) {
          return const Rejected(RejectCodes.targetSelf);
        }
        if (role == Role.don && s.roles[targetId]!.team == Team.mafia) {
          return const Rejected(RejectCodes.targetTeammate);
        }
        final done = role == Role.detective
            ? mem.checks[a.actorId]?.containsKey(targetId)
            : mem.donChecks[a.actorId]?.containsKey(targetId);
        if (done ?? false) return const Rejected(RejectCodes.alreadyChecked);
      default:
        break;
    }

    // A new pick replaces the same player's earlier pick of the same kind.
    final pending = [
      for (final p in s.pendingNightActions)
        if (!(p.actorId == a.actorId && p.type == a.type)) p,
      a,
    ];
    final next = _copy(s, pendingNightActions: pending);
    if (_nightComplete(next)) return _resolveNight(next, now);
    return Accepted(next);
  }

  /// True once every living night role has made every pick it can make.
  bool _nightComplete(GameState s) {
    bool has(UserId id, String type) =>
        s.pendingNightActions.any((p) => p.actorId == id && p.type == type);
    final mem = _memory(s);
    // The Don's shot is the Mafia's shot (see _resolveNight), so once the
    // Don has shot the other Mafia have nothing left that counts: the
    // night does not wait for them. Unless the Hypnotist put the Don to
    // sleep, which voids the Don's pick and leaves it to the others.
    final asleep = s.pendingNightActions
        .whereType<NightSleep>()
        .where((a) => _player(s, a.actorId)?.isAlive ?? false)
        .lastOrNull
        ?.targetId;
    final donShot = s.public.alive.any(
      (p) =>
          s.roles[p.userId] == Role.don &&
          p.userId != asleep &&
          has(p.userId, 'nightKill'),
    );
    for (final p in s.public.alive) {
      final role = s.roles[p.userId]!;
      final followsDon = donShot && role.team == Team.mafia;
      if (_kills(role) && !followsDon && !has(p.userId, 'nightKill')) {
        return false;
      }
      if (role == Role.bodyguard &&
          _hasTarget(s, p.userId, mem.lastGuard) &&
          !has(p.userId, 'nightGuard')) {
        return false;
      }
      if (role == Role.hypnotist &&
          _hasTarget(s, p.userId, mem.lastSleep) &&
          !has(p.userId, 'nightSleep')) {
        return false;
      }
      if ((role == Role.don || role == Role.detective) &&
          _canCheckAnyone(s, p.userId) &&
          !has(p.userId, 'nightCheck')) {
        return false;
      }
      if (role == Role.doctor && !has(p.userId, 'nightHeal')) return false;
    }
    return true;
  }

  /// Roles that shoot at night: the Mafia team together, the Maniac alone.
  static bool _kills(Role role) =>
      role.team == Team.mafia || role == Role.maniac;

  /// True when [me] has someone to pick other than themselves and [last]
  /// (the Bodyguard and Hypnotist may not pick the same player twice in a
  /// row).
  bool _hasTarget(GameState s, UserId me, UserId? last) =>
      s.public.alive.any((p) => p.userId != me && p.userId != last);

  /// False when a checker has already checked every player they may check,
  /// so the night does not wait on a pick they cannot make.
  bool _canCheckAnyone(GameState s, UserId checker) {
    final mem = _memory(s);
    final isDon = s.roles[checker] == Role.don;
    final done = isDon
        ? mem.donChecks[checker]?.keys.toSet() ?? const <UserId>{}
        : mem.checks[checker]?.keys.toSet() ?? const <UserId>{};
    return s.public.alive.any(
      (p) =>
          p.userId != checker &&
          !done.contains(p.userId) &&
          !(isDon && s.roles[p.userId]!.team == Team.mafia),
    );
  }

  ApplyResult _resolveNight(GameState s, DateTime now) {
    final pub = s.public;
    final round = pub.round;
    var mem = _memory(s);
    bool aliveId(UserId id) => _player(s, id)?.isAlive ?? false;
    Role roleOf(UserId id) => s.roles[id]!;

    // The Hypnotist goes first: whoever they put to sleep does nothing
    // tonight, whatever they picked.
    final sleep = s.pendingNightActions
        .whereType<NightSleep>()
        .where((a) => aliveId(a.actorId) && aliveId(a.targetId))
        .lastOrNull;
    final slept = sleep?.targetId;
    bool acts(GameAction a) => aliveId(a.actorId) && a.actorId != slept;
    final moves = [
      for (final a in s.pendingNightActions)
        if (acts(a)) a,
    ];

    // Who the Mafia kill: the Don's pick if the Don picked, otherwise the
    // most-picked target, ties going to the pick of the lowest seat.
    final kills = [
      for (final a in moves)
        if (a is NightKill &&
            roleOf(a.actorId).team == Team.mafia &&
            aliveId(a.targetId))
          a,
    ];
    UserId? killTarget;
    final donKill = kills.where((a) => roleOf(a.actorId) == Role.don);
    if (donKill.isNotEmpty) {
      killTarget = donKill.last.targetId;
    } else if (kills.isNotEmpty) {
      final tally = <UserId, int>{};
      for (final k in kills) {
        tally[k.targetId] = (tally[k.targetId] ?? 0) + 1;
      }
      final top = tally.values.reduce((a, b) => a > b ? a : b);
      final bySeat = [...kills]
        ..sort(
          (a, b) => _player(
            s,
            a.actorId,
          )!.seat.compareTo(_player(s, b.actorId)!.seat),
        );
      killTarget = bySeat.firstWhere((k) => tally[k.targetId] == top).targetId;
    }
    final maniacKill = moves
        .whereType<NightKill>()
        .where((a) => roleOf(a.actorId) == Role.maniac && aliveId(a.targetId))
        .lastOrNull;

    final heal = moves.whereType<NightHeal>().lastOrNull;
    final guard = moves.whereType<NightGuard>().lastOrNull;

    // Each shot: the Doctor saves the target; else the Bodyguard steps in
    // front of them (and the Doctor may have saved the Bodyguard); the
    // Immortal shrugs a shot off.
    StoryAttack shoot(List<UserId> shooters, UserId target, bool byManiac) {
      if (heal?.targetId == target) {
        return StoryAttack(
          shooters: shooters,
          target: target,
          byManiac: byManiac,
          outcome: ShotOutcome.healed,
        );
      }
      final bodyguard =
          guard != null && guard.targetId == target && guard.actorId != target
          ? guard.actorId
          : null;
      final hit = bodyguard ?? target;
      return StoryAttack(
        shooters: shooters,
        target: target,
        byManiac: byManiac,
        bodyguardId: bodyguard,
        outcome: heal?.targetId == hit
            ? ShotOutcome.healed
            : roleOf(hit) == Role.immortal
            ? ShotOutcome.immortal
            : ShotOutcome.died,
      );
    }

    final attacks = [
      if (killTarget != null)
        shoot(
          [
            for (final k in kills)
              if (k.targetId == killTarget) k.actorId,
          ],
          killTarget,
          false,
        ),
      if (maniacKill != null)
        shoot([maniacKill.actorId], maniacKill.targetId, true),
    ];
    final deaths = <UserId>{
      for (final a in attacks)
        if (a.outcome == ShotOutcome.died) a.hit,
    }.toList();
    final mafiaShot = killTarget == null ? null : attacks.first;

    mem = mem.copyWith(
      lastHeal: () => heal?.targetId,
      selfHealUsed:
          mem.selfHealUsed || (heal != null && heal.targetId == heal.actorId),
      lastGuard: () => guard?.targetId,
      lastSleep: () => slept,
      asleep: () => slept,
    );

    // Checks resolve even if the checker is killed tonight.
    final checks = {
      for (final e in mem.checks.entries) e.key: {...e.value},
    };
    final donChecks = {
      for (final e in mem.donChecks.entries) e.key: {...e.value},
    };
    final madeChecks = moves.whereType<NightCheck>().toList();
    for (final c in madeChecks) {
      final targetRole = roleOf(c.targetId);
      if (roleOf(c.actorId) == Role.don) {
        (donChecks[c.actorId] ??= {})[c.targetId] =
            targetRole == Role.detective;
      } else {
        (checks[c.actorId] ??= {})[c.targetId] = targetRole.team;
      }
    }
    mem = mem.copyWith(checks: checks, donChecks: donChecks);

    // Remember the night for the end-of-match story.
    mem = mem.copyWith(
      nights: [
        ...mem.nights,
        StoryNight(
          round: round,
          target: killTarget,
          shooters: mafiaShot?.shooters ?? const [],
          doctorId: heal?.actorId,
          healed: heal?.targetId,
          saved:
              mafiaShot != null &&
              mafiaShot.outcome == ShotOutcome.healed &&
              mafiaShot.bodyguardId == null,
          checks: [
            for (final c in madeChecks)
              StoryCheck(
                checkerId: c.actorId,
                targetId: c.targetId,
                byDon: roleOf(c.actorId) == Role.don,
                found: roleOf(c.actorId) == Role.don
                    ? roleOf(c.targetId) == Role.detective
                    : roleOf(c.targetId).team == Team.mafia,
              ),
          ],
          attacks: attacks,
          bodyguardId: guard?.actorId,
          guarded: guard?.targetId,
          hypnotistId: sleep?.actorId,
          slept: slept,
        ),
      ],
    );

    var players = pub.players;
    final log = [...pub.log];
    for (final dead in deaths) {
      players = _eliminate(players, dead);
      log.add(
        PublicEvent(
          round: round,
          phase: GamePhase.night,
          message: EventKeys.eliminated,
          userId: dead,
          cause: EliminationCause.killedAtNight,
        ),
      );
    }
    if (deaths.isEmpty) {
      log.add(
        PublicEvent(
          round: round,
          phase: GamePhase.night,
          message: EventKeys.nobodyDied,
        ),
      );
    }

    final afterNight = _copy(
      s,
      public: _pub(pub, players: players, log: log),
      pendingNightActions: const [],
      memory: mem,
    );
    final winner = _winner(afterNight);
    if (winner != null) return _end(afterNight, winner, now);
    if (deaths.isNotEmpty) {
      return Accepted(
        _startLastWord(
          afterNight,
          deaths.first,
          then: GamePhase.day,
          now: now,
          queue: deaths.skip(1).toList(),
        ),
      );
    }
    return Accepted(_startDay(afterNight, now));
  }

  // -------------------------------------------------------------- voting

  ApplyResult _castVote(GameState s, CastVote a, DateTime now) {
    if (s.public.phase != GamePhase.voting) {
      return const Rejected(RejectCodes.wrongPhase);
    }
    final actor = _player(s, a.actorId);
    if (actor == null) return const Rejected(RejectCodes.unknownPlayer);
    if (!actor.isAlive) return const Rejected(RejectCodes.actorDead);
    final targetId = a.targetId;
    if (targetId != null) {
      final target = _player(s, targetId);
      if (target == null) return const Rejected(RejectCodes.unknownPlayer);
      if (!target.isAlive) return const Rejected(RejectCodes.targetDead);
      if (targetId == a.actorId) return const Rejected(RejectCodes.targetSelf);
    }
    final votes = {...s.public.votes, a.actorId: targetId};
    final next = _copy(s, public: _pub(s.public, votes: votes));
    if (next.public.alive.every((p) => votes.containsKey(p.userId))) {
      return _resolveVoting(next, now);
    }
    return Accepted(next);
  }

  /// The most-voted player is out if they have more votes than anyone else
  /// and more than the skips. Players who did not vote do not count.
  ApplyResult _resolveVoting(GameState s, DateTime now) {
    final pub = s.public;
    final tally = <UserId, int>{};
    var skips = 0;
    for (final MapEntry(key: voter, value: target) in pub.votes.entries) {
      if (!(_player(s, voter)?.isAlive ?? false)) continue;
      if (target == null) {
        skips++;
      } else if (_player(s, target)?.isAlive ?? false) {
        tally[target] = (tally[target] ?? 0) + 1;
      }
    }

    final log = [...pub.log];
    var players = pub.players;
    final top = tally.isEmpty
        ? 0
        : tally.values.reduce((a, b) => a > b ? a : b);
    final leaders = [
      for (final e in tally.entries)
        if (e.value == top) e.key,
    ];
    UserId? votedOut;
    var tied = false;
    if (top == 0 || top <= skips) {
      log.add(_event(pub, EventKeys.nobodyVotedOut));
    } else if (leaders.length > 1) {
      tied = true;
      log.add(_event(pub, EventKeys.voteTied));
    } else {
      votedOut = leaders.single;
      players = _eliminate(players, votedOut);
      log.add(
        PublicEvent(
          round: pub.round,
          phase: GamePhase.voting,
          message: EventKeys.eliminated,
          userId: leaders.single,
          cause: EliminationCause.votedOut,
        ),
      );
    }

    // Who voted for whom stays open to the table until the next vote.
    final cast = {
      for (final MapEntry(key: voter, value: target) in pub.votes.entries)
        if (_player(s, voter)?.isAlive ?? false) voter: target,
    };
    final mem = _memory(s);
    final afterVote = _copy(
      s,
      public: _pub(
        pub,
        players: players,
        log: log,
        votes: const {},
        lastVotes: cast,
      ),
      memory: mem.copyWith(
        days: [
          ...mem.days,
          StoryVote(
            round: pub.round,
            votes: cast,
            votedOut: votedOut,
            tied: tied,
          ),
        ],
      ),
    );
    final winner = _winner(afterVote);
    if (winner != null) return _end(afterVote, winner, now);
    if (votedOut != null) {
      return Accepted(
        _startLastWord(afterVote, votedOut, then: GamePhase.night, now: now),
      );
    }
    return Accepted(_startNight(afterVote, now));
  }

  // ----------------------------------------------------------- last word

  GameState _startLastWord(
    GameState s,
    UserId speaker, {
    required GamePhase then,
    required DateTime now,
    List<UserId> queue = const [],
  }) => _copy(
    s,
    public: _pub(
      s.public,
      phase: GamePhase.lastWord,
      phaseEndsAt: () => now.add(s.settings.durations.lastWord),
      votes: const {},
      lastWordBy: () => speaker,
    ),
    memory: _memory(s)
        .copyWith(afterLastWord: () => then, lastWordQueue: queue),
  );

  /// Gives the next player killed the same night their last word, or moves
  /// on to the phase the last word interrupted.
  GameState _endLastWord(GameState s, DateTime now) {
    final mem = _memory(s);
    final then = mem.afterLastWord;
    final queue = [
      for (final id in mem.lastWordQueue)
        if (_player(s, id)?.isConnected ?? false) id,
    ];
    if (queue.isNotEmpty && then != null) {
      return _startLastWord(
        s,
        queue.first,
        then: then,
        now: now,
        queue: queue.skip(1).toList(),
      );
    }
    final cleared = _copy(
      s,
      memory: mem.copyWith(afterLastWord: () => null, lastWordQueue: const []),
    );
    return then == GamePhase.night
        ? _startNight(cleared, now)
        : _startDay(cleared, now);
  }

  /// How many lines [speaker] has typed as their last word.
  int _lastWordLines(GameState s, UserId speaker) => s.public.log
      .where((e) => e.message == EventKeys.lastWord && e.userId == speaker)
      .length;

  ApplyResult _sayLastWord(GameState s, SayLastWord a) {
    final pub = s.public;
    if (pub.phase != GamePhase.lastWord) {
      return const Rejected(RejectCodes.wrongPhase);
    }
    if (a.actorId != pub.lastWordBy) {
      return const Rejected(RejectCodes.notYourRole);
    }
    final text = ChatRules.clean(a.text);
    if (text.isEmpty) return const Rejected(RejectCodes.emptyText);
    if (_lastWordLines(s, a.actorId) >= ChatRules.maxLastWordLines) {
      return const Rejected(RejectCodes.lastWordFull);
    }
    return Accepted(
      _copy(
        s,
        public: _pub(
          pub,
          log: [
            ...pub.log,
            PublicEvent(
              round: pub.round,
              phase: GamePhase.lastWord,
              message: EventKeys.lastWord,
              userId: a.actorId,
              text: text,
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------- skip the timer

  /// Phases whose timer the players may end early by all agreeing. Night
  /// and voting already end as soon as everyone has acted.
  static bool _skippable(GamePhase p) =>
      p == GamePhase.day || p == GamePhase.roleReveal;

  ApplyResult _skipPhase(GameState s, SkipPhase a, DateTime now) {
    // The speaker alone may end their own last word.
    if (s.public.phase == GamePhase.lastWord) {
      if (a.actorId != s.public.lastWordBy) {
        return const Rejected(RejectCodes.notYourRole);
      }
      if (!a.skip) return Accepted(s);
      return Accepted(_endLastWord(s, now));
    }
    if (!_skippable(s.public.phase)) {
      return const Rejected(RejectCodes.wrongPhase);
    }
    final actor = _player(s, a.actorId);
    if (actor == null) return const Rejected(RejectCodes.unknownPlayer);
    if (!actor.isAlive) return const Rejected(RejectCodes.actorDead);
    final skips = [
      for (final u in s.public.skipVotes)
        if (u != a.actorId) u,
      if (a.skip) a.actorId,
    ];
    final next = _copy(s, public: _pub(s.public, skipVotes: skips));
    return _maybeSkip(next, now) ?? Accepted(next);
  }

  /// Ends the phase now if more than half of the living players have agreed
  /// to skip (`SkipPhase.needed`).
  ApplyResult? _maybeSkip(GameState s, DateTime now) {
    final pub = s.public;
    if (!_skippable(pub.phase)) return null;
    final alive = pub.alive.toList();
    final agreed = alive.where((p) => pub.skipVotes.contains(p.userId));
    if (alive.isEmpty || agreed.length < SkipPhase.needed(alive.length)) {
      return null;
    }
    final skipped = _copy(
      s,
      public: _pub(pub, log: [...pub.log, _event(pub, EventKeys.phaseSkipped)]),
    );
    return Accepted(
      pub.phase == GamePhase.day
          ? _startVoting(skipped, now)
          : _startNight(skipped, now),
    );
  }

  // ------------------------------------------------------------- leaving

  ApplyResult _playerLeft(GameState s, PlayerLeft a, DateTime now) {
    final leaver = _player(s, a.userId);
    if (leaver == null) return const Rejected(RejectCodes.unknownPlayer);
    final mem = _memory(s);
    if (mem.forfeited.contains(a.userId)) {
      return const Rejected(RejectCodes.alreadyLeft);
    }
    final pub = s.public;

    // A player who is already out just disconnects; they keep their result.
    if (!leaver.isAlive) {
      final gone = _copy(
        s,
        public: _pub(
          pub,
          players: [
            for (final p in pub.players)
              p.userId == a.userId ? p.copyWith(isConnected: false) : p,
          ],
        ),
      );
      // Nobody waits for the last word of a player who has gone.
      if (pub.phase == GamePhase.lastWord && pub.lastWordBy == a.userId) {
        return Accepted(_endLastWord(gone, now));
      }
      return Accepted(gone);
    }

    final players = [
      for (final p in pub.players)
        p.userId == a.userId
            ? p.copyWith(isAlive: false, isConnected: false)
            : p,
    ];
    final next = _copy(
      s,
      public: _pub(
        pub,
        players: players,
        votes: {
          for (final e in pub.votes.entries)
            if (e.key != a.userId && e.value != a.userId) e.key: e.value,
        },
        skipVotes: [
          for (final u in pub.skipVotes)
            if (u != a.userId) u,
        ],
        log: [
          ...pub.log,
          PublicEvent(
            round: pub.round,
            phase: pub.phase,
            message: EventKeys.playerLeft,
            userId: a.userId,
            cause: EliminationCause.leftMatch,
          ),
        ],
      ),
      pendingNightActions: [
        for (final p in s.pendingNightActions)
          if (p.actorId != a.userId && _targetOf(p) != a.userId) p,
      ],
      memory: mem.copyWith(forfeited: [...mem.forfeited, a.userId]),
    );

    final winner = _winner(next);
    if (winner != null) return _end(next, winner, now);
    if (next.public.phase == GamePhase.night && _nightComplete(next)) {
      return _resolveNight(next, now);
    }
    if (next.public.phase == GamePhase.voting &&
        next.public.alive.every(
          (p) => next.public.votes.containsKey(p.userId),
        )) {
      return _resolveVoting(next, now);
    }
    return _maybeSkip(next, now) ?? Accepted(next);
  }

  // ---------------------------------------------------------- transitions

  GameState _startDay(GameState s, DateTime now) => _copy(
    s,
    public: _pub(
      s.public,
      phase: GamePhase.day,
      phaseEndsAt: () => now.add(s.settings.durations.day),
      log: [
        ...s.public.log,
        PublicEvent(
          round: s.public.round,
          phase: GamePhase.day,
          message: EventKeys.dayStarted,
        ),
      ],
    ),
  );

  GameState _startNight(GameState s, DateTime now) {
    final round = s.public.round + 1;
    return _copy(
      memory: _memory(s).copyWith(asleep: () => null),
      s,
      public: _pub(
        s.public,
        phase: GamePhase.night,
        round: round,
        phaseEndsAt: () => now.add(s.settings.durations.night),
        votes: const {},
        log: [
          ...s.public.log,
          PublicEvent(
            round: round,
            phase: GamePhase.night,
            message: EventKeys.nightStarted,
          ),
        ],
      ),
      pendingNightActions: const [],
    );
  }

  GameState _startVoting(GameState s, DateTime now) => _copy(
    s,
    public: _pub(
      s.public,
      phase: GamePhase.voting,
      phaseEndsAt: () => now.add(s.settings.durations.voting),
      votes: const {},
      lastVotes: const {},
      log: [
        ...s.public.log,
        PublicEvent(
          round: s.public.round,
          phase: GamePhase.voting,
          message: EventKeys.votingStarted,
        ),
      ],
    ),
  );

  /// The Maniac wins once they are one of the last two players alive.
  /// Otherwise the town wins when no Mafia and no Maniac is left, and the
  /// Mafia win once they are at least as many as everyone else alive.
  Team? _winner(GameState s) {
    var mafia = 0;
    var town = 0;
    var maniac = 0;
    for (final p in s.public.alive) {
      switch (s.roles[p.userId]!.team) {
        case Team.mafia:
          mafia++;
        case Team.town:
          town++;
        case Team.maniac:
          maniac++;
      }
    }
    if (maniac > 0 && mafia + town + maniac <= 2) return Team.maniac;
    if (mafia == 0 && maniac == 0) return Team.town;
    if (mafia > 0 && mafia >= town + maniac) return Team.mafia;
    return null;
  }

  Accepted _end(GameState s, Team winner, DateTime now) {
    final pub = s.public;
    final mem = _memory(s);
    final forfeited = mem.forfeited;
    final ended = _copy(
      s,
      public: _pub(
        pub,
        phase: GamePhase.ended,
        phaseEndsAt: () => null,
        votes: const {},
        winner: winner,
        log: [
          ...pub.log,
          PublicEvent(
            round: pub.round,
            phase: GamePhase.ended,
            message: switch (winner) {
              Team.town => EventKeys.townWon,
              Team.mafia => EventKeys.mafiaWon,
              Team.maniac => EventKeys.maniacWon,
            },
          ),
        ],
      ),
      pendingNightActions: const [],
    );
    final winners = <UserId>[];
    final losers = <UserId>[];
    for (final p in pub.players) {
      final won =
          s.roles[p.userId]!.team == winner && !forfeited.contains(p.userId);
      (won ? winners : losers).add(p.userId);
    }
    return Accepted(
      ended,
      matchResult: MatchResult(
        roomId: pub.roomId,
        matchId: pub.matchId,
        stake: s.settings.stake,
        winningTeam: winner,
        winners: winners,
        losers: losers,
        forfeited: forfeited,
        roles: {for (final p in pub.players) p.userId: s.roles[p.userId]!},
        story: MatchStory(
          nights: mem.nights,
          days: mem.days,
          lastWords: {
            for (final e in pub.log)
              if (e.message == EventKeys.lastWord &&
                  e.userId != null &&
                  e.text != null)
                e.userId!: [
                  for (final l in pub.log)
                    if (l.message == EventKeys.lastWord &&
                        l.userId == e.userId &&
                        l.text != null)
                      l.text!,
                ],
          },
        ),
        endedAt: now,
      ),
    );
  }

  // --------------------------------------------------------- private view

  @override
  PrivatePlayerState privateView(GameState state, UserId userId) {
    final role = state.roles[userId];
    final me = _player(state, userId);
    if (role == null || me == null) {
      throw ArgumentError.value(userId, 'userId', 'not in this match');
    }
    final mem = _memory(state);
    return PrivatePlayerState(
      userId: userId,
      role: role,
      teammates: role.team == Team.mafia
          ? [
              for (final p in state.public.players)
                if (p.userId != userId &&
                    state.roles[p.userId]!.team == Team.mafia)
                  p.userId,
            ]
          : const [],
      checks: role == Role.detective
          ? mem.checks[userId] ?? const {}
          : const {},
      detectiveChecks: role == Role.don
          ? mem.donChecks[userId] ?? const {}
          : const {},
      allowedActions: _allowedActions(state, me, role),
      wasAsleep: mem.asleep == userId && state.public.phase != GamePhase.night,
    );
  }

  List<String> _allowedActions(GameState s, Player me, Role role) {
    switch (s.public.phase) {
      case GamePhase.roleReveal:
        return me.isHost
            ? const ['startMatch', 'skipPhase']
            : const ['skipPhase'];
      case GamePhase.day when me.isAlive:
        return const ['skipPhase'];
      case GamePhase.night when me.isAlive:
        final mem = _memory(s);
        return [
          if (_kills(role)) 'nightKill',
          if (role == Role.doctor) 'nightHeal',
          if (role == Role.bodyguard && _hasTarget(s, me.userId, mem.lastGuard))
            'nightGuard',
          if (role == Role.hypnotist && _hasTarget(s, me.userId, mem.lastSleep))
            'nightSleep',
          if ((role == Role.detective || role == Role.don) &&
              _canCheckAnyone(s, me.userId))
            'nightCheck',
        ];
      case GamePhase.voting when me.isAlive:
        return const ['castVote'];
      case GamePhase.lastWord when s.public.lastWordBy == me.userId:
        return [
          if (_lastWordLines(s, me.userId) < ChatRules.maxLastWordLines)
            'lastWord',
          'skipPhase',
        ];
      default:
        return const [];
    }
  }

  // -------------------------------------------------------------- helpers

  Player? _player(GameState s, UserId id) {
    for (final p in s.public.players) {
      if (p.userId == id) return p;
    }
    return null;
  }

  EngineMemory _memory(GameState s) => EngineMemory.fromJson(s.engineData);

  UserId? _targetOf(GameAction a) => switch (a) {
    NightKill(:final targetId) => targetId,
    NightHeal(:final targetId) => targetId,
    NightCheck(:final targetId) => targetId,
    NightGuard(:final targetId) => targetId,
    NightSleep(:final targetId) => targetId,
    _ => null,
  };

  List<Player> _eliminate(List<Player> players, UserId id) => [
    for (final p in players) p.userId == id ? p.copyWith(isAlive: false) : p,
  ];

  PublicEvent _event(PublicGameState pub, String message) =>
      PublicEvent(round: pub.round, phase: pub.phase, message: message);

  GameState _copy(
    GameState s, {
    PublicGameState? public,
    List<GameAction>? pendingNightActions,
    EngineMemory? memory,
  }) => GameState(
    public: public ?? s.public,
    roles: s.roles,
    settings: s.settings,
    pendingNightActions: pendingNightActions ?? s.pendingNightActions,
    seed: s.seed,
    engineData: memory?.toJson() ?? s.engineData,
  );

  PublicGameState _pub(
    PublicGameState p, {
    GamePhase? phase,
    int? round,
    DateTime? Function()? phaseEndsAt,
    List<Player>? players,
    Map<UserId, UserId?>? votes,
    Map<UserId, UserId?>? lastVotes,
    List<UserId>? skipVotes,
    List<PublicEvent>? log,
    Team? winner,
    UserId? Function()? lastWordBy,
  }) => PublicGameState(
    roomId: p.roomId,
    matchId: p.matchId,
    phase: phase ?? p.phase,
    round: round ?? p.round,
    phaseEndsAt: phaseEndsAt == null ? p.phaseEndsAt : phaseEndsAt(),
    players: players ?? p.players,
    votes: votes ?? p.votes,
    lastVotes: lastVotes ?? p.lastVotes,
    // Agreements to skip belong to one phase only.
    skipVotes:
        skipVotes ??
        (phase != null && phase != p.phase ? const [] : p.skipVotes),
    log: log ?? p.log,
    winner: winner ?? p.winner,
    // The speaker belongs to the last word only.
    lastWordBy: lastWordBy != null
        ? lastWordBy()
        : (phase != null && phase != p.phase ? null : p.lastWordBy),
  );
}
