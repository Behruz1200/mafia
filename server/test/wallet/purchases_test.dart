import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:server/wallet/wallet_module.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'pg_harness.dart';

const bundle = 'uz.mafia.app';

class FakeAppStore implements AppStoreVerifier {
  final known = <String, AppStoreTransaction>{};
  var lookups = 0;

  void add(
    String id, {
    String product = 'coins_500',
    String bundleId = bundle,
    String env = 'Production',
    String type = 'Consumable',
    DateTime? revoked,
  }) => known[id] = AppStoreTransaction(
    transactionId: id,
    originalTransactionId: id,
    productId: product,
    bundleId: bundleId,
    environment: env,
    type: type,
    revocationDate: revoked,
  );

  @override
  Future<AppStoreTransaction?> transaction(String id) async {
    lookups++;
    return known[id];
  }
}

/// A JWS-shaped string with an unsigned payload, like Apple sends.
String fakeJws(Map<String, Object?> payload) =>
    'e30.${base64Url.encode(utf8.encode(jsonEncode(payload)))}.sig';

void main() {
  late TestDatabase db;
  late FakeAppStore apple;
  late WalletServices services;
  late Handler app;
  var n = 0;

  WalletConfig config({SandboxPolicy sandbox = SandboxPolicy.allow}) =>
      WalletConfig(
        databaseUrl: 'unused',
        apple: AppleConfig(
          bundleId: bundle,
          issuerId: 'i',
          keyId: 'k',
          privateKeyPem: '',
          sandbox: sandbox,
        ),
      );

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
    n++;
    apple = FakeAppStore();
    services = WalletServices.connect(config(), db: db.pool, appStore: apple);
    final router = Router();
    WalletModule(services: services).mount(router);
    app = router.call;
  });

  String user() => 'p${n}_user';
  String txId([String s = '']) => 'p${n}_tx$s';

  Future<Response> call(
    String method,
    String path, {
    String? as,
    Object? body,
  }) async => app(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body == null ? null : jsonEncode(body),
      context: {'userId': ?as},
    ),
  );

  Future<Object?> bodyOf(Response r) async =>
      jsonDecode(await r.readAsString());

  PurchaseRequest buy(String tx, {String product = 'coins_500'}) =>
      PurchaseRequest(
        store: Store.appStore,
        productId: product,
        transactionId: tx,
        verificationData: 'jws-from-the-app',
      );

  group('purchases', skip: skipWithoutDatabase, () {
    test('a verified purchase credits pack coins plus bonus', () async {
      apple.add(txId());
      final b = await services.purchases.verifyAndCredit(user(), buy(txId()));
      expect(b.available, 550);
    });

    test('rejects what Apple does not confirm', () async {
      Future<String> code(PurchaseRequest r) => services.purchases
          .verifyAndCredit(user(), r)
          .then(
            (_) => 'ok',
            onError: (Object e) => (e as PurchaseRejected).code,
          );

      expect(await code(buy('made-up')), 'purchase_not_found');
      apple.add(txId('a'), bundleId: 'com.other.app');
      expect(await code(buy(txId('a'))), 'purchase_invalid');
      apple.add(txId('b'), product: 'coins_100');
      expect(await code(buy(txId('b'))), 'purchase_invalid'); // product swap
      apple.add(txId('c'), type: 'Auto-Renewable Subscription');
      expect(await code(buy(txId('c'))), 'purchase_invalid');
      apple.add(txId('d'), revoked: DateTime.utc(2026));
      expect(await code(buy(txId('d'))), 'purchase_refunded');
      apple.add(txId('e'), product: 'coins_9999');
      expect(
        await code(buy(txId('e'), product: 'coins_9999')),
        'unknown_product',
      );
      expect(
        await code(
          const PurchaseRequest(
            store: Store.playStore,
            productId: 'coins_500',
            transactionId: 'x',
            verificationData: 'x',
          ),
        ),
        'store_not_supported',
      );
      expect((await services.wallet.balance(user())).available, 0);
    });

    test('sandbox purchases can be refused', () async {
      final strict = WalletServices.connect(
        config(sandbox: SandboxPolicy.deny),
        db: db.pool,
        appStore: apple,
      );
      apple.add(txId(), env: 'Sandbox');
      await expectLater(
        strict.purchases.verifyAndCredit(user(), buy(txId())),
        throwsA(isA<PurchaseRejected>()),
      );
      expect(
        (await services.purchases.verifyAndCredit(
          user(),
          buy(txId()),
        )).available,
        550,
      );
    });

    test('purchases refuse when Apple is not configured', () async {
      final noApple = WalletServices.connect(
        const WalletConfig(databaseUrl: 'unused'),
        db: db.pool,
      );
      await expectLater(
        noApple.purchases.verifyAndCredit(user(), buy(txId())),
        throwsA(
          isA<PurchaseRejected>().having(
            (e) => e.code,
            'code',
            'store_not_configured',
          ),
        ),
      );
    });

    test(
      'a refund notification claws back only after Apple confirms',
      () async {
        apple.add(txId());
        await services.purchases.verifyAndCredit(user(), buy(txId()));
        final notice = jsonEncode({
          'signedPayload': fakeJws({
            'notificationType': 'REFUND',
            'data': {
              'signedTransactionInfo': fakeJws({'transactionId': txId()}),
            },
          }),
        });

        // Forged: Apple still says the purchase is fine.
        expect(
          await services.purchases.handleAppStoreNotification(notice),
          'ignored:not-revoked',
        );
        expect((await services.wallet.balance(user())).available, 550);

        apple.add(txId(), revoked: DateTime.utc(2026));
        expect(
          await services.purchases.handleAppStoreNotification(notice),
          'clawed-back',
        );
        expect(
          await services.purchases.handleAppStoreNotification(notice),
          'clawed-back',
        );
        expect((await services.wallet.balance(user())).available, 0);
      },
    );

    test('other notifications are acknowledged and ignored', () async {
      final notice = jsonEncode({
        'signedPayload': fakeJws({'notificationType': 'TEST'}),
      });
      expect(
        await services.purchases.handleAppStoreNotification(notice),
        'ignored:TEST',
      );
      expect(apple.lookups, 0);
      await expectLater(
        services.purchases.handleAppStoreNotification('not json'),
        throwsA(isA<PurchaseRejected>()),
      );
    });
  });

  group('routes', skip: skipWithoutDatabase, () {
    test('need a signed-in player', () async {
      for (final path in [
        ApiRoutes.wallet,
        ApiRoutes.ledger,
        ApiRoutes.coinPacks,
      ]) {
        final r = await call('GET', path);
        expect(r.statusCode, 401, reason: path);
        expect(await bodyOf(r), containsPair('error', 'unauthorized'));
      }
    });

    test('balance, packs, purchase and history', () async {
      final empty = await call('GET', ApiRoutes.wallet, as: user());
      expect(
        WalletBalance.fromJson((await bodyOf(empty))! as Json).available,
        0,
      );

      final packs = await call('GET', ApiRoutes.coinPacks, as: user());
      final list = [
        for (final p in (await bodyOf(packs))! as List)
          CoinPack.fromJson(p as Json),
      ];
      expect(list.map((p) => p.productId), contains('coins_500'));

      apple.add(txId());
      final bought = await call(
        'POST',
        ApiRoutes.purchases,
        as: user(),
        body: buy(txId()).toJson(),
      );
      expect(bought.statusCode, 200);
      expect(
        WalletBalance.fromJson((await bodyOf(bought))! as Json).available,
        550,
      );

      final stolen = await call(
        'POST',
        ApiRoutes.purchases,
        as: 'someone_else',
        body: buy(txId()).toJson(),
      );
      expect(stolen.statusCode, 409);
      expect(
        await bodyOf(stolen),
        containsPair('error', 'purchase_other_account'),
      );

      final history = await call(
        'GET',
        '${ApiRoutes.ledger}?limit=5',
        as: user(),
      );
      final rows = [
        for (final e in (await bodyOf(history))! as List)
          LedgerEntry.fromJson(e as Json),
      ];
      expect(rows.single.kind, LedgerKind.purchase);
      expect(rows.single.delta, 550);
    });

    test('bad purchase bodies get 400', () async {
      final r = await call(
        'POST',
        ApiRoutes.purchases,
        as: user(),
        body: {'nope': true},
      );
      expect(r.statusCode, 400);
    });

    test('App Store notifications need no session', () async {
      final r = await call(
        'POST',
        ApiRoutes.appStoreNotifications,
        body: {
          'signedPayload': fakeJws({'notificationType': 'TEST'}),
        },
      );
      expect(r.statusCode, 200);
    });
  });
}
