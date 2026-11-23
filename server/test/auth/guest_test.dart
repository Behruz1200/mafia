import 'package:server/auth/src/errors.dart';
import 'package:test/test.dart';

import 'auth_service_test.dart' show throwsAuth;
import 'helpers.dart';

void main() {
  test('guest sign-in is refused unless switched on', () async {
    final h = Harness();
    await expectLater(
      h.service.signInAsGuest(),
      throwsAuth(AuthError.guestDisabled),
    );
  });

  test('each guest is a new player from the launch country', () async {
    final h = Harness(guestSignIn: true);
    final a = await h.service.signInAsGuest();
    final b = await h.service.signInAsGuest();
    expect(a.userId, isNot(b.userId));
    expect(h.service.tokens.verify(a.accessToken), a.userId);

    final me = await h.service.me(a.userId);
    expect(me.countryCode, 'UZ');
    expect(me.hasBirthDate, isFalse);
    expect(me.displayName, startsWith('O‘yinchi '));
  });

  test('at most GUEST_PER_HOUR new guests an hour', () async {
    final h = Harness(guestSignIn: true, guestsPerHour: 2);
    await h.service.signInAsGuest();
    await h.service.signInAsGuest();
    await expectLater(
      h.service.signInAsGuest(),
      throwsAuth(AuthError.tooManyGuests),
    );
    h.clock.advance(const Duration(hours: 1));
    await h.service.signInAsGuest();
  });
}
