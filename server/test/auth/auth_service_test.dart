import 'package:contracts/contracts.dart';
import 'package:server/auth/src/errors.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Matcher throwsAuth(AuthError e) =>
    throwsA(isA<AuthError>().having((x) => x.code, 'code', e.code));

void main() {
  late Harness h;
  setUp(() => h = Harness());

  group('phone sign-in', () {
    test('sends a code and signs up a new player from Uzbekistan', () async {
      await h.service.startPhone('+998 90 123-45-67');
      expect(h.sms.sent.single.$1, '+998901234567');
      expect(h.sms.sent.single.$2, contains(h.sms.lastCode));

      final s = await h.service.verifyPhone('+998901234567', h.sms.lastCode);
      expect(h.service.tokens.verify(s.accessToken), s.userId);
      expect(s.expiresAt, h.clock.now.add(const Duration(minutes: 15)));

      final me = await h.service.me(s.userId);
      expect(me.countryCode, 'UZ');
      expect(me.locale, 'uz');
      expect(me.hasBirthDate, isFalse);
      expect(me.isAdult, isFalse);
      expect(me.displayName, startsWith('O‘yinchi '));
    });

    test('the same number signs in to the same account', () async {
      final a = await h.signIn();
      h.clock.advance(const Duration(minutes: 2));
      final b = await h.signIn();
      expect(b.userId, a.userId);
    });

    test('rejects bad numbers and countries that have not launched', () async {
      expect(h.service.startPhone('12345'), throwsAuth(AuthError.invalidPhone));
      expect(
        h.service.startPhone('+79161234567'),
        throwsAuth(AuthError.countryNotSupported),
      );
      expect(h.sms.sent, isEmpty);
    });

    test('a wrong code fails, and five wrong codes lock the code', () async {
      await h.service.startPhone('+998901234567');
      final good = h.sms.lastCode;
      final bad = good == '000000' ? '111111' : '000000';
      for (var i = 0; i < 4; i++) {
        await expectLater(
          h.service.verifyPhone('+998901234567', bad),
          throwsAuth(AuthError.codeInvalid),
        );
      }
      await expectLater(
        h.service.verifyPhone('+998901234567', bad),
        throwsAuth(AuthError.tooManyAttempts),
      );
      // Even the right code no longer works.
      await expectLater(
        h.service.verifyPhone('+998901234567', good),
        throwsAuth(AuthError.tooManyAttempts),
      );
    });

    test('a code works once and expires after five minutes', () async {
      await h.service.startPhone('+998901234567');
      final code = h.sms.lastCode;
      await h.service.verifyPhone('+998901234567', code);
      await expectLater(
        h.service.verifyPhone('+998901234567', code),
        throwsAuth(AuthError.codeInvalid),
      );

      h.clock.advance(const Duration(minutes: 1));
      await h.service.startPhone('+998901234567');
      h.clock.advance(const Duration(minutes: 6));
      await expectLater(
        h.service.verifyPhone('+998901234567', h.sms.lastCode),
        throwsAuth(AuthError.codeExpired),
      );
    });

    test('one code a minute, five an hour', () async {
      await h.service.startPhone('+998901234567');
      await expectLater(
        h.service.startPhone('+998901234567'),
        throwsAuth(AuthError.codeTooSoon),
      );
      for (var i = 0; i < 4; i++) {
        h.clock.advance(const Duration(minutes: 1, seconds: 1));
        await h.service.startPhone('+998901234567');
      }
      h.clock.advance(const Duration(minutes: 1, seconds: 1));
      await expectLater(
        h.service.startPhone('+998901234567'),
        throwsAuth(AuthError.tooManyCodes),
      );
      h.clock.advance(const Duration(hours: 1));
      await h.service.startPhone('+998901234567');
      expect(h.sms.sent, hasLength(6));
    });

    test('an SMS provider failure is reported, not hidden', () async {
      h.sms.fail = true;
      await expectLater(
        h.service.startPhone('+998901234567'),
        throwsAuth(AuthError.smsFailed),
      );
    });

    test('store reviewer numbers use a fixed code and send no SMS', () async {
      final r = Harness(testPhones: {'+998900000001': '424242'});
      await r.service.startPhone('+998900000001');
      expect(r.sms.sent, isEmpty);
      final s = await r.service.verifyPhone('+998900000001', '424242');
      expect(s.userId, isNotEmpty);
    });

    test('codes are stored hashed, never in plain text', () async {
      await h.service.startPhone('+998901234567');
      final rec = await h.accounts.phoneCode('+998901234567');
      expect(rec!.codeHash, isNot(contains(h.sms.lastCode)));
      expect(rec.codeHash, hasLength(64));
    });
  });

  group('sessions', () {
    test('refresh rotates the token, and the old one stops working', () async {
      final s1 = await h.signIn();
      h.clock.advance(const Duration(minutes: 20));
      final s2 = await h.service.refresh(s1.refreshToken);
      expect(s2.userId, s1.userId);
      expect(s2.refreshToken, isNot(s1.refreshToken));
      expect(h.service.tokens.verify(s2.accessToken), s1.userId);

      final s3 = await h.service.refresh(s2.refreshToken);
      expect(s3.userId, s1.userId);
    });

    test('reusing an old refresh token revokes the whole chain', () async {
      final s1 = await h.signIn();
      final s2 = await h.service.refresh(s1.refreshToken);
      await expectLater(
        h.service.refresh(s1.refreshToken),
        throwsAuth(AuthError.refreshInvalid),
      );
      // The thief's replay also logged out the newer token.
      await expectLater(
        h.service.refresh(s2.refreshToken),
        throwsAuth(AuthError.refreshInvalid),
      );
    });

    test('refresh tokens expire after 60 days', () async {
      final s = await h.signIn();
      h.clock.advance(const Duration(days: 61));
      await expectLater(
        h.service.refresh(s.refreshToken),
        throwsAuth(AuthError.refreshInvalid),
      );
    });

    test('sign out revokes the refresh token', () async {
      final s = await h.signIn();
      await h.service.signOut(s.refreshToken);
      await expectLater(
        h.service.refresh(s.refreshToken),
        throwsAuth(AuthError.refreshInvalid),
      );
      await h.service.signOut('unknown'); // no error
    });

    test('refresh tokens are stored hashed', () async {
      final s = await h.signIn();
      expect(
        h.store.sessions.values.map((x) => x.tokenHash),
        isNot(contains(s.refreshToken)),
      );
    });
  });

  group('profile', () {
    test('changes name and language, ignores what it does not own', () async {
      final s = await h.signIn();
      final p = await h.service.updateMe(
        s.userId,
        const UpdateProfileRequest(displayName: '  Aziza   K ', locale: 'ru'),
      );
      expect(p.displayName, 'Aziza K');
      expect(p.locale, 'ru');
      expect(p.countryCode, 'UZ');
    });

    test('rejects bad names and languages', () async {
      final s = await h.signIn();
      for (final name in ['', 'A', 'x' * 25, 'bad\u0000name']) {
        await expectLater(
          h.service.updateMe(s.userId, UpdateProfileRequest(displayName: name)),
          throwsAuth(AuthError.invalidName),
        );
      }
      await expectLater(
        h.service.updateMe(s.userId, const UpdateProfileRequest(locale: 'de')),
        throwsAuth(AuthError.invalidLocale),
      );
    });

    test('age gate: 18 and over is adult, the date is set once', () async {
      final s = await h.signIn();
      // Turns 18 tomorrow: not yet adult.
      final p = await h.service.updateMe(
        s.userId,
        UpdateProfileRequest(birthDate: DateTime(2008, 11, 22)),
      );
      expect(p.hasBirthDate, isTrue);
      expect(p.isAdult, isFalse);
      expect(p.toJson().keys, isNot(contains('birthDate')));

      await expectLater(
        h.service.updateMe(
          s.userId,
          UpdateProfileRequest(birthDate: DateTime(1990)),
        ),
        throwsAuth(AuthError.birthDateAlreadySet),
      );

      h.clock.advance(const Duration(days: 1));
      expect((await h.service.me(s.userId)).isAdult, isTrue);
    });

    test('rejects birth dates in the future', () async {
      final s = await h.signIn();
      await expectLater(
        h.service.updateMe(
          s.userId,
          UpdateProfileRequest(birthDate: DateTime(2030)),
        ),
        throwsAuth(AuthError.invalidBirthDate),
      );
    });

    test('deleting the account wipes personal data and sessions', () async {
      final s = await h.signIn();
      await h.service.updateMe(
        s.userId,
        UpdateProfileRequest(displayName: 'Aziza', birthDate: DateTime(1990)),
      );
      await h.service.deleteMe(s.userId);

      expect(await h.service.profileOf(s.userId), isNull);
      final row = h.store.users[s.userId]!;
      expect(row.phone, isNull);
      expect(row.birthDate, isNull);
      expect(row.displayName, 'Deleted player');
      await expectLater(
        h.service.refresh(s.refreshToken),
        throwsAuth(AuthError.refreshInvalid),
      );

      // The same number can sign up again, as a new account.
      h.clock.advance(const Duration(minutes: 2));
      final again = await h.signIn();
      expect(again.userId, isNot(s.userId));
    });
  });
}
