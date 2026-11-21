import 'dart:convert';
import 'dart:math';

import 'package:contracts/contracts.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

const _issuer = 'mafia';
const _audience = 'mafia-app';

/// Short-lived access tokens: HS256 JWTs signed with `JWT_SECRET`,
/// `sub` = user id.
class AccessTokens {
  AccessTokens(this._secret, {this.ttl = const Duration(minutes: 15)})
    : assert(_secret.isNotEmpty);

  final String _secret;
  final Duration ttl;

  String issue(UserId userId, DateTime now) => JWT(
    {'iat': now.millisecondsSinceEpoch ~/ 1000},
    subject: userId,
    issuer: _issuer,
    audience: Audience.one(_audience),
  ).sign(SecretKey(_secret), algorithm: JWTAlgorithm.HS256, expiresIn: ttl);

  /// The user id, or null when the token is bad, forged or expired.
  UserId? verify(String token) {
    try {
      // Pin the algorithm: never trust the header to choose it.
      final header = JWT.decode(token).header;
      if (header?['alg'] != 'HS256') return null;
      final jwt = JWT.verify(
        token,
        SecretKey(_secret),
        issuer: _issuer,
        audience: Audience.one(_audience),
      );
      return jwt.subject;
    } on Object {
      return null;
    }
  }
}

final _random = Random.secure();

/// 32 random bytes, base64url. Given to the app once; only its hash is kept.
String newRefreshToken() =>
    base64Url.encode(List<int>.generate(32, (_) => _random.nextInt(256)));

/// SHA-256 hex of a refresh token, for storage and lookup.
String hashToken(String token) => sha256.convert(utf8.encode(token)).toString();

/// A [digits]-digit SMS code with leading zeros.
String newSmsCode([int digits = 6]) =>
    List.generate(digits, (_) => _random.nextInt(10)).join();

/// HMAC of the code, keyed by the server secret, so a database leak does not
/// reveal live codes (6 digits are easy to brute-force from a plain hash).
String hashSmsCode(String secret, String phone, String code) => Hmac(
  sha256,
  utf8.encode(secret),
).convert(utf8.encode('$phone:$code')).toString();

/// Compares two strings in constant time.
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
