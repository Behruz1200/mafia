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
      _ => throw StateError('not a night action: ${a.type}'),
    };
    final target = _player(s, targetId);
    if (target == null) return const Rejected(RejectCodes.unknownPlayer);
    if (!target.isAlive) return const Rejected(RejectCodes.targetDead);

    final role = s.roles[a.actorId]!;
    final mem = _memory(s);
    switch (a) {
      case NightKill():
        if (role.team != Team.mafia) {
          return const Rejected(RejectCodes.notYourRole);
        }
        if (s.roles[targetId]!.team == Team.mafia) {
          return const Rejected(RejectCodes.targetTeammate);
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
    for (final p in s.public.alive) {
      final role = s.roles[p.userId]!;
      if (role.team == Team.mafia && !has(p.userId, 'nightKill')) return false;
      if ((role == Role.don || role == Role.detective) &&
          _canCheckAnyone(s, p.userId) &&
          !has(p.userId, 'nightCheck')) {
        return false;
      }
      if (role == Role.doctor && !has(p.userId, 'nightHeal')) return false;
    }
    return true;
  }

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

    // Who the Mafia kill: the Don's pick if the Don picked, otherwise the
    // most-picked target, ties going to the pick of the lowest seat.
    final kills = [
      for (final a in s.pendingNightActions)
        if (a is NightKill && aliveId(a.actorId) && aliveId(a.targetId)) a,
    ];
    UserId? killTarget;
    final donKill = kills.where((a) => s.roles[a.actorId] == Role.don);
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

    final heal = s.pendingNightActions
        .whereType<NightHeal>()
        .where((a) => aliveId(a.actorId))
        .lastOrNull;
    final saved = heal != null && heal.targetId == killTarget;
    mem = mem.copyWith(
      lastHeal: () => heal?.targetId,
      selfHealUsed:
          mem.selfHealUsed || (heal != null && heal.targetId == heal.actorId),
    );

    // Checks resolve even if the checker is killed tonight.
    final checks = {
      for (final e in mem.checks.entries) e.key: {...e.value},
    };
    final donChecks = {
      for (final e in mem.donChecks.entries) e.key: {...e.value},
    };
    for (final c in s.pendingNightActions.whereType<NightCheck>()) {
      if (!aliveId(c.actorId)) continue;
      final targetRole = s.roles[c.targetId]!;
      if (s.roles[c.actorId] == Role.don) {
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
          shooters: [
            for (final k in kills)
              if (k.targetId == killTarget) k.actorId,
          ],
          doctorId: heal?.actorId,
          healed: heal?.targetId,
          saved: saved,
          checks: [
            for (final c in s.pendingNightActions.whereType<NightCheck>())
              if (aliveId(c.actorId))
                StoryCheck(
                  checkerId: c.actorId,
                  targetId: c.targetId,
                  byDon: s.roles[c.actorId] == Role.don,
                  found: s.roles[c.actorId] == Role.don
                      ? s.roles[c.targetId] == Role.detective
                      : s.roles[c.targetId]!.team == Team.mafia,
                ),
          ],
        ),
      ],
    );

    var players = pub.players;
    final log = [...pub.log];
    if (killTarget != null && !saved) {
      players = _eliminate(players, killTarget);
      log.add(
        PublicEvent(
          round: round,
          phase: GamePhase.night,
          message: EventKeys.eliminated,
          userId: killTarget,
          cause: EliminationCause.killedAtNight,
        ),
      );
    } else {
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
    if (killTarget != null && !saved) {
      return Accepted(
        _startLastWord(afterNight, killTarget, then: GamePhase.day, now: now),
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

    final mem = _memory(s);
    final afterVote = _copy(
      s,
      public: _pub(pub, players: players, log: log, votes: const {}),
      memory: mem.copyWith(
        days: [
          ...mem.days,
          StoryVote(
            round: pub.round,
            votes: {
              for (final MapEntry(key: voter, value: target)
                  in pub.votes.entries)
                if (_player(s, voter)?.isAlive ?? false) voter: target,
            },
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
  }) => _copy(
    s,
    public: _pub(
      s.public,
      phase: GamePhase.lastWord,
      phaseEndsAt: () => now.add(s.settings.durations.lastWord),
      votes: const {},
      lastWordBy: () => speaker,
    ),
    memory: _memory(s).copyWith(afterLastWord: () => then),
  );

  /// Moves on to the phase the last word interrupted.
  GameState _endLastWord(GameState s, DateTime now) {
    final then = _memory(s).afterLastWord;
    final cleared = _copy(
      s,
      memory: _memory(s).copyWith(afterLastWord: () => null),
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

  /// Ends the phase now if every living player has agreed to skip.
  ApplyResult? _maybeSkip(GameState s, DateTime now) {
    final pub = s.public;
    if (!_skippable(pub.phase)) return null;
    final alive = pub.alive.toList();
    if (alive.isEmpty ||
        !alive.every((p) => pub.skipVotes.contains(p.userId))) {
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

  /// Town wins when no Mafia is left. Mafia wins once they are at least as
  /// many as the living town.
  Team? _winner(GameState s) {
    var mafia = 0;
    var town = 0;
    for (final p in s.public.alive) {
      s.roles[p.userId]!.team == Team.mafia ? mafia++ : town++;
    }
    if (mafia == 0) return Team.town;
    if (mafia >= town) return Team.mafia;
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
            message: winner == Team.town
                ? EventKeys.townWon
                : EventKeys.mafiaWon,
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
        return [
          if (role.team == Team.mafia) 'nightKill',
          if (role == Role.doctor) 'nightHeal',
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
