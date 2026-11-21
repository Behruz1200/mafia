import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:postgres/postgres.dart';
import 'package:server/auth/src/apple.dart';
import 'package:server/auth/src/auth_config.dart';
import 'package:server/auth/src/auth_service.dart';
import 'package:server/auth/src/postgres_store.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Runs against a real, empty PostgreSQL when `TEST_DATABASE_URL` is set,
/// e.g. `postgres://postgres:postgres@localhost:5432/mafia_test`. The
/// tables are dropped and recreated from the migrations.
void main() {
  final url = Platform.environment['TEST_DATABASE_URL'];
  if (url == null) {
    test('PostgreSQL store', () {}, skip: 'TEST_DATABASE_URL is not set');
    return;
  }

  late Pool<void> pool;
  late AuthService service;
  late RecordingSms sms;
  late TestClock clock;

  setUpAll(() async {
    pool = Pool.withUrl(url);
    await pool.execute(
      'DROP TABLE IF EXISTS sessions, phone_codes, users, schema_migrations',
    );
    for (final f in ['0001_init.sql', '0002_accounts_users.sql']) {
      final sql = await File('migrations/$f').readAsString();
      // Simple protocol so a file with several statements runs at once.
      await pool.execute(sql, queryMode: QueryMode.simple);
    }
  });
  tearDownAll(() => pool.close());

  setUp(() {
    sms = RecordingSms();
    clock = TestClock();
    service = AuthService(
      config: const AuthConfig(
        jwtSecret: testSecret,
        regions: RegionPolicy(launchCountries: {'UZ'}, stakeCountries: {'UZ'}),
      ),
      store: PostgresAccountStore(pool),
      sms: sms,
      apple: AppleIdVerifier(audiences: const {}),
      now: clock.call,
    );
  });

  test('sign up, profile, refresh, reuse detection, delete', () async {
    const phone = '+998935550101';
    await service.startPhone(phone);
    final s1 = await service.verifyPhone(phone, sms.lastCode);
    expect(await service.me(s1.userId), isA<UserProfile>());

    final p = await service.updateMe(
      s1.userId,
      UpdateProfileRequest(
        displayName: 'Dilnoza',
        locale: 'en',
        birthDate: DateTime(2000, 2, 29),
      ),
    );
    expect(p.displayName, 'Dilnoza');
    expect(p.locale, 'en');
    expect(p.countryCode, 'UZ');
    expect(p.isAdult, isTrue);
    expect(p.hasBirthDate, isTrue);

    final s2 = await service.refresh(s1.refreshToken);
    expect(s2.userId, s1.userId);
    await expectLater(service.refresh(s1.refreshToken), throwsA(anything));
    await expectLater(service.refresh(s2.refreshToken), throwsA(anything));

    await service.deleteMe(s1.userId);
    expect(await service.profileOf(s1.userId), isNull);
    final row = await pool.execute(
      Sql.named(
        'SELECT phone_e164, birth_date, display_name FROM users '
        'WHERE id::text = @id',
      ),
      parameters: {'id': s1.userId},
    );
    expect(row.first[0], isNull);
    expect(row.first[1], isNull);
    expect(row.first[2], 'Deleted player');
  });

  test('wrong codes are counted in the database', () async {
    const phone = '+998935550102';
    await service.startPhone(phone);
    final bad = sms.lastCode == '000000' ? '111111' : '000000';
    for (var i = 0; i < 5; i++) {
      await expectLater(service.verifyPhone(phone, bad), throwsA(anything));
    }
    await expectLater(
      service.verifyPhone(phone, sms.lastCode),
      throwsA(anything),
    );
  });
}
