import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mafia_app/features/auth/data/api.dart';
import 'package:mafia_app/features/auth/data/http_auth_repository.dart';
import 'package:mafia_app/features/auth/data/session_storage.dart';
import 'package:mafia_app/features/profile/data/http_profile_repository.dart';

AuthSession session(String n, DateTime expires) => AuthSession(
  userId: 'u1',
  accessToken: 'access-$n',
  refreshToken: 'refresh-$n',
  expiresAt: expires,
);

/// A tiny stand-in for the game server's accounts routes.
class FakeServer {
  final calls = <String>[];
  var refreshWorks = true;
  var refreshCount = 0;
  var profile = UserProfile(
    userId: 'u1',
    displayName: 'O‘yinchi 1234',
    countryCode: 'UZ',
    createdAt: DateTime.utc(2026),
  );

  late final client = MockClient((req) async {
    final body = req.body.isEmpty ? null : jsonDecode(req.body) as Json;
    calls.add('${req.method} ${req.url.path}');
    http.Response ok(Object? j) => http.Response(
      jsonEncode(j),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    http.Response err(int s, String code) =>
        http.Response(jsonEncode({'error': code}), s);
    final authed =
        req.headers['authorization']?.startsWith('Bearer access-') ?? false;

    switch ('${req.method} ${req.url.path}') {
      case 'POST ${ApiRoutes.authPhoneStart}':
        return ok({'ok': true});
      case 'POST ${ApiRoutes.authPhoneVerify}':
        return body!['code'] == '123456'
            ? ok(
                session(
                  '1',
                  DateTime.now().add(const Duration(minutes: 15)),
                ).toJson(),
              )
            : err(400, 'code_invalid');
      case 'POST ${ApiRoutes.authRefresh}':
        if (!refreshWorks) return err(401, 'refresh_invalid');
        refreshCount++;
        return ok(
          session(
            'r$refreshCount',
            DateTime.now().add(const Duration(minutes: 15)),
          ).toJson(),
        );
      case 'POST ${ApiRoutes.authSignOut}':
        return http.Response('', 204);
      case 'GET ${ApiRoutes.me}':
        return authed ? ok(profile.toJson()) : err(401, 'unauthorized');
      case 'PATCH ${ApiRoutes.me}':
        if (!authed) return err(401, 'unauthorized');
        final r = UpdateProfileRequest.fromJson(body!);
        profile = UserProfile(
          userId: 'u1',
          displayName: r.displayName ?? profile.displayName,
          countryCode: 'UZ',
          locale: r.locale ?? profile.locale,
          isAdult: r.birthDate != null || profile.isAdult,
          hasBirthDate: r.birthDate != null || profile.hasBirthDate,
          createdAt: profile.createdAt,
        );
        return ok(profile.toJson());
      case 'DELETE ${ApiRoutes.me}':
        return authed ? http.Response('', 204) : err(401, 'unauthorized');
    }
    return err(404, 'not_found');
  });
}

void main() {
  late FakeServer server;
  late MemorySessionStorage storage;
  late HttpAuthRepository auth;

  HttpAuthRepository make() => HttpAuthRepository(
    api: AccountsApi(baseUrl: 'http://api', client: server.client),
    storage: storage,
    apple: () async => null,
  );

  setUp(() {
    server = FakeServer();
    storage = MemorySessionStorage();
    auth = make();
  });
  tearDown(() => auth.dispose());

  test('phone sign-in saves the session', () async {
    await auth.restored;
    expect(auth.currentSession, isNull);
    await auth.startPhoneSignIn('+998901234567');
    final s = await auth.verifyPhoneCode('+998901234567', '123456');
    expect(s.accessToken, 'access-1');
    expect(storage.session?.refreshToken, 'refresh-1');
  });

  test('a wrong code comes back as its server error code', () async {
    await expectLater(
      auth.verifyPhoneCode('+998901234567', '000000'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'code_invalid'),
      ),
    );
    expect(auth.currentSession, isNull);
  });

  test('restores a saved session and refreshes it when stale', () async {
    auth.dispose();
    storage.session = session(
      'old',
      DateTime.now().subtract(const Duration(minutes: 1)),
    );
    auth = make();
    await auth.restored;
    expect(auth.currentSession!.accessToken, 'access-r1');
    expect(storage.session!.refreshToken, 'refresh-r1');
  });

  test('signs out when the server rejects the refresh token', () async {
    auth.dispose();
    server.refreshWorks = false;
    storage.session = session(
      'old',
      DateTime.now().subtract(const Duration(minutes: 1)),
    );
    auth = make();
    await auth.restored;
    expect(auth.currentSession, isNull);
    expect(storage.session, isNull);
  });

  test('two refreshes at once make one call', () async {
    await auth.verifyPhoneCode('+998901234567', '123456');
    await Future.wait([auth.refreshNow(), auth.refreshNow()]);
    expect(server.refreshCount, 1);
  });

  test('sign out and delete clear the session', () async {
    await auth.verifyPhoneCode('+998901234567', '123456');
    await auth.signOut();
    expect(auth.currentSession, isNull);
    expect(server.calls, contains('POST ${ApiRoutes.authSignOut}'));

    await auth.verifyPhoneCode('+998901234567', '123456');
    await auth.deleteAccount();
    expect(auth.currentSession, isNull);
    expect(server.calls, contains('DELETE ${ApiRoutes.me}'));
  });

  test('cancelling Apple sign-in is not an error the player sees', () async {
    await expectLater(
      auth.signInWithApple(),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'apple_canceled'),
      ),
    );
  });

  test('profile loads after sign-in and saves name and birth date', () async {
    final profiles = HttpProfileRepository(
      api: AccountsApi(baseUrl: 'http://api', client: server.client),
      auth: auth,
    );
    addTearDown(profiles.dispose);
    await auth.verifyPhoneCode('+998901234567', '123456');

    final first = await profiles.watchMyProfile().firstWhere((p) => p != null);
    expect(first!.hasBirthDate, isFalse);

    final named = await profiles.updateMyProfile(
      first.copyWith(displayName: 'Sardor'),
    );
    expect(named.displayName, 'Sardor');
    final aged = await profiles.setBirthDate(DateTime(1999, 1, 1));
    expect(aged.hasBirthDate, isTrue);
    expect(aged.isAdult, isTrue);
  });
}
