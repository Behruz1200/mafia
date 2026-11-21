import 'dart:io';
import 'dart:math';

import 'package:contracts/contracts.dart';

import 'apple.dart';
import 'auth_config.dart';
import 'errors.dart';
import 'memory_store.dart';
import 'phone.dart';
import 'postgres_store.dart';
import 'sms.dart';
import 'store.dart';
import 'tokens.dart';

/// Sign-up, sign-in, sessions and profiles. Transport-free: the module
/// turns HTTP into calls here, tests call it directly.
class AuthService {
  AuthService({
    required this.config,
    required this.store,
    required this.sms,
    required this.apple,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       tokens = AccessTokens(config.jwtSecret, ttl: config.accessTtl);

  /// Builds the real service from environment variables.
  factory AuthService.fromEnvironment([Map<String, String>? env]) {
    final config = AuthConfig.fromEnvironment(env);
    final AccountStore store;
    if (config.useMemoryStore) {
      store = MemoryAccountStore();
    } else {
      final url = config.databaseUrl;
      if (url == null) {
        throw StateError('DATABASE_URL is not set (or use AUTH_STORE=memory)');
      }
      store = PostgresAccountStore.connect(url);
    }
    final SmsSender sms = switch (config.smsProvider) {
      'eskiz' => EskizSmsSender(
        email:
            config.eskizEmail ?? (throw StateError('ESKIZ_EMAIL is not set')),
        password:
            config.eskizPassword ??
            (throw StateError('ESKIZ_PASSWORD is not set')),
        from: config.eskizFrom,
      ),
      'console' => () {
        stderr.writeln(
          'WARNING: SMS_PROVIDER=console prints sign-in codes to the log. '
          'Use SMS_PROVIDER=eskiz on a real server.',
        );
        return ConsoleSmsSender();
      }(),
      final other => throw StateError('Unknown SMS_PROVIDER $other'),
    };
    return AuthService(
      config: config,
      store: store,
      sms: sms,
      apple: AppleIdVerifier(audiences: config.appleAudiences),
    );
  }

  final AuthConfig config;
  final AccountStore store;
  final SmsSender sms;
  final AppleIdVerifier apple;
  final AccessTokens tokens;
  final DateTime Function() _now;

  static const codeTtl = Duration(minutes: 5);
  static const resendAfter = Duration(seconds: 60);
  static const maxSendsPerHour = 5;
  static const maxAttempts = 5;

  DateTime get _utcNow => _now().toUtc();

  // ---- Phone ------------------------------------------------------------

  String _checkPhone(String input) {
    final phone = normalizePhone(input);
    if (phone == null) throw AuthError.invalidPhone;
    if (!config.regions.allowsApp(countryOfPhone(phone))) {
      throw AuthError.countryNotSupported;
    }
    return phone;
  }

  /// Sends a 6-digit code. At most one a minute and five an hour per number.
  Future<void> startPhone(String input) async {
    final phone = _checkPhone(input);
    final now = _utcNow;
    final prev = await store.phoneCode(phone);

    var windowStart = now;
    var sends = 1;
    if (prev != null) {
      if (now.difference(prev.lastSentAt) < resendAfter) {
        throw AuthError.codeTooSoon;
      }
      if (now.difference(prev.windowStart) < const Duration(hours: 1)) {
        if (prev.sendsInWindow >= maxSendsPerHour) {
          throw AuthError.tooManyCodes;
        }
        windowStart = prev.windowStart;
        sends = prev.sendsInWindow + 1;
      }
    }

    final testCode = config.testPhones[phone];
    final code = testCode ?? newSmsCode();
    await store.savePhoneCode(
      PhoneCodeRecord(
        phone: phone,
        codeHash: hashSmsCode(config.jwtSecret, phone, code),
        expiresAt: now.add(codeTtl),
        lastSentAt: now,
        windowStart: windowStart,
        sendsInWindow: sends,
      ),
    );
    if (testCode != null) return;

    try {
      await sms.send(phone, config.smsText.replaceAll('{code}', code));
    } on Object catch (e) {
      stderr.writeln('SMS to ${maskPhone(phone)} failed: $e');
      throw AuthError.smsFailed;
    }
  }

  /// Checks the code; creates the account on first sign-in.
  Future<AuthSession> verifyPhone(String input, String code) async {
    final phone = _checkPhone(input);
    final now = _utcNow;
    final pending = await store.phoneCode(phone);
    if (pending == null) throw AuthError.codeInvalid;
    if (pending.attempts >= maxAttempts) throw AuthError.tooManyAttempts;
    if (now.isAfter(pending.expiresAt)) throw AuthError.codeExpired;

    final want = hashSmsCode(config.jwtSecret, phone, code.trim());
    if (!constantTimeEquals(want, pending.codeHash)) {
      final n = await store.addPhoneCodeAttempt(phone);
      throw n >= maxAttempts
          ? AuthError.tooManyAttempts
          : AuthError.codeInvalid;
    }
    await store.deletePhoneCode(phone);

    final user =
        await store.userByPhone(phone) ??
        await store.createUser(
          phone: phone,
          displayName: _defaultName(),
          locale: 'uz',
          countryCode: countryOfPhone(phone),
        );
    return _newSession(user.id, now);
  }

  // ---- Apple ------------------------------------------------------------

  Future<AuthSession> signInWithApple(AppleSignInRequest req) async {
    final sub = await apple.verify(req.identityToken, req.rawNonce);
    final now = _utcNow;
    final name = _cleanName(req.displayName);
    final user =
        await store.userByAppleSub(sub) ??
        await store.createUser(
          appleSub: sub,
          displayName: name ?? _defaultName(),
          locale: 'uz',
        );
    return _newSession(user.id, now);
  }

  // ---- Sessions ---------------------------------------------------------

  Future<AuthSession> _newSession(UserId userId, DateTime now) async {
    final refresh = newRefreshToken();
    final family = _uuid();
    await store.createSession(
      SessionRecord(
        id: _uuid(),
        userId: userId,
        familyId: family,
        tokenHash: hashToken(refresh),
        expiresAt: now.add(config.refreshTtl),
      ),
    );
    return _session(userId, refresh, now);
  }

  AuthSession _session(UserId userId, String refresh, DateTime now) =>
      AuthSession(
        userId: userId,
        accessToken: tokens.issue(userId, now),
        refreshToken: refresh,
        expiresAt: now.add(config.accessTtl),
      );

  /// Swaps a refresh token for a new pair. A token that was already used
  /// means it leaked: the whole chain is revoked and the player signs in
  /// again.
  Future<AuthSession> refresh(String refreshToken) async {
    final now = _utcNow;
    final s = await store.sessionByTokenHash(hashToken(refreshToken));
    if (s == null) throw AuthError.refreshInvalid;
    if (s.revokedAt != null) {
      await store.revokeFamily(s.familyId, now);
      throw AuthError.refreshInvalid;
    }
    if (now.isAfter(s.expiresAt)) throw AuthError.refreshInvalid;
    if (await store.userById(s.userId) == null) {
      throw AuthError.refreshInvalid;
    }

    final next = newRefreshToken();
    final ok = await store.rotateSession(
      s.id,
      SessionRecord(
        id: _uuid(),
        userId: s.userId,
        familyId: s.familyId,
        tokenHash: hashToken(next),
        expiresAt: now.add(config.refreshTtl),
      ),
      now,
    );
    if (!ok) {
      await store.revokeFamily(s.familyId, now);
      throw AuthError.refreshInvalid;
    }
    return _session(s.userId, next, now);
  }

  /// Ends this device's session. Unknown tokens are ignored.
  Future<void> signOut(String refreshToken) async {
    final s = await store.sessionByTokenHash(hashToken(refreshToken));
    if (s != null) await store.revokeFamily(s.familyId, _utcNow);
  }

  // ---- Profile ----------------------------------------------------------

  /// Public profile for other modules (rooms, wallet). Null when unknown or
  /// deleted.
  Future<UserProfile?> profileOf(UserId id) async =>
      (await store.userById(id))
          ?.toProfile(_utcNow, adultAge: config.regions.minStakeAge);

  Future<UserProfile> me(UserId id) async =>
      await profileOf(id) ?? (throw AuthError.accountNotFound);

  Future<UserProfile> updateMe(UserId id, UpdateProfileRequest req) async {
    final user = await store.userById(id);
    if (user == null) throw AuthError.accountNotFound;

    String? name;
    if (req.displayName != null) {
      name = _cleanName(req.displayName) ?? (throw AuthError.invalidName);
    }
    if (req.locale != null && !supportedLocales.contains(req.locale)) {
      throw AuthError.invalidLocale;
    }
    final birth = req.birthDate;
    if (birth != null) {
      if (user.birthDate != null) throw AuthError.birthDateAlreadySet;
      final probe = UserRecord(
        id: id,
        displayName: '',
        locale: '',
        createdAt: _utcNow,
        birthDate: birth,
      );
      final age = probe.ageOn(_utcNow)!;
      if (age < 0 || age > 120) throw AuthError.invalidBirthDate;
    }

    final updated = await store.updateUser(
      id,
      displayName: name,
      locale: req.locale,
      birthDate: birth == null
          ? null
          : DateTime.utc(birth.year, birth.month, birth.day),
    );
    return updated.toProfile(_utcNow, adultAge: config.regions.minStakeAge);
  }

  /// Apple requires in-app deletion. Personal data is wiped at once; the
  /// id stays so coin history and past matches still add up.
  Future<void> deleteMe(UserId id) async {
    final user = await store.userById(id);
    if (user == null) return;
    if (user.phone != null) await store.deletePhoneCode(user.phone!);
    await store.deleteUser(id, _utcNow);
  }

  // ---- Helpers ----------------------------------------------------------

  final _rand = Random.secure();

  String _uuid() {
    final b = List<int>.generate(16, (_) => _rand.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
        '-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// `O‘yinchi 4821`. Players pick their own name on the setup screen.
  String _defaultName() => 'O‘yinchi ${1000 + _rand.nextInt(9000)}';

  static final _control = RegExp(r'[\x00-\x1F\x7F]');

  /// Trimmed, single-spaced, 2 to 24 characters, no control characters.
  String? _cleanName(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.runes.length < 2 || s.runes.length > 24) return null;
    if (_control.hasMatch(s)) return null;
    return s;
  }
}
