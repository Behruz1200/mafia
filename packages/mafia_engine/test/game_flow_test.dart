import 'package:contracts/contracts.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Table t;
  late UserId don, mafia, detective, doctor;
  late List<UserId> civilians;

  setUp(() {
    t = Table();
    don = t.one(Role.don);
    mafia = t.one(Role.mafia);
    detective = t.one(Role.detective);
    doctor = t.one(Role.doctor);
    civilians = t.all(Role.civilian);
  });

  group('role reveal', () {
    test('the timer must run out before the night starts', () {
      expect(t.reject(const PhaseTimeout()), RejectCodes.tooEarly);
      t.toNight();
      expect(t.state.public.round, 1);
      expect(t.lastEvent.message, EventKeys.nightStarted);
    });

    test('the host can start the night early, nobody else can', () {
      expect(
        t.reject(const StartMatch(actorId: 'user_1')),
        RejectCodes.notHost,
      );
      t.act(const StartMatch(actorId: 'user_0'));
      expect(t.phase, GamePhase.night);
      expect(
        t.reject(const StartMatch(actorId: 'user_0')),
        RejectCodes.wrongPhase,
      );
    });

    test('night actions wait for the night', () {
      expect(
        t.reject(NightKill(actorId: don, targetId: civilians[0])),
        RejectCodes.wrongPhase,
      );
    });
  });

  group('night', () {
    setUp(() => t.toNight());

    test('only the Mafia can kill, and not each other', () {
      expect(
        t.reject(NightKill(actorId: civilians[0], targetId: civilians[1])),
        RejectCodes.notYourRole,
      );
      expect(
        t.reject(NightKill(actorId: mafia, targetId: don)),
        RejectCodes.targetTeammate,
      );
      expect(
        t.reject(NightKill(actorId: mafia, targetId: 'nobody')),
        RejectCodes.unknownPlayer,
      );
    });

    test('only the Doctor heals; only the Detective and Don check', () {
      expect(
        t.reject(NightHeal(actorId: detective, targetId: doctor)),
        RejectCodes.notYourRole,
      );
      expect(
        t.reject(NightCheck(actorId: doctor, targetId: don)),
        RejectCodes.notYourRole,
      );
      expect(
        t.reject(NightCheck(actorId: detective, targetId: detective)),
        RejectCodes.targetSelf,
      );
      expect(
        t.reject(NightCheck(actorId: don, targetId: mafia)),
        RejectCodes.targetTeammate,
      );
    });

    test('a kill with no heal eliminates the target and starts the day', () {
      t.act(NightKill(actorId: don, targetId: civilians[0]));
      t.timeout();
      expect(t.phase, GamePhase.day);
      expect(t.isAlive(civilians[0]), isFalse);
      final killed = t.log.firstWhere((e) => e.message == EventKeys.eliminated);
      expect(killed.userId, civilians[0]);
      expect(killed.cause, EliminationCause.killedAtNight);
      expect(t.lastEvent.message, EventKeys.dayStarted);
      expect(t.state.pendingNightActions, isEmpty);
    });

    test('the Doctor saves the Mafia target', () {
      t.act(NightKill(actorId: don, targetId: civilians[0]));
      t.act(NightHeal(actorId: doctor, targetId: civilians[0]));
      t.timeout();
      expect(t.isAlive(civilians[0]), isTrue);
      expect(t.log.any((e) => e.message == EventKeys.nobodyDied), isTrue);
    });

    test("the Don's pick wins when the Mafia split", () {
      t.act(NightKill(actorId: mafia, targetId: civilians[0]));
      t.act(NightKill(actorId: don, targetId: civilians[1]));
      t.timeout();
      expect(t.isAlive(civilians[0]), isTrue);
      expect(t.isAlive(civilians[1]), isFalse);
    });

    test('a later pick replaces an earlier one', () {
      t.act(NightKill(actorId: don, targetId: civilians[0]));
      t.act(NightKill(actorId: don, targetId: civilians[2]));
      expect(t.state.pendingNightActions, hasLength(1));
      t.timeout();
      expect(t.isAlive(civilians[2]), isFalse);
    });

    test('nobody dies when the Mafia make no pick', () {
      t.timeout();
      expect(t.state.public.alive, hasLength(8));
      expect(t.log.any((e) => e.message == EventKeys.nobodyDied), isTrue);
    });

    test('the night ends early once every night role has acted', () {
      t.act(NightKill(actorId: don, targetId: civilians[0]));
      t.act(NightKill(actorId: mafia, targetId: civilians[0]));
      t.act(NightCheck(actorId: don, targetId: civilians[1]));
      t.act(NightCheck(actorId: detective, targetId: don));
      expect(t.phase, GamePhase.night);
      t.act(NightHeal(actorId: doctor, targetId: doctor));
      expect(t.phase, GamePhase.day);
    });

    test('the night does not wait for the Mafia once the Don has shot', () {
      t
        ..act(NightKill(actorId: don, targetId: civilians[0]))
        ..act(NightCheck(actorId: don, targetId: civilians[1]))
        ..act(NightCheck(actorId: detective, targetId: don))
        ..act(NightHeal(actorId: doctor, targetId: doctor));
      expect(t.phase, isNot(GamePhase.night));
      expect(t.isAlive(civilians[0]), isFalse);
    });

    test('without a shot from the Don the night waits for every Mafia', () {
      t
        ..act(NightKill(actorId: mafia, targetId: civilians[0]))
        ..act(NightCheck(actorId: don, targetId: civilians[1]))
        ..act(NightCheck(actorId: detective, targetId: don))
        ..act(NightHeal(actorId: doctor, targetId: doctor));
      expect(t.phase, GamePhase.night);
      t.act(NightKill(actorId: don, targetId: civilians[2]));
      expect(t.phase, isNot(GamePhase.night));
      // The Don's pick decides.
      expect(t.isAlive(civilians[2]), isFalse);
      expect(t.isAlive(civilians[0]), isTrue);
    });

    test('check results go only to the checker', () {
      t.act(NightCheck(actorId: detective, targetId: don));
      t.act(NightCheck(actorId: don, targetId: detective));
      t.timeout();
      final det = engine.privateView(t.state, detective);
      expect(det.checks, {don: Team.mafia});
      expect(det.detectiveChecks, isEmpty);
      final d = engine.privateView(t.state, don);
      expect(d.detectiveChecks, {detective: true});
      expect(d.checks, isEmpty);
      expect(engine.privateView(t.state, mafia).detectiveChecks, isEmpty);
    });

    test('the Don sees a non-Detective as false', () {
      t.act(NightCheck(actorId: don, targetId: doctor));
      t.timeout();
      expect(engine.privateView(t.state, don).detectiveChecks, {doctor: false});
    });

    test('nobody checks the same player twice', () {
      t.act(NightCheck(actorId: detective, targetId: mafia));
      t.timeout();
      t.toVoting();
      t.timeout();
      expect(t.phase, GamePhase.night);
      expect(
        t.reject(NightCheck(actorId: detective, targetId: mafia)),
        RejectCodes.alreadyChecked,
      );
    });

    test('the Doctor cannot protect the same player two nights running', () {
      t.act(NightHeal(actorId: doctor, targetId: civilians[0]));
      t.timeout();
      t.toVoting();
      t.timeout();
      expect(
        t.reject(NightHeal(actorId: doctor, targetId: civilians[0])),
        RejectCodes.sameHealTwice,
      );
      t.act(NightHeal(actorId: doctor, targetId: civilians[1]));
    });

    test('the Doctor can protect themselves only once', () {
      t.act(NightHeal(actorId: doctor, targetId: doctor));
      t.timeout();
      t.toVoting();
      t.timeout();
      t.act(NightHeal(actorId: doctor, targetId: civilians[0]));
      t.timeout();
      t.toVoting();
      t.timeout();
      expect(
        t.reject(NightHeal(actorId: doctor, targetId: doctor)),
        RejectCodes.selfHealUsed,
      );
    });

    test('dead players cannot act and cannot be targeted', () {
      t.act(NightKill(actorId: don, targetId: doctor));
      t.timeout();
      t.toVoting();
      t.timeout();
      expect(
        t.reject(NightHeal(actorId: doctor, targetId: civilians[0])),
        RejectCodes.actorDead,
      );
      expect(
        t.reject(NightKill(actorId: don, targetId: doctor)),
        RejectCodes.targetDead,
      );
    });
  });

  group('voting', () {
    setUp(() {
      t.toNight();
      t.timeout(); // quiet night
      t.toVoting();
    });

    test('votes are only taken during voting', () {
      t.timeout();
      expect(t.phase, GamePhase.night);
      expect(
        t.reject(CastVote(actorId: civilians[0], targetId: don)),
        RejectCodes.wrongPhase,
      );
    });

    test('the most-voted player is out', () {
      t.act(CastVote(actorId: civilians[0], targetId: mafia));
      t.act(CastVote(actorId: civilians[1], targetId: mafia));
      t.act(CastVote(actorId: civilians[2], targetId: don));
      expect(t.state.public.votes, hasLength(3));
      t.timeout();
      expect(t.isAlive(mafia), isFalse);
      final out = t.log.lastWhere((e) => e.message == EventKeys.eliminated);
      expect(out.cause, EliminationCause.votedOut);
      expect(t.phase, GamePhase.night);
      expect(t.state.public.round, 2);
      expect(t.state.public.votes, isEmpty);
    });

    test('everyone sees who voted for whom until the next vote', () {
      t.act(CastVote(actorId: civilians[0], targetId: mafia));
      t.act(CastVote(actorId: civilians[1], targetId: mafia));
      t.act(CastVote(actorId: civilians[2], targetId: null));
      t.timeout();
      expect(t.phase, GamePhase.night);
      expect(t.state.public.lastVotes, {
        civilians[0]: mafia,
        civilians[1]: mafia,
        civilians[2]: null,
      });
      t.timeout(); // quiet night
      expect(t.state.public.lastVotes, hasLength(3), reason: 'still day');
      t.toVoting();
      expect(t.state.public.lastVotes, isEmpty);
    });

    test('a tie puts nobody out', () {
      t.act(CastVote(actorId: civilians[0], targetId: mafia));
      t.act(CastVote(actorId: civilians[1], targetId: don));
      t.timeout();
      expect(t.state.public.alive, hasLength(8));
      expect(t.log.any((e) => e.message == EventKeys.voteTied), isTrue);
    });

    test('skips beat or equal the top vote, nobody is out', () {
      t.act(CastVote(actorId: civilians[0], targetId: mafia));
      t.act(CastVote(actorId: civilians[1], targetId: null));
      t.timeout();
      expect(t.state.public.alive, hasLength(8));
      expect(t.log.any((e) => e.message == EventKeys.nobodyVotedOut), isTrue);
    });

    test('a changed vote replaces the old one', () {
      t.act(CastVote(actorId: civilians[0], targetId: don));
      t.act(CastVote(actorId: civilians[0], targetId: mafia));
      expect(t.state.public.votes, {civilians[0]: mafia});
    });

    test('nobody votes for themselves', () {
      expect(
        t.reject(CastVote(actorId: civilians[0], targetId: civilians[0])),
        RejectCodes.targetSelf,
      );
    });

    test('voting ends early once everyone alive has voted', () {
      for (final p in t.state.public.alive.toList()) {
        if (t.phase != GamePhase.voting) break;
        t.act(
          CastVote(
            actorId: p.userId,
            targetId: p.userId == mafia ? don : mafia,
          ),
        );
      }
      expect(t.phase, GamePhase.night);
      expect(t.isAlive(mafia), isFalse);
    });
  });

  group('skip the timer', () {
    List<UserId> alive() => [for (final p in t.state.public.alive) p.userId];

    setUp(() {
      t.toNight();
      t.act(NightKill(actorId: don, targetId: civilians[0]));
      t.timeout();
      expect(t.phase, GamePhase.day);
    });

    test('the day ends early once more than half of the living agree', () {
      final everyone = alive();
      final needed = SkipPhase.needed(everyone.length);
      expect(needed, lessThan(everyone.length));
      for (final id in everyone.take(needed - 1)) {
        t.act(SkipPhase(actorId: id));
        expect(t.phase, GamePhase.day);
      }
      expect(t.state.public.skipVotes, hasLength(needed - 1));
      t.act(SkipPhase(actorId: everyone[needed - 1]));
      expect(t.phase, GamePhase.voting);
      expect(t.state.public.skipVotes, isEmpty);
      expect(t.log.any((e) => e.message == EventKeys.phaseSkipped), isTrue);
    });

    test('one player tapping twice still counts once', () {
      t.act(SkipPhase(actorId: don));
      t.act(SkipPhase(actorId: don));
      expect(t.state.public.skipVotes, [don]);
    });

    test('a player can take their agreement back', () {
      t.act(SkipPhase(actorId: don));
      t.act(SkipPhase(actorId: don, skip: false));
      expect(t.state.public.skipVotes, isEmpty);
    });

    test('dead players cannot skip and are not waited for', () {
      expect(t.reject(SkipPhase(actorId: civilians[0])), RejectCodes.actorDead);
      for (final id in alive()) {
        if (t.phase != GamePhase.day) break;
        t.act(SkipPhase(actorId: id));
      }
      expect(t.phase, GamePhase.voting);
    });

    test('a holdout leaving can tip the count', () {
      final everyone = alive();
      // One short of the share; then a player who did not agree leaves.
      final agree = everyone
          .where((id) => id != civilians[1])
          .take(SkipPhase.needed(everyone.length) - 1);
      for (final id in agree) {
        t.act(SkipPhase(actorId: id));
      }
      expect(t.phase, GamePhase.day);
      t.act(PlayerLeft(userId: civilians[1]));
      expect(
        t.phase,
        agree.length >= SkipPhase.needed(everyone.length - 1)
            ? GamePhase.voting
            : GamePhase.day,
      );
    });

    test('more than half: 3 of 4, 3 of 5, 4 of 7', () {
      expect(
        [for (var n = 1; n <= 12; n++) SkipPhase.needed(n)],
        [1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7],
      );
    });

    test('night and voting cannot be skipped this way', () {
      t.toVoting();
      expect(t.reject(SkipPhase(actorId: don)), RejectCodes.wrongPhase);
      t.timeout();
      expect(t.phase, GamePhase.night);
      expect(t.reject(SkipPhase(actorId: don)), RejectCodes.wrongPhase);
    });
  });

  group('role reveal skip', () {
    test('everyone agreeing starts the night', () {
      final ids = [for (final p in t.state.public.players) p.userId];
      for (final id in ids) {
        if (t.phase != GamePhase.roleReveal) break;
        t.act(SkipPhase(actorId: id));
      }
      expect(t.phase, GamePhase.night);
      expect(t.state.public.round, 1);
    });
  });

  group('winning', () {
    test('the town wins when the last Mafia is voted out', () {
      t.toNight();
      t.timeout();
      t.toVoting();
      t.act(CastVote(actorId: civilians[0], targetId: mafia));
      t.timeout();
      t.timeout(); // quiet night
      t.toVoting();
      t.act(CastVote(actorId: civilians[0], targetId: don));
      t.timeout();

      expect(t.phase, GamePhase.ended);
      expect(t.state.public.winner, Team.town);
      expect(t.state.public.phaseEndsAt, isNull);
      expect(t.lastEvent.message, EventKeys.townWon);
      final r = t.result!;
      expect(r.winningTeam, Team.town);
      expect(r.stake, 100);
      expect(r.winners.toSet(), {detective, doctor, ...civilians});
      expect(r.losers.toSet(), {don, mafia});
      expect(r.forfeited, isEmpty);
      expect(r.endedAt, t.now);
      expect(t.reject(const PhaseTimeout()), RejectCodes.matchEnded);
    });

    test('the Mafia win once they equal the town', () {
      t.toNight();
      // 8 alive: 2 Mafia, 6 town. Kill one a night, vote nobody out.
      final victims = [doctor, detective, civilians[0], civilians[1]];
      for (final v in victims) {
        if (t.phase == GamePhase.ended) break;
        expect(t.phase, GamePhase.night);
        t.act(NightKill(actorId: don, targetId: v));
        t.timeout();
        if (t.phase == GamePhase.ended) break;
        t.toVoting();
        t.timeout();
      }
      expect(t.phase, GamePhase.ended);
      expect(t.state.public.winner, Team.mafia);
      expect(t.result!.winners.toSet(), {don, mafia});
      // Dead Mafia still win, dead town still lose.
      expect(t.result!.losers, containsAll(victims));
    });
  });

  group('leaving', () {
    test('a living player who leaves forfeits, even if their team wins', () {
      t.toNight();
      t.act(PlayerLeft(userId: civilians[0]));
      expect(t.isAlive(civilians[0]), isFalse);
      expect(t.lastEvent.message, EventKeys.playerLeft);
      expect(t.lastEvent.cause, EliminationCause.leftMatch);
      expect(
        t.reject(PlayerLeft(userId: civilians[0])),
        RejectCodes.alreadyLeft,
      );

      t.act(PlayerLeft(userId: don));
      t.act(PlayerLeft(userId: mafia));
      expect(t.phase, GamePhase.ended);
      expect(t.state.public.winner, Team.town);
      final r = t.result!;
      expect(r.forfeited, [civilians[0], don, mafia]);
      expect(r.winners, isNot(contains(civilians[0])));
      expect(r.losers, containsAll([civilians[0], don, mafia]));
    });

    test('a player already out can leave without forfeiting', () {
      t.toNight();
      t.act(NightKill(actorId: don, targetId: civilians[0]));
      t.timeout();
      t.act(PlayerLeft(userId: civilians[0]));
      final p = t.state.public.players.firstWhere(
        (p) => p.userId == civilians[0],
      );
      expect(p.isConnected, isFalse);
      t.toVoting();
      t.act(CastVote(actorId: civilians[1], targetId: mafia));
      t.timeout();
      t.timeout();
      t.toVoting();
      t.act(CastVote(actorId: civilians[1], targetId: don));
      t.timeout();
      expect(t.result!.winners, contains(civilians[0]));
      expect(t.result!.forfeited, isEmpty);
    });

    test("a leaver's picks and votes are dropped", () {
      t.toNight();
      t.act(NightKill(actorId: mafia, targetId: civilians[0]));
      t.act(NightHeal(actorId: doctor, targetId: civilians[1]));
      t.act(PlayerLeft(userId: civilians[1]));
      expect(t.state.pendingNightActions, hasLength(1));
      t.act(PlayerLeft(userId: mafia));
      expect(t.state.pendingNightActions, isEmpty);
    });

    test('leaving can complete the night', () {
      t.toNight();
      t.act(NightKill(actorId: don, targetId: civilians[0]));
      t.act(NightKill(actorId: mafia, targetId: civilians[0]));
      t.act(NightCheck(actorId: don, targetId: civilians[1]));
      t.act(NightCheck(actorId: detective, targetId: don));
      t.act(PlayerLeft(userId: doctor));
      expect(t.phase, GamePhase.day);
    });
  });

  group('private view', () {
    test('Mafia see each other, the town sees nobody', () {
      expect(engine.privateView(t.state, don).teammates, [mafia]);
      expect(engine.privateView(t.state, mafia).teammates, [don]);
      expect(engine.privateView(t.state, detective).teammates, isEmpty);
      expect(engine.privateView(t.state, civilians[0]).role, Role.civilian);
    });

    test('allowed actions follow the phase and role', () {
      List<String> allowed(UserId id) =>
          engine.privateView(t.state, id).allowedActions;
      expect(allowed('user_0'), ['startMatch', 'skipPhase']);
      expect(allowed('user_1'), ['skipPhase']);
      t.toNight();
      expect(allowed(don), ['nightKill', 'nightCheck']);
      expect(allowed(mafia), ['nightKill']);
      expect(allowed(doctor), ['nightHeal']);
      expect(allowed(detective), ['nightCheck']);
      expect(allowed(civilians[0]), isEmpty);
      t.act(NightKill(actorId: don, targetId: civilians[0]));
      t.timeout();
      expect(allowed(don), ['skipPhase']);
      expect(allowed(civilians[0]), isEmpty); // dead
      t.toVoting();
      expect(allowed(don), ['castVote']);
      expect(allowed(civilians[0]), isEmpty); // dead
    });

    test('an unknown player has no view', () {
      expect(
        () => engine.privateView(t.state, 'stranger'),
        throwsArgumentError,
      );
    });
  });

  group('last word', () {
    late Table w;
    late UserId wDon, wDoctor;
    late List<UserId> town;

    setUp(() {
      w = Table(skipLastWords: false);
      wDon = w.one(Role.don);
      wDoctor = w.one(Role.doctor);
      town = w.all(Role.civilian);
      w.toNight();
    });

    List<String> allowed(UserId id) =>
        engine.privateView(w.state, id).allowedActions;

    test('the night victim speaks first, then the day starts', () {
      w.act(NightKill(actorId: wDon, targetId: town[0]));
      w.timeout();
      expect(w.phase, GamePhase.lastWord);
      expect(w.state.public.lastWordBy, town[0]);
      expect(w.isAlive(town[0]), isFalse);
      expect(
        w.state.public.phaseEndsAt,
        w.now.add(const PhaseDurations().lastWord),
      );
      expect(allowed(town[0]), ['lastWord', 'skipPhase']);
      expect(allowed(wDon), isEmpty);
      w.timeout();
      expect(w.phase, GamePhase.day);
      expect(w.state.public.lastWordBy, isNull);
      expect(w.lastEvent.message, EventKeys.dayStarted);
    });

    test('a saved player has no last word', () {
      w.act(NightKill(actorId: wDon, targetId: town[0]));
      w.act(NightHeal(actorId: wDoctor, targetId: town[0]));
      w.timeout();
      expect(w.phase, GamePhase.day);
    });

    test('the voted-out player speaks, then night falls', () {
      w.timeout(); // quiet night
      w.timeout(); // day
      for (final c in town.take(3)) {
        w.act(CastVote(actorId: c, targetId: town[3]));
      }
      w.timeout();
      expect(w.phase, GamePhase.lastWord);
      expect(w.state.public.lastWordBy, town[3]);
      expect(w.state.public.round, 1);
      w.timeout();
      expect(w.phase, GamePhase.night);
      expect(w.state.public.round, 2);
    });

    test('typed lines go to the log, only from the speaker', () {
      w.act(NightKill(actorId: wDon, targetId: town[0]));
      w.timeout();
      expect(
        w.reject(SayLastWord(actorId: town[1], text: 'hi')),
        RejectCodes.notYourRole,
      );
      expect(
        w.reject(SayLastWord(actorId: town[0], text: '  \n ')),
        RejectCodes.emptyText,
      );
      w.act(SayLastWord(actorId: town[0], text: '  It was\nthe Don! '));
      final said = w.lastEvent;
      expect(said.message, EventKeys.lastWord);
      expect(said.userId, town[0]);
      expect(said.text, 'It was the Don!');
      expect(said.phase, GamePhase.lastWord);
      // Survives the trip to the app.
      final back = PublicGameState.fromJson(w.state.public.toJson());
      expect(back.log.last.text, 'It was the Don!');
      expect(back.lastWordBy, town[0]);
    });

    test('at most three typed lines, each cut to 200 characters', () {
      w.act(NightKill(actorId: wDon, targetId: town[0]));
      w.timeout();
      w.act(SayLastWord(actorId: town[0], text: 'x' * 500));
      expect(w.lastEvent.text, hasLength(ChatRules.maxLength));
      w.act(SayLastWord(actorId: town[0], text: 'two'));
      w.act(SayLastWord(actorId: town[0], text: 'three'));
      expect(allowed(town[0]), ['skipPhase']);
      expect(
        w.reject(SayLastWord(actorId: town[0], text: 'four')),
        RejectCodes.lastWordFull,
      );
    });

    test('only the speaker can end it early', () {
      w.act(NightKill(actorId: wDon, targetId: town[0]));
      w.timeout();
      expect(w.reject(SkipPhase(actorId: town[1])), RejectCodes.notYourRole);
      expect(w.reject(const PhaseTimeout()), RejectCodes.tooEarly);
      w.act(SkipPhase(actorId: town[0]));
      expect(w.phase, GamePhase.day);
    });

    test('the speaker leaving ends it', () {
      w.act(NightKill(actorId: wDon, targetId: town[0]));
      w.timeout();
      w.act(PlayerLeft(userId: town[0]));
      expect(w.phase, GamePhase.day);
      expect(w.result, isNull);
    });

    test('no last word when the elimination ends the match', () {
      final small = Table(
        players: 4,
        deal: const {Role.mafia: 1},
        skipLastWords: false,
      );
      final m = small.one(Role.mafia);
      final others = small.all(Role.civilian);
      small.toNight();
      // The only night role has picked, so the night ends at once.
      small.act(NightKill(actorId: m, targetId: others[0]));
      expect(small.phase, GamePhase.lastWord);
      small.act(SayLastWord(actorId: others[0], text: 'Vote out $m'));
      small.timeout(); // last word over: day
      small.timeout(); // voting
      for (final c in others.skip(1)) {
        small.act(CastVote(actorId: c, targetId: m));
      }
      small.act(CastVote(actorId: m, targetId: others[1]));
      expect(small.phase, GamePhase.ended);
      expect(small.result?.winningTeam, Team.town);
      // The typed last word is kept for the end-of-match story.
      expect(small.result?.story?.lastWords, {
        others[0]: ['Vote out $m'],
      });
    });
  });
}
