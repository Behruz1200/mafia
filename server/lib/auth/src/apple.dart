import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'errors.dart';

/// Looks up Apple's public signing key by key id.
typedef AppleKeyLookup = Future<JWTKey?> Function(String kid);

/// Checks Sign in with Apple identity tokens: signed by Apple (RS256),
/// issued by `https://appleid.apple.com`, for our app ([audiences] are the
/// bundle ids), not expired, and carrying the SHA-256 of the app's nonce.
class AppleIdVerifier {
  AppleIdVerifier({required this.audiences, AppleKeyLookup? keys})
    : _keys = keys ?? AppleJwks().keyFor;

  final Set<String> audiences;
  final AppleKeyLookup _keys;

  /// Returns Apple's stable user id (`sub`).
  Future<String> verify(String identityToken, String rawNonce) async {
    if (audiences.isEmpty) throw AuthError.appleNotConfigured;
    try {
      final header = JWT.decode(identityToken).header ?? const {};
      if (header['alg'] != 'RS256') throw AuthError.appleTokenInvalid;
      final key = await _keys(header['kid'] as String? ?? '');
      if (key == null) throw AuthError.appleTokenInvalid;

      final jwt = JWT.verify(
        identityToken,
        key,
        checkHeaderType: false, // Apple's header has no `typ`
        issuer: 'https://appleid.apple.com',
      );
      final aud = jwt.audience ?? const <String>[];
      if (!aud.any(audiences.contains)) throw AuthError.appleTokenInvalid;

      final payload = jwt.payload as Map<String, dynamic>;
      final wantNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      if (payload['nonce'] != wantNonce) throw AuthError.appleTokenInvalid;

      final sub = jwt.subject;
      if (sub == null || sub.isEmpty) throw AuthError.appleTokenInvalid;
      return sub;
    } on AuthError {
      rethrow;
    } on Object {
      throw AuthError.appleTokenInvalid;
    }
  }
}

/// Apple's published keys, fetched on demand and cached for a day.
class AppleJwks {
  AppleJwks({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;

  static final _url = Uri.parse('https://appleid.apple.com/auth/keys');
  final http.Client _client;
  final DateTime Function() _now;
  Map<String, JWTKey> _cache = const {};
  DateTime? _fetchedAt;

  Future<JWTKey?> keyFor(String kid) async {
    final stale =
        _fetchedAt == null ||
        _now().difference(_fetchedAt!) > const Duration(hours: 24);
    // Refetch when stale, or when Apple rotated to a key we have not seen
    // (at most once a minute, so bad tokens cannot hammer Apple).
    final unknownKid =
        !_cache.containsKey(kid) &&
        _now().difference(_fetchedAt ?? DateTime(0)) >
            const Duration(minutes: 1);
    if (stale || unknownKid) await _refresh();
    return _cache[kid];
  }

  Future<void> _refresh() async {
    final res = await _client.get(_url);
    if (res.statusCode != 200) return;
    final keys = (jsonDecode(res.body) as Map)['keys'] as List;
    _cache = {
      for (final k in keys.cast<Map<String, dynamic>>())
        k['kid'] as String: JWTKey.fromJWK(k),
    };
    _fetchedAt = _now();
  }
}
