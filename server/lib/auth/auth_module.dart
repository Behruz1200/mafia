import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../src/module.dart';
import 'auth_guard.dart';
import 'src/auth_service.dart';
import 'src/errors.dart';

/// Stream 5 (accounts). Phone sign-in by SMS code (Eskiz), Sign in with
/// Apple, JWT access tokens with rotating refresh tokens, profile, age gate
/// and account deletion. Profiles are stored only in this server's
/// PostgreSQL database. Settings: see `README.md` in this folder.
class AuthModule extends ServerModule {
  /// Without [service], the real one is built from environment variables
  /// on the first request, so the app (and its tests) start without a
  /// database.
  AuthModule({AuthService? service})
    : _service = service == null ? null : Future.value(service);

  Future<AuthService>? _service;

  Future<AuthService> get _svc =>
      _service ??= Future(AuthService.fromEnvironment);

  /// For other modules (rooms): a player's public profile, or null when the
  /// account does not exist or was deleted.
  Future<UserProfile?> profileOf(UserId id) async => (await _svc).profileOf(id);

  @override
  void mount(Router r) {
    r.post(
      ApiRoutes.authPhoneStart,
      _handle((s, req) async {
        final body = PhoneStartRequest.fromJson(await _body(req));
        await s.startPhone(body.phoneE164);
        return json({'ok': true});
      }),
    );
    r.post(
      ApiRoutes.authPhoneVerify,
      _handle((s, req) async {
        final body = PhoneVerifyRequest.fromJson(await _body(req));
        return json((await s.verifyPhone(body.phoneE164, body.code)).toJson());
      }),
    );
    r.post(
      ApiRoutes.authApple,
      _handle((s, req) async {
        final body = AppleSignInRequest.fromJson(await _body(req));
        return json((await s.signInWithApple(body)).toJson());
      }),
    );
    r.post(
      ApiRoutes.authRefresh,
      _handle((s, req) async {
        final body = RefreshRequest.fromJson(await _body(req));
        return json((await s.refresh(body.refreshToken)).toJson());
      }),
    );
    r.post(
      ApiRoutes.authSignOut,
      _handle((s, req) async {
        final body = RefreshRequest.fromJson(await _body(req));
        await s.signOut(body.refreshToken);
        return Response(204);
      }),
    );
    r.get(
      ApiRoutes.me,
      _handle((s, req) async => json((await s.me(_user(req))).toJson())),
    );
    r.patch(
      ApiRoutes.me,
      _handle((s, req) async {
        final body = UpdateProfileRequest.fromJson(await _body(req));
        return json((await s.updateMe(_user(req), body)).toJson());
      }),
    );
    r.delete(
      ApiRoutes.me,
      _handle((s, req) async {
        await s.deleteMe(_user(req));
        return Response(204);
      }),
    );
  }

  UserId _user(Request req) => userIdOf(req) ?? (throw AuthError.unauthorized);

  static Future<Json> _body(Request req) async {
    final text = await req.readAsString();
    if (text.length > 16 * 1024) throw AuthError.badRequest;
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) throw AuthError.badRequest;
    return decoded;
  }

  Handler _handle(FutureOr<Response> Function(AuthService s, Request req) fn) =>
      (req) async {
        final AuthService s;
        try {
          s = await _svc;
        } on Object catch (e) {
          stderr.writeln('Accounts are not configured: $e');
          _service = null; // try again on the next request
          return _error(const AuthError(503, 'auth_not_configured'));
        }
        try {
          return await fn(s, req);
        } on AuthError catch (e) {
          return _error(e);
        } on FormatException {
          return _error(AuthError.badRequest);
        } on TypeError {
          // A missing or wrongly typed field in the JSON body.
          return _error(AuthError.badRequest);
        } on ArgumentError {
          return _error(AuthError.badRequest);
        }
      };

  static Response _error(AuthError e) => json(
    ApiError(code: e.code, message: e.message).toJson(),
    status: e.status,
  );
}
