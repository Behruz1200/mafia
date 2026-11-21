/// How every other server module finds out who is calling.
///
/// `authenticate()` runs once for the whole app (see `lib/src/app.dart`).
/// For a valid `Authorization: Bearer <accessToken>` it puts the user id in
/// `request.context['userId']`; otherwise it passes the request through
/// untouched. Routes that need a player call [userIdOf] and answer 401
/// `unauthorized` when it is null.
library;

import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:shelf/shelf.dart';

import 'src/tokens.dart';

/// Key in `Request.context` that holds the signed-in user's id (a String).
const userIdKey = 'userId';

/// The signed-in user's id, or null for an anonymous request.
UserId? userIdOf(Request request) => request.context[userIdKey] as UserId?;

AccessTokens? _tokensFor(String? secret) {
  final s = secret ?? Platform.environment['JWT_SECRET'];
  return (s == null || s.isEmpty) ? null : AccessTokens(s);
}

/// Checks an access token, e.g. the socket's `?token=`. Returns the user id,
/// or null when it is missing, forged or expired. [secret] defaults to
/// `JWT_SECRET`.
UserId? verifyAccessToken(String token, {String? secret}) =>
    _tokensFor(secret)?.verify(token);

/// Reads the Bearer token and sets [userIdKey]. Never rejects a request.
Middleware authenticate({String? secret}) {
  final tokens = _tokensFor(secret);
  return (inner) => (request) {
    final header = request.headers['authorization'];
    if (tokens == null ||
        header == null ||
        !header.toLowerCase().startsWith('bearer ')) {
      return inner(request);
    }
    final id = tokens.verify(header.substring(7).trim());
    return inner(
      id == null ? request : request.change(context: {userIdKey: id}),
    );
  };
}

/// For other streams' tests: a valid access token for [userId].
String issueTestAccessToken(UserId userId, String secret) =>
    AccessTokens(secret).issue(userId, DateTime.now());
