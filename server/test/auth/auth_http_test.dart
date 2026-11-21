import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:server/auth/auth_guard.dart';
import 'package:server/auth/auth_module.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Harness h;
  late Handler app;

  setUp(() {
    h = Harness();
    final router = Router();
    AuthModule(service: h.service).mount(router);
    app = const Pipeline()
        .addMiddleware(authenticate(secret: testSecret))
        .addHandler(router.call);
  });

  Future<(int, Object?)> call(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async {
    final res = await app(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body == null ? null : jsonEncode(body),
        headers: {'authorization': ?(token == null ? null : 'Bearer $token')},
      ),
    );
    final text = await res.readAsString();
    return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
  }

  test('full flow: code, sign in, profile, refresh, delete', () async {
    var (status, body) = await call(
      'POST',
      ApiRoutes.authPhoneStart,
      body: const PhoneStartRequest(phoneE164: '+998901234567').toJson(),
    );
    expect(status, 200);

    (status, body) = await call(
      'POST',
      ApiRoutes.authPhoneVerify,
      body: PhoneVerifyRequest(
        phoneE164: '+998901234567',
        code: h.sms.lastCode,
      ).toJson(),
    );
    expect(status, 200);
    final session = AuthSession.fromJson(body! as Json);

    (status, body) = await call(
      'PATCH',
      ApiRoutes.me,
      token: session.accessToken,
      body: UpdateProfileRequest(
        displayName: 'Jasur',
        birthDate: DateTime(1995, 5, 5),
      ).toJson(),
    );
    expect(status, 200);
    final me = UserProfile.fromJson(body! as Json);
    expect(me.displayName, 'Jasur');
    expect(me.isAdult, isTrue);

    (status, body) = await call(
      'GET',
      ApiRoutes.me,
      token: session.accessToken,
    );
    expect(UserProfile.fromJson(body! as Json).displayName, 'Jasur');

    (status, body) = await call(
      'POST',
      ApiRoutes.authRefresh,
      body: RefreshRequest(refreshToken: session.refreshToken).toJson(),
    );
    expect(status, 200);
    final next = AuthSession.fromJson(body! as Json);

    (status, _) = await call('DELETE', ApiRoutes.me, token: next.accessToken);
    expect(status, 204);
    (status, body) = await call('GET', ApiRoutes.me, token: next.accessToken);
    expect(status, 404);
  });

  test('profile routes need a valid token', () async {
    var (status, body) = await call('GET', ApiRoutes.me);
    expect(status, 401);
    expect(ApiError.fromJson(body! as Json).code, 'unauthorized');

    (status, _) = await call('GET', ApiRoutes.me, token: 'forged.token.here');
    expect(status, 401);

    final other = issueTestAccessToken(
      'u1',
      'a-different-secret-32-chars-long!!',
    );
    (status, _) = await call('GET', ApiRoutes.me, token: other);
    expect(status, 401);
  });

  test('errors use ApiError codes the app can translate', () async {
    var (status, body) = await call(
      'POST',
      ApiRoutes.authPhoneStart,
      body: {'phone': '+79161234567'},
    );
    expect(status, 403);
    expect(ApiError.fromJson(body! as Json).code, 'country_not_supported');

    (status, body) = await call(
      'POST',
      ApiRoutes.authPhoneStart,
      body: {'nope': 1},
    );
    expect(status, 400);
    expect(ApiError.fromJson(body! as Json).code, 'bad_request');

    (status, body) = await call(
      'POST',
      ApiRoutes.authRefresh,
      body: const RefreshRequest(refreshToken: 'x').toJson(),
    );
    expect(status, 401);
    expect(ApiError.fromJson(body! as Json).code, 'refresh_invalid');
  });

  test('authenticate() sets the user id for other modules', () async {
    final token = issueTestAccessToken('user-42', testSecret);
    String? seen;
    final probe = authenticate(secret: testSecret)((req) {
      seen = userIdOf(req);
      return Response.ok('');
    });
    await probe(
      Request(
        'GET',
        Uri.parse('http://x/'),
        headers: {'authorization': 'Bearer $token'},
      ),
    );
    expect(seen, 'user-42');

    seen = 'unset';
    await probe(Request('GET', Uri.parse('http://x/')));
    expect(seen, isNull);
    expect(verifyAccessToken(token, secret: testSecret), 'user-42');
    expect(verifyAccessToken('${token}x', secret: testSecret), isNull);
  });

  test('without configuration the routes answer 503, not crash', () async {
    final router = Router();
    AuthModule().mount(router); // no JWT_SECRET or DATABASE_URL in tests
    final res = await router.call(
      Request(
        'POST',
        Uri.parse('http://localhost${ApiRoutes.authPhoneStart}'),
        body: '{"phone":"+998901234567"}',
      ),
    );
    expect(res.statusCode, 503);
  });
}
