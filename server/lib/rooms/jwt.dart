import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:crypto/crypto.dart';

import 'ports.dart';

/// Checks HS256 access tokens signed with `JWT_SECRET`.
///
/// Expected claims: `sub` (the user id), `exp` (seconds since epoch), and
/// optionally `typ: "access"`. Stream 5 issues tokens in this shape; if it
/// picks another format it can plug its own [TokenVerifier] in instead.
class JwtTokenVerifier implements TokenVerifier {
  JwtTokenVerifier(String secret, {DateTime Function()? now})
    : _hmac = Hmac(sha256, utf8.encode(secret)),
      _now = now ?? DateTime.now {
    if (secret.length < 16) {
      throw ArgumentError('JWT_SECRET must be at least 16 characters');
    }
  }

  final Hmac _hmac;
  final DateTime Function() _now;

  @override
  UserId? verify(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final header = _decode(parts[0]);
      if (header['alg'] != 'HS256') return null;
      final expected = _hmac.convert(utf8.encode('${parts[0]}.${parts[1]}'));
      if (!_sameBytes(expected.bytes, base64Url.decode(_pad(parts[2])))) {
        return null;
      }
      final claims = _decode(parts[1]);
      final exp = claims['exp'];
      if (exp is! int) return null;
      if (_now().millisecondsSinceEpoch ~/ 1000 >= exp) return null;
      final typ = claims['typ'];
      if (typ != null && typ != 'access') return null;
      final sub = claims['sub'];
      return sub is String && sub.isNotEmpty ? sub : null;
    } on FormatException {
      return null;
    }
  }

  /// Signs claims the same way. Used by tests and local tools only.
  String sign(Map<String, Object?> claims) {
    String enc(Object o) =>
        base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final head = enc({'alg': 'HS256', 'typ': 'JWT'});
    final body = enc(claims);
    final sig = _hmac.convert(utf8.encode('$head.$body')).bytes;
    return '$head.$body.${base64Url.encode(sig).replaceAll('=', '')}';
  }

  static Json _decode(String part) {
    final v = jsonDecode(utf8.decode(base64Url.decode(_pad(part))));
    if (v is! Map<String, Object?>) throw const FormatException('not object');
    return v;
  }

  static String _pad(String s) => s.padRight((s.length + 3) ~/ 4 * 4, '=');

  /// Constant-time compare, so the signature check leaks nothing by timing.
  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
