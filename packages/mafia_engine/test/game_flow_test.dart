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
      expect(allowed('user_0'), ['startMatch']);
      t.toNight();
      expect(allowed(don), ['nightKill', 'nightCheck']);
      expect(allowed(mafia), ['nightKill']);
      expect(allowed(doctor), ['nightHeal']);
      expect(allowed(detective), ['nightCheck']);
      expect(allowed(civilians[0]), isEmpty);
      t.act(NightKill(actorId: don, targetId: civilians[0]));
      t.timeout();
      expect(allowed(don), isEmpty);
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
}
