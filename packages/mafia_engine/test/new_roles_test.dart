import 'package:contracts/contracts.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:mafia_engine/src/memory.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// 8 players: Mafia, Maniac, Detective, Doctor, Bodyguard, Hypnotist,
/// Immortal and one Civilian.
const allNew = {
  Role.mafia: 1,
  Role.maniac: 1,
  Role.detective: 1,
  Role.doctor: 1,
  Role.bodyguard: 1,
  Role.hypnotist: 1,
  Role.immortal: 1,
};

void main() {
  late Table t;
  late UserId mafia, maniac, detective, doctor, guard, hypno, immortal, civ;

  setUp(() {
    t = Table(deal: allNew)..toNight();
    mafia = t.one(Role.mafia);
    maniac = t.one(Role.maniac);
    detective = t.one(Role.detective);
    doctor = t.one(Role.doctor);
    guard = t.one(Role.bodyguard);
    hypno = t.one(Role.hypnotist);
    immortal = t.one(Role.immortal);
    civ = t.one(Role.civilian);
  });

  List<UserId> killed() => [
    for (final e in t.log)
      if (e.message == EventKeys.eliminated &&
          e.cause == EliminationCause.killedAtNight)
        e.userId!,
  ];

  StoryNight lastNight() =>
      EngineMemory.fromJson(t.state.engineData).nights.last;

  group('Maniac', () {
    test('kills on their own, as well as the Mafia', () {
      t
        ..act(NightKill(actorId: mafia, targetId: civ))
        ..act(NightKill(actorId: maniac, targetId: detective))
        ..timeout();
      expect(killed(), [civ, detective]);
      expect(t.phase, GamePhase.day);
      final attacks = lastNight().attacks;
      expect(attacks.map((a) => a.byManiac), [false, true]);
      expect(attacks.every((a) => a.outcome == ShotOutcome.died), isTrue);
    });

    test('may shoot a Mafia member but not themselves', () {
      expect(
        t.reject(NightKill(actorId: maniac, targetId: maniac)),
        RejectCodes.targetSelf,
      );
      t
        ..act(NightKill(actorId: maniac, targetId: mafia))
        ..timeout();
      // The only Mafia is gone, but the Maniac still plays on.
      expect(killed(), [mafia]);
      expect(t.state.public.winner, isNull);
    });

    test('the Mafia may shoot the Maniac', () {
      t
        ..act(NightKill(actorId: mafia, targetId: maniac))
        ..timeout();
      expect(killed(), [maniac]);
    });

    test('the Detective sees the Maniac as their own side', () {
      t
        ..act(NightCheck(actorId: detective, targetId: maniac))
        ..timeout();
      expect(
        engine.privateView(t.state, detective).checks[maniac],
        Team.maniac,
      );
      expect(engine.privateView(t.state, maniac).teammates, isEmpty);
    });

    test('the night waits for the Maniac', () {
      expect(engine.privateView(t.state, maniac).allowedActions, ['nightKill']);
      t
        ..act(NightKill(actorId: mafia, targetId: civ))
        ..act(NightHeal(actorId: doctor, targetId: doctor))
        ..act(NightCheck(actorId: detective, targetId: mafia))
        ..act(NightGuard(actorId: guard, targetId: doctor))
        ..act(NightSleep(actorId: hypno, targetId: doctor));
      expect(t.phase, GamePhase.night);
      t.act(NightKill(actorId: maniac, targetId: immortal));
      expect(t.phase, isNot(GamePhase.night));
    });
  });

  group('two deaths in one night', () {
    test('each gets a last word, in order', () {
      final table = Table(deal: allNew, skipLastWords: false)..toNight();
      table
        ..act(NightKill(actorId: table.one(Role.mafia), targetId: civ))
        ..act(NightKill(actorId: table.one(Role.maniac), targetId: doctor))
        ..timeout();
      expect(table.phase, GamePhase.lastWord);
      expect(table.state.public.lastWordBy, civ);
      table.act(SkipPhase(actorId: civ));
      expect(table.phase, GamePhase.lastWord);
      expect(table.state.public.lastWordBy, doctor);
      table.timeout();
      expect(table.phase, GamePhase.day);
    });
  });

  group('Bodyguard', () {
    test('dies in place of the player they guard', () {
      t
        ..act(NightGuard(actorId: guard, targetId: civ))
        ..act(NightKill(actorId: mafia, targetId: civ))
        ..timeout();
      expect(killed(), [guard]);
      expect(t.isAlive(civ), isTrue);
      expect(lastNight().attacks.single.bodyguardId, guard);
      expect(lastNight().attacks.single.hit, guard);
    });

    test('lives if the Doctor protects the Bodyguard', () {
      t
        ..act(NightGuard(actorId: guard, targetId: civ))
        ..act(NightHeal(actorId: doctor, targetId: guard))
        ..act(NightKill(actorId: mafia, targetId: civ))
        ..timeout();
      expect(killed(), isEmpty);
      expect(t.log.any((e) => e.message == EventKeys.nobodyDied), isTrue);
      expect(lastNight().attacks.single.outcome, ShotOutcome.healed);
    });

    test('takes both shots when both hit their player', () {
      t
        ..act(NightGuard(actorId: guard, targetId: civ))
        ..act(NightKill(actorId: mafia, targetId: civ))
        ..act(NightKill(actorId: maniac, targetId: civ))
        ..timeout();
      expect(killed(), [guard]);
    });

    test('cannot guard themselves or the same player twice in a row', () {
      expect(
        t.reject(NightGuard(actorId: guard, targetId: guard)),
        RejectCodes.targetSelf,
      );
      t
        ..act(NightGuard(actorId: guard, targetId: civ))
        ..timeout()
        ..toVoting()
        ..timeout();
      expect(t.phase, GamePhase.night);
      expect(
        t.reject(NightGuard(actorId: guard, targetId: civ)),
        RejectCodes.sameGuardTwice,
      );
    });
  });

  group('Hypnotist', () {
    test('a sleeping Mafia member kills no one', () {
      t
        ..act(NightSleep(actorId: hypno, targetId: mafia))
        ..act(NightKill(actorId: mafia, targetId: civ))
        ..timeout();
      expect(killed(), isEmpty);
      expect(lastNight().slept, mafia);
      expect(engine.privateView(t.state, mafia).wasAsleep, isTrue);
      expect(engine.privateView(t.state, civ).wasAsleep, isFalse);
    });

    test('a sleeping Doctor saves no one', () {
      t
        ..act(NightSleep(actorId: hypno, targetId: doctor))
        ..act(NightHeal(actorId: doctor, targetId: civ))
        ..act(NightKill(actorId: mafia, targetId: civ))
        ..timeout();
      expect(killed(), [civ]);
    });

    test('a sleeping Detective learns nothing', () {
      t
        ..act(NightSleep(actorId: hypno, targetId: detective))
        ..act(NightCheck(actorId: detective, targetId: mafia))
        ..timeout();
      expect(engine.privateView(t.state, detective).checks, isEmpty);
      expect(lastNight().checks, isEmpty);
    });

    test('the sleep wears off when the next night starts', () {
      t
        ..act(NightSleep(actorId: hypno, targetId: civ))
        ..timeout()
        ..toVoting()
        ..timeout();
      expect(t.phase, GamePhase.night);
      expect(engine.privateView(t.state, civ).wasAsleep, isFalse);
      expect(
        t.reject(NightSleep(actorId: hypno, targetId: civ)),
        RejectCodes.sameSleepTwice,
      );
    });
  });

  group('Immortal', () {
    test('survives a night shot', () {
      expect(engine.privateView(t.state, immortal).allowedActions, isEmpty);
      t
        ..act(NightKill(actorId: mafia, targetId: immortal))
        ..timeout();
      expect(killed(), isEmpty);
      expect(lastNight().attacks.single.outcome, ShotOutcome.immortal);
    });

    test('can still be voted out', () {
      t
        ..timeout()
        ..toVoting();
      for (final p in t.state.public.alive) {
        if (p.userId != immortal) {
          t.act(CastVote(actorId: p.userId, targetId: immortal));
        }
      }
      t.act(CastVote(actorId: immortal, targetId: civ));
      expect(t.isAlive(immortal), isFalse);
    });
  });

  group('who wins', () {
    test('the Maniac wins when one of the last two', () {
      // 5 players: Mafia + Maniac against 3 town.
      final m = Table(players: 5, deal: const {Role.mafia: 1, Role.maniac: 1})
        ..toNight();
      final town = [
        for (final p in m.state.public.players)
          if (m.state.roles[p.userId]!.team == Team.town) p.userId,
      ];
      m
        ..act(
          NightKill(actorId: m.one(Role.maniac), targetId: m.one(Role.mafia)),
        )
        // With only shooters left to act, the night ends at once.
        ..act(NightKill(actorId: m.one(Role.mafia), targetId: town[0]));
      expect(m.state.public.winner, isNull);
      m
        ..toVoting()
        ..timeout()
        ..act(NightKill(actorId: m.one(Role.maniac), targetId: town[1]));
      expect(m.state.public.winner, Team.maniac);
      expect(m.result!.winners, [m.one(Role.maniac)]);
      expect(m.lastEvent.message, EventKeys.maniacWon);
    });

    test('the town must also get rid of the Maniac', () {
      final m = Table(players: 6, deal: const {Role.mafia: 1, Role.maniac: 1})
        ..toNight();
      m
        ..act(
          NightKill(actorId: m.one(Role.maniac), targetId: m.one(Role.mafia)),
        )
        ..timeout();
      expect(m.state.public.winner, isNull);
      m.toVoting();
      final maniacId = m.one(Role.maniac);
      for (final p in m.state.public.alive) {
        m.act(
          CastVote(
            actorId: p.userId,
            targetId: p.userId == maniacId ? m.one(Role.civilian) : maniacId,
          ),
        );
      }
      expect(m.state.public.winner, Team.town);
    });
  });

  group('RoleSetup', () {
    test('counts the Maniac with the Mafia for fairness', () {
      expect(
        RoleSetup.check(4, {Role.mafia: 1, Role.maniac: 1}),
        RoleSetupProblem.tooStrong,
      );
      expect(RoleSetup.check(5, {Role.mafia: 1, Role.maniac: 1}), isNull);
    });

    test('refuses two of a one-of-a-kind role', () {
      expect(
        RoleSetup.check(12, {Role.mafia: 1, Role.bodyguard: 2}),
        RoleSetupProblem.invalidCount,
      );
      expect(RoleSetup.check(12, {Role.mafia: 3}), isNull);
    });

    test('needs a Mafia member and enough seats', () {
      expect(RoleSetup.check(8, {Role.maniac: 1}), RoleSetupProblem.noMafia);
      expect(
        RoleSetup.check(5, {
          Role.mafia: 1,
          Role.detective: 1,
          Role.doctor: 1,
          Role.bodyguard: 1,
          Role.hypnotist: 1,
          Role.immortal: 1,
        }),
        RoleSetupProblem.tooManyRoles,
      );
    });

    test('fills the rest with Civilians', () {
      expect(RoleSetup.fill(8, {Role.mafia: 2, Role.immortal: 1}), {
        Role.mafia: 2,
        Role.immortal: 1,
        Role.civilian: 5,
      });
    });
  });
}
