import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server/wallet/app_store.dart';
import 'package:server/wallet/wallet_config.dart';
import 'package:test/test.dart';

String jws(Map<String, Object?> p) =>
    'e30.${base64Url.encode(utf8.encode(jsonEncode(p))).replaceAll('=', '')}.s';

/// A throwaway P-256 key made at test time (never a real key in the repo).
String? testKey() {
  try {
    final r = Process.runSync('openssl', [
      'genpkey',
      '-algorithm',
      'EC',
      '-pkeyopt',
      'ec_paramgen_curve:P-256',
    ]);
    return r.exitCode == 0 ? r.stdout as String : null;
  } on ProcessException {
    return null;
  }
}

void main() {
  test('reads the fields we use from a transaction payload', () {
    final t = AppStoreTransaction.fromPayload(
      unverifiedJwsPayload(
        jws({
          'transactionId': '2000001',
          'productId': 'coins_500',
          'bundleId': 'uz.mafia.app',
          'environment': 'Sandbox',
          'type': 'Consumable',
          'purchaseDate': 1795000000000,
          'revocationDate': 1795000100000,
        }),
      ),
    );
    expect(t.originalTransactionId, '2000001');
    expect(t.isSandbox, isTrue);
    expect(t.isRevoked, isTrue);
    expect(t.purchaseDate!.isUtc, isTrue);
  });

  test('rejects strings that are not a JWS', () {
    expect(() => unverifiedJwsPayload('abc'), throwsFormatException);
  });

  final key = testKey();
  group('App Store Server API', skip: key == null ? 'needs openssl' : null, () {
    AppleConfig cfg(SandboxPolicy s) => AppleConfig(
      bundleId: 'uz.mafia.app',
      issuerId: 'issuer-1',
      keyId: 'KEY123',
      privateKeyPem: key!,
      sandbox: s,
    );

    test('signs requests and falls back to the sandbox', () async {
      final hosts = <String>[];
      final client = MockClient((req) async {
        hosts.add(req.url.host);
        final token = req.headers['authorization']!.substring(7);
        final decoded = JWT.decode(token);
        expect(decoded.header!['kid'], 'KEY123');
        expect(decoded.header!['alg'], 'ES256');
        expect(decoded.payload['bid'], 'uz.mafia.app');
        expect(decoded.payload['aud'], 'appstoreconnect-v1');
        expect(req.url.path, '/inApps/v1/transactions/42');
        if (req.url.host.contains('sandbox')) {
          return http.Response(
            jsonEncode({
              'signedTransactionInfo': jws({
                'transactionId': '42',
                'productId': 'coins_100',
                'bundleId': 'uz.mafia.app',
                'environment': 'Sandbox',
                'type': 'Consumable',
              }),
            }),
            200,
          );
        }
        return http.Response('{"errorCode":4040010}', 404);
      });

      final api = AppStoreServerApi(cfg(SandboxPolicy.allow), client: client);
      final t = await api.transaction('42');
      expect(t!.productId, 'coins_100');
      expect(hosts, [
        'api.storekit.itunes.apple.com',
        'api.storekit-sandbox.itunes.apple.com',
      ]);

      hosts.clear();
      final strict = AppStoreServerApi(cfg(SandboxPolicy.deny), client: client);
      expect(await strict.transaction('42'), isNull);
      expect(hosts, ['api.storekit.itunes.apple.com']);
    });

    test('Apple outages are reported, not treated as "not found"', () async {
      final api = AppStoreServerApi(
        cfg(SandboxPolicy.allow),
        client: MockClient((_) async => http.Response('down', 500)),
      );
      expect(api.transaction('1'), throwsA(isA<AppStoreUnavailable>()));
    });
  });

  group('WalletConfig', () {
    test('is off without a database', () {
      expect(WalletConfig.fromEnvironment({}), isNull);
    });

    test('reads packs and cut, Apple stays off until fully configured', () {
      final c = WalletConfig.fromEnvironment({
        'DATABASE_URL': 'postgres://x',
        'HOUSE_CUT_PERCENT': '15',
        'COIN_PACKS': 'coins_100:100,coins_500:500:50',
        'APPLE_BUNDLE_ID': 'uz.mafia.app',
      })!;
      expect(c.houseCutPercent, 15);
      expect(c.welcomeCoins, 500); // 5 games at the typical stake of 100
      expect(c.packFor('coins_500')!.bonusCoins, 50);
      expect(c.packFor('coins_1200'), isNull);
      expect(c.apple, isNull);
    });

    test('rejects nonsense', () {
      expect(
        () => WalletConfig.fromEnvironment({
          'DATABASE_URL': 'x',
          'HOUSE_CUT_PERCENT': '150',
        }),
        throwsStateError,
      );
      expect(() => WalletConfig.parsePacks('coins:-5'), throwsFormatException);
    });
  });
}
