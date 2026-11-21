import 'dart:async';
import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mafia_app/features/shop/data/http_wallet_repository.dart';
import 'package:mafia_app/features/shop/data/store_billing.dart';

class FakeBilling implements StoreBilling {
  final finished = <String>[];
  final unfinishedCtrl = StreamController<StorePurchase>.broadcast();
  Object? failWith;

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<Map<String, String>> prices(List<String> ids) async => {
    for (final id in ids) id: '10 000 so‘m',
  };
  @override
  Future<StorePurchase> buy(String productId) async {
    if (failWith case final e?) throw e;
    return StorePurchase(
      store: Store.appStore,
      productId: productId,
      transactionId: 'tx-$productId',
      verificationData: 'jws',
    );
  }

  @override
  Future<void> finish(StorePurchase p) async => finished.add(p.transactionId);
  @override
  Stream<StorePurchase> get unfinished => unfinishedCtrl.stream;
  @override
  void dispose() {}
}

void main() {
  late FakeBilling billing;
  late List<http.Request> sent;
  late http.Response Function(http.Request) server;

  HttpWalletRepository repo({String? token = 'tok'}) => HttpWalletRepository(
    baseUrl: 'https://api.test',
    accessToken: () => token,
    billing: billing,
    client: MockClient((req) async {
      sent.add(req);
      return server(req);
    }),
  );

  http.Response ok(Object body) => http.Response(jsonEncode(body), 200);
  http.Response err(int status, String code) =>
      http.Response(jsonEncode({'error': code}), status);

  setUp(() {
    billing = FakeBilling();
    sent = [];
    server = (_) => ok({'userId': 'u', 'available': 0});
  });

  test('reads the balance with the bearer token', () async {
    server = (_) => ok({'userId': 'u', 'available': 70, 'inEscrow': 30});
    final b = await repo().watchBalance().first;
    expect(b.available, 70);
    expect(b.inEscrow, 30);
    expect(sent.single.url.path, ApiRoutes.wallet);
    expect(sent.single.headers['authorization'], 'Bearer tok');
  });

  test('a purchase is verified by the server, then finished', () async {
    server = (req) {
      expect(req.url.path, ApiRoutes.purchases);
      final body = PurchaseRequest.fromJson(jsonDecode(req.body) as Json);
      expect(body.transactionId, 'tx-coins_500');
      return ok({'userId': 'u', 'available': 550});
    };
    final b = await repo().buy(
      const CoinPack(productId: 'coins_500', coins: 500),
    );
    expect(b.available, 550);
    expect(billing.finished, ['tx-coins_500']);
  });

  test('server down: the purchase stays open for the next launch', () async {
    server = (_) => err(503, 'store_unavailable');
    await expectLater(
      repo().buy(const CoinPack(productId: 'coins_100', coins: 100)),
      throwsA(
        isA<WalletException>().having((e) => e.isTemporary, 'temp', true),
      ),
    );
    expect(billing.finished, isEmpty);
  });

  test('a purchase the server refuses is closed with the store', () async {
    server = (_) => err(400, 'purchase_invalid');
    await expectLater(
      repo().buy(const CoinPack(productId: 'coins_100', coins: 100)),
      throwsA(isA<WalletException>()),
    );
    expect(billing.finished, ['tx-coins_100']);
  });

  test('cancelling in the store sends nothing', () async {
    billing.failWith = const PurchaseCancelled();
    await expectLater(
      repo().buy(const CoinPack(productId: 'coins_100', coins: 100)),
      throwsA(isA<PurchaseCancelled>()),
    );
    expect(sent, isEmpty);
  });

  test('purchases left over from an earlier launch are delivered', () async {
    server = (_) => ok({'userId': 'u', 'available': 100});
    final r = repo();
    final next = r.watchBalance().firstWhere((b) => b.available == 100);
    billing.unfinishedCtrl.add(
      const StorePurchase(
        store: Store.appStore,
        productId: 'coins_100',
        transactionId: 'old',
        verificationData: 'jws',
      ),
    );
    await next;
    await pumpEventQueue();
    expect(billing.finished, ['old']);
  });

  test('signed out: no request is made', () async {
    await expectLater(
      repo(token: null).history(),
      throwsA(isA<WalletException>()),
    );
    expect(sent, isEmpty);
  });

  test('history and packs decode the contract types', () async {
    server = (req) => req.url.path == ApiRoutes.ledger
        ? ok([
            LedgerEntry(
              id: '1',
              userId: 'u',
              kind: LedgerKind.matchPayout,
              delta: 180,
              balanceAfter: 1080,
              createdAt: DateTime.utc(2026),
            ).toJson(),
          ])
        : ok([const CoinPack(productId: 'coins_100', coins: 100).toJson()]);
    final r = repo();
    expect((await r.history(limit: 5)).single.kind, LedgerKind.matchPayout);
    expect(sent.last.url.queryParameters['limit'], '5');
    expect((await r.coinPacks()).single.productId, 'coins_100');
  });
}
