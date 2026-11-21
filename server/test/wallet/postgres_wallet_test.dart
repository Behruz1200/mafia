import 'package:contracts/contracts.dart';
import 'package:postgres/postgres.dart';
import 'package:server/wallet/wallet_module.dart';
import 'package:test/test.dart';

import 'pg_harness.dart';

void main() {
  late TestDatabase db;
  late PostgresWallet wallet;
  var n = 0;

  setUpAll(() async {
    if (testDatabaseUrl == null) return;
    db = await TestDatabase.create();
  });
  tearDownAll(() async {
    if (testDatabaseUrl == null) return;
    await db.dispose();
  });
  setUp(() {
    if (testDatabaseUrl == null) return;
    wallet = PostgresWallet(db.pool, houseCutPercent: 10);
    n++;
  });

  /// Fresh user ids per test, so tests share one database safely.
  List<String> users(int count) => [
    for (var i = 0; i < count; i++) 't${n}_u$i',
  ];
  String match() => 't${n}_match';

  Future<void> fund(List<String> ids, int coins) async {
    for (final u in ids) {
      await wallet.grantReward(u, coins, reference: 'seed');
    }
  }

  Future<int> available(String u) async => (await wallet.balance(u)).available;

  /// The ledger explains every balance exactly.
  Future<void> expectLedgerMatches(List<String> ids) async {
    for (final u in ids) {
      final rows = await db.pool.execute(
        Sql.named(
          'SELECT coalesce(sum(delta), 0)::bigint FROM ledger WHERE user_id = @u',
        ),
        parameters: {'u': u},
      );
      expect(rows.first[0], await available(u), reason: 'ledger of $u');
    }
  }

  group('PostgresWallet', skip: skipWithoutDatabase, () {
    test('unknown players have an empty wallet', () async {
      final b = await wallet.balance('nobody');
      expect(b.available, 0);
      expect(b.inEscrow, 0);
    });

    test('rewards are given once per reference', () async {
      final [u] = users(1);
      expect(await wallet.grantReward(u, 500, reference: 'welcome'), isTrue);
      expect(await wallet.grantReward(u, 500, reference: 'welcome'), isFalse);
      expect(await available(u), 500);
      final h = await wallet.history(u);
      expect(h.single.kind, LedgerKind.reward);
      expect(h.single.balanceAfter, 500);
    });

    test('stakes are all or nothing', () async {
      final ps = users(3);
      await fund(ps.take(2).toList(), 200);
      await fund([ps[2]], 50);
      await expectLater(
        wallet.holdStakes(matchId: match(), players: ps, stake: 100),
        throwsA(
          isA<InsufficientCoins>().having((e) => e.userIds, 'who', [ps[2]]),
        ),
      );
      expect(await available(ps[0]), 200);
      expect(await available(ps[2]), 50);
      expect((await wallet.balance(ps[0])).inEscrow, 0);
    });

    test('free matches move no coins', () async {
      final ps = users(2);
      await wallet.holdStakes(matchId: match(), players: ps, stake: 0);
      expect((await wallet.history(ps[0])), isEmpty);
    });

    test('winners split the pot minus the house cut', () async {
      final ps = users(4);
      await fund(ps, 1000);
      await wallet.holdStakes(matchId: match(), players: ps, stake: 100);
      expect(await available(ps[0]), 900);
      expect((await wallet.balance(ps[0])).inEscrow, 100);

      await wallet.settle(
        MatchResult(
          roomId: 'r',
          matchId: match(),
          stake: 100,
          winningTeam: Team.town,
          winners: [ps[0], ps[1]],
          losers: [ps[2], ps[3]],
          endedAt: DateTime.utc(2026),
        ),
      );
      // pot 400, house 40, each winner 180 (their 100 back + 80).
      expect(await available(ps[0]), 1080);
      expect(await available(ps[1]), 1080);
      expect(await available(ps[2]), 900);
      expect(await available(ps[3]), 900);
      for (final p in ps) {
        expect((await wallet.balance(p)).inEscrow, 0);
      }
      final house = await wallet.history(houseAccount, limit: 1);
      expect(house.single.kind, LedgerKind.houseFee);
      expect(house.single.delta, 40);
      await expectLedgerMatches(ps);
    });

    test('coins are conserved when the pot does not divide evenly', () async {
      final ps = users(4);
      await fund(ps, 100);
      await wallet.holdStakes(matchId: match(), players: ps, stake: 33);
      await wallet.settle(
        MatchResult(
          roomId: 'r',
          matchId: match(),
          stake: 33,
          winningTeam: Team.mafia,
          winners: ps.take(3).toList(),
          losers: [ps[3]],
          endedAt: DateTime.utc(2026),
        ),
      );
      // pot 132, fee 13, 119 / 3 = 39 each, 2 left over go to the house.
      expect(await available(ps[0]), 100 - 33 + 39);
      final house = await wallet.history(houseAccount, limit: 1);
      expect(house.single.delta, 15);
      expect(house.single.reference, match());
    });

    test('settling twice pays once, holding twice charges once', () async {
      final ps = users(2);
      await fund(ps, 100);
      await wallet.holdStakes(matchId: match(), players: ps, stake: 50);
      await wallet.holdStakes(matchId: match(), players: ps, stake: 50);
      expect(await available(ps[0]), 50);
      final result = MatchResult(
        roomId: 'r',
        matchId: match(),
        stake: 50,
        winningTeam: Team.town,
        winners: [ps[0]],
        losers: [ps[1]],
        endedAt: DateTime.utc(2026),
      );
      await wallet.settle(result);
      await wallet.settle(result);
      expect(await available(ps[0]), 50 + 90);
      expect(await available(ps[1]), 50);
      await expectLater(
        wallet.holdStakes(matchId: match(), players: ps, stake: 50),
        throwsStateError,
      );
    });

    test('a cancelled match returns every stake', () async {
      final ps = users(3);
      await fund(ps, 100);
      await wallet.holdStakes(matchId: match(), players: ps, stake: 40);
      await wallet.settle(
        MatchResult(
          roomId: 'r',
          matchId: match(),
          stake: 40,
          winners: const [],
          losers: const [],
          endedAt: DateTime.utc(2026),
        ),
      );
      for (final p in ps) {
        expect(await available(p), 100);
        expect((await wallet.balance(p)).inEscrow, 0);
      }
      await expectLedgerMatches(ps);
    });

    test('forfeited players and unknown winners are never paid', () async {
      final ps = users(3);
      await fund(ps, 100);
      await wallet.holdStakes(matchId: match(), players: ps, stake: 100);
      await wallet.settle(
        MatchResult(
          roomId: 'r',
          matchId: match(),
          stake: 100,
          winningTeam: Team.town,
          winners: [ps[0], ps[1], 'stranger'],
          losers: [ps[2]],
          forfeited: [ps[1]],
          endedAt: DateTime.utc(2026),
        ),
      );
      expect(await available(ps[0]), 270); // whole pot 300 minus 30
      expect(await available(ps[1]), 0);
      expect(await available('stranger'), 0);
    });

    test('parallel holds of one match charge once', () async {
      final ps = users(3);
      await fund(ps, 100);
      await Future.wait([
        for (var i = 0; i < 5; i++)
          wallet.holdStakes(matchId: match(), players: ps, stake: 30),
      ]);
      for (final p in ps) {
        expect(await available(p), 70);
      }
    });

    test('parallel matches sharing players never overdraw', () async {
      final ps = users(2);
      await fund(ps, 100);
      final results = await Future.wait([
        for (var i = 0; i < 4; i++)
          wallet
              .holdStakes(matchId: '${match()}_$i', players: ps, stake: 40)
              .then((_) => true, onError: (Object e) => false),
      ]);
      expect(results.where((ok) => ok).length, 2);
      expect(await available(ps[0]), 20);
      expect((await wallet.balance(ps[0])).inEscrow, 80);
    });

    test('a purchase credits once and belongs to one account', () async {
      final [u, other] = users(2);
      final p = VerifiedPurchase(
        store: Store.appStore,
        transactionId: 'tx_${match()}',
        productId: 'coins_500',
        coins: 550,
      );
      expect((await wallet.creditPurchase(u, p)).available, 550);
      expect((await wallet.creditPurchase(u, p)).available, 550);
      await expectLater(
        wallet.creditPurchase(other, p),
        throwsA(isA<PurchaseBelongsToAnotherUser>()),
      );
      expect(await available(other), 0);
    });

    test('a refund takes the coins back, even below zero', () async {
      final ps = users(2);
      final tx = 'tx_${match()}';
      await wallet.creditPurchase(
        ps[0],
        VerifiedPurchase(
          store: Store.appStore,
          transactionId: tx,
          productId: 'coins_100',
          coins: 100,
        ),
      );
      await fund([ps[1]], 100);
      await wallet.holdStakes(matchId: match(), players: ps, stake: 100);
      await wallet.settle(
        MatchResult(
          roomId: 'r',
          matchId: match(),
          stake: 100,
          winningTeam: Team.town,
          winners: [ps[1]],
          losers: [ps[0]],
          endedAt: DateTime.utc(2026),
        ),
      );
      expect(await wallet.clawBackPurchase(Store.appStore, tx), isTrue);
      expect(await wallet.clawBackPurchase(Store.appStore, tx), isTrue);
      expect(await available(ps[0]), -100);
      await expectLedgerMatches(ps);
      expect(await wallet.clawBackPurchase(Store.appStore, 'nope'), isFalse);
      // A negative balance cannot stake.
      await expectLater(
        wallet.holdStakes(matchId: '${match()}_2', players: ps, stake: 1),
        throwsA(isA<InsufficientCoins>()),
      );
    });

    test('the ledger cannot be edited or deleted', () async {
      final [u] = users(1);
      await fund([u], 10);
      await expectLater(
        db.pool.execute(
          Sql.named('UPDATE ledger SET delta = 999 WHERE user_id = @u'),
          parameters: {'u': u},
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        db.pool.execute(
          Sql.named('DELETE FROM ledger WHERE user_id = @u'),
          parameters: {'u': u},
        ),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
