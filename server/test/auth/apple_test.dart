import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:server/auth/src/apple.dart';
import 'package:server/auth/src/errors.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Makes a throwaway RSA key with openssl, standing in for Apple's.
Future<(RSAPrivateKey, RSAPublicKey)> _testKey() async {
  final dir = await Directory.systemTemp.createTemp('apple_key');
  final priv = '${dir.path}/k.pem';
  final pub = '${dir.path}/p.pem';
  await Process.run('openssl', ['genrsa', '-out', priv, '2048']);
  await Process.run('openssl', ['rsa', '-in', priv, '-pubout', '-out', pub]);
  final keys = (
    RSAPrivateKey(await File(priv).readAsString()),
    RSAPublicKey(await File(pub).readAsString()),
  );
  await dir.delete(recursive: true);
  return keys;
}

void main() {
  late RSAPrivateKey applePrivate;
  late AppleIdVerifier verifier;

  setUpAll(() async {
    final (priv, pub) = await _testKey();
    applePrivate = priv;
    verifier = AppleIdVerifier(
      audiences: {'uz.mafia.app'},
      keys: (kid) async => kid == 'k1' ? pub : null,
    );
  });

  String token({
    String aud = 'uz.mafia.app',
    String iss = 'https://appleid.apple.com',
    String nonce = 'raw-nonce',
    String kid = 'k1',
    Duration expiresIn = const Duration(minutes: 5),
    JWTKey? key,
    JWTAlgorithm alg = JWTAlgorithm.RS256,
  }) => JWT(
    {'nonce': sha256.convert(utf8.encode(nonce)).toString()},
    subject: '001234.abcd',
    issuer: iss,
    audience: Audience.one(aud),
    header: {'kid': kid},
  ).sign(key ?? applePrivate, algorithm: alg, expiresIn: expiresIn);

  Matcher rejected = throwsA(
    isA<AuthError>().having((e) => e.code, 'code', 'apple_token_invalid'),
  );

  test('accepts a token Apple signed for our app', () async {
    expect(await verifier.verify(token(), 'raw-nonce'), '001234.abcd');
  });

  test('rejects another app, issuer, nonce, key or an expired token', () {
    expect(verifier.verify(token(aud: 'com.other'), 'raw-nonce'), rejected);
    expect(verifier.verify(token(iss: 'https://evil'), 'raw-nonce'), rejected);
    expect(verifier.verify(token(), 'other-nonce'), rejected);
    expect(verifier.verify(token(kid: 'k2'), 'raw-nonce'), rejected);
    expect(
      verifier.verify(
        token(expiresIn: const Duration(seconds: -10)),
        'raw-nonce',
      ),
      rejected,
    );
    expect(verifier.verify('not-a-jwt', 'raw-nonce'), rejected);
  });

  test('rejects an HS256 token, even one signed with a guessable key', () {
    final forged = token(key: SecretKey('x'), alg: JWTAlgorithm.HS256);
    expect(verifier.verify(forged, 'raw-nonce'), rejected);
  });

  test('says so when Apple sign-in is not configured', () {
    final off = AppleIdVerifier(audiences: const {}, keys: (_) async => null);
    expect(
      off.verify(token(), 'raw-nonce'),
      throwsA(
        isA<AuthError>().having((e) => e.code, 'code', 'apple_not_configured'),
      ),
    );
  });

  test('signs up once per Apple id and keeps the first name', () async {
    final h = Harness(apple: verifier);
    final a = await h.service.signInWithApple(
      AppleSignInRequest(
        identityToken: token(),
        rawNonce: 'raw-nonce',
        displayName: 'Kamola',
      ),
    );
    final b = await h.service.signInWithApple(
      AppleSignInRequest(identityToken: token(), rawNonce: 'raw-nonce'),
    );
    expect(b.userId, a.userId);
    final me = await h.service.me(a.userId);
    expect(me.displayName, 'Kamola');
    expect(me.countryCode, isNull);
  });
}
