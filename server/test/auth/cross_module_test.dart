import 'package:contracts/contracts.dart';
import 'package:server/auth/auth_guard.dart';
import 'package:server/auth/auth_module.dart';
import 'package:server/auth/auth_players.dart';
import 'package:server/rooms/jwt.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('rooms accept the access tokens accounts issue', () async {
    final h = Harness();
    final s = await h.signIn();
    expect(JwtTokenVerifier(testSecret).verify(s.accessToken), s.userId);
    expect(
      JwtTokenVerifier(testSecret)
          .verify(issueTestAccessToken('u1', testSecret)),
      'u1',
    );
  });

  test('rooms see real names and the 18+ flag', () async {
    final h = Harness();
    final s = await h.signIn();
    await h.service.updateMe(
      s.userId,
      UpdateProfileRequest(displayName: 'Timur', birthDate: DateTime(1990)),
    );
    final players = AuthPlayers(AuthModule(service: h.service));
    final p = await players.profile(s.userId);
    expect(p!.displayName, 'Timur');
    expect(p.isAdult, isTrue);
    expect(p.countryCode, 'UZ');
    expect(await players.profile('nobody'), isNull);
  });
}
