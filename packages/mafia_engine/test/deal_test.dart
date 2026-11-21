import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('default deal', () {
    test('matches the table in the README', () {
      Map<Role, int> row(int don, int mafia, int det, int doc, int civ) => {
        Role.don: don,
        Role.mafia: mafia,
        Role.detective: det,
        Role.doctor: doc,
        Role.civilian: civ,
      };
      expect(defaultRoleCounts(4), row(0, 1, 1, 0, 2));
      expect(defaultRoleCounts(5), row(0, 1, 1, 1, 2));
      expect(defaultRoleCounts(6), row(1, 1, 1, 1, 2));
      expect(defaultRoleCounts(8), row(1, 1, 1, 1, 4));
      expect(defaultRoleCounts(9), row(1, 2, 1, 1, 4));
      expect(defaultRoleCounts(12), row(1, 3, 1, 1, 6));
    });

    test('always adds up and keeps the Mafia a minority', () {
      for (var n = 4; n <= 20; n++) {
        final c = defaultRoleCounts(n);
        expect(c.values.fold(0, (a, b) => a + b), n);
        final mafia = c[Role.mafia]! + c[Role.don]!;
        expect(mafia, greaterThan(0));
        expect(mafia * 2, lessThan(n));
      }
    });

    test('needs at least 4 players', () {
      expect(() => defaultRoleCounts(3), throwsArgumentError);
    });
  });

  group('newMatch', () {
    GameState deal(int seed, {int players = 10, Map<Role, int>? counts}) =>
        engine.newMatch(
          roomId: 'r',
          matchId: 'm',
          players: samplePlayers(players),
          settings: RoomSettings(roleCounts: counts),
          seed: seed,
          now: fixtureNow,
        );

    test('starts the role reveal with a timer', () {
      final s = deal(1);
      expect(s.public.phase, GamePhase.roleReveal);
      expect(s.public.round, 0);
      expect(s.public.phaseEndsAt, fixtureNow.add(const Duration(seconds: 10)));
      expect(s.public.log.single.message, EventKeys.rolesDealt);
      expect(s.roles.length, 10);
    });

    test('the same seed deals the same roles', () {
      expect(deal(42).roles, deal(42).roles);
    });

    test('different seeds shuffle the deal', () {
      final deals = {
        for (var seed = 0; seed < 20; seed++) deal(seed).roles.toString(),
      };
      expect(deals.length, greaterThan(10));
    });

    test('deals exactly the counts asked for', () {
      final s = deal(3, players: 8, counts: eightDeal);
      Iterable<Role> of(Role r) => s.roles.values.where((x) => x == r);
      expect(of(Role.don).length, 1);
      expect(of(Role.mafia).length, 1);
      expect(of(Role.detective).length, 1);
      expect(of(Role.doctor).length, 1);
      expect(of(Role.civilian).length, 4);
    });

    test('refuses unfair or impossible deals', () {
      expect(() => deal(1, players: 3), throwsArgumentError);
      expect(() => deal(1, counts: {Role.doctor: 1}), throwsArgumentError);
      expect(() => deal(1, counts: {Role.don: 2}), throwsArgumentError);
      expect(
        () => deal(1, players: 6, counts: {Role.mafia: 3}),
        throwsArgumentError,
      );
      expect(
        () => deal(1, players: 4, counts: {Role.mafia: 1, Role.don: 1}),
        throwsArgumentError,
      );
    });

    test('refuses duplicate players', () {
      final p = samplePlayers(5);
      expect(
        () => engine.newMatch(
          roomId: 'r',
          matchId: 'm',
          players: [...p, p.first],
          settings: const RoomSettings(),
          seed: 1,
          now: fixtureNow,
        ),
        throwsArgumentError,
      );
    });
  });
}
