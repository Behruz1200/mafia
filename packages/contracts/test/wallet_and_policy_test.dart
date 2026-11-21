import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:test/test.dart';

MatchResult result(String id, {List<String> winners = const ['a']}) =>
    MatchResult(
      roomId: 'r',
      matchId: id,
      stake: 100,
      winningTeam: winners.isEmpty ? null : Team.town,
      winners: winners,
      losers: const ['b', 'c'],
      endedAt: fixtureNow,
    );

void main() {
  group('InMemoryWalletSettlement', () {
    late InMemoryWalletSettlement w;
    setUp(
      () => w = InMemoryWalletSettlement(
        balances: {'a': 100, 'b': 100, 'c': 100, 'poor': 10},
      ),
    );

    test('holds are all or nothing', () async {
      await expectLater(
        w.holdStakes(matchId: 'm', players: ['a', 'poor'], stake: 100),
        throwsA(isA<InsufficientCoins>()),
      );
      expect(w.availableOf('a'), 100);
    });

    test('winner takes the pot minus a 10% house cut, once', () async {
      await w.holdStakes(matchId: 'm', players: ['a', 'b', 'c'], stake: 100);
      await w.settle(result('m'));
      await w.settle(result('m')); // retry must not pay twice
      expect(w.availableOf('a'), 270);
      expect(w.availableOf('b'), 0);
      expect(w.availableOf(houseAccount), 30);
    });

    test('cancelled match returns stakes', () async {
      await w.holdStakes(matchId: 'm', players: ['a', 'b'], stake: 100);
      await w.settle(result('m', winners: const []));
      expect(w.availableOf('a'), 100);
      expect(w.availableOf('b'), 100);
    });
  });

  group('RegionPolicy', () {
    final p = RegionPolicy.fromJson({
      'launchCountries': ['uz'],
      'stakeCountries': ['UZ'],
    });

    test('Uzbekistan is open, stakes need 18+', () {
      expect(p.allowsApp('UZ'), isTrue);
      expect(p.allowsApp('KZ'), isFalse);
      expect(p.allowsStakes(country: 'UZ', isAdult: true), isTrue);
      expect(p.allowsStakes(country: 'UZ', isAdult: false), isFalse);
      expect(p.allowsStakes(country: null, isAdult: true), isFalse);
    });
  });
}
