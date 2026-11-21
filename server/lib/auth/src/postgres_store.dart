import 'package:contracts/contracts.dart';
import 'package:postgres/postgres.dart';

import 'memory_store.dart' show deletedDisplayName;
import 'store.dart';

/// [AccountStore] on the server's PostgreSQL (tables from
/// `migrations/0002_accounts_users.sql`).
class PostgresAccountStore implements AccountStore {
  /// [db] is a `Pool` in production, a `Connection` in tests.
  PostgresAccountStore(this._db);

  /// Opens a pool from `postgres://user:pass@host:5432/db`.
  factory PostgresAccountStore.connect(String databaseUrl) =>
      PostgresAccountStore(Pool<void>.withUrl(databaseUrl));

  final SessionExecutor _db;

  Future<Result> _q(String sql, [Map<String, Object?> p = const {}]) =>
      _db.run((s) => s.execute(Sql.named(sql), parameters: p));

  static const _userCols =
      'id::text AS id, phone_e164, apple_sub, display_name, avatar_url, '
      'country_code, locale, birth_date, created_at, deleted_at';

  UserRecord _user(ResultRow row) {
    final m = row.toColumnMap();
    return UserRecord(
      id: m['id']! as String,
      phone: m['phone_e164'] as String?,
      appleSub: m['apple_sub'] as String?,
      displayName: m['display_name']! as String,
      avatarUrl: m['avatar_url'] as String?,
      countryCode: (m['country_code'] as String?)?.trim(),
      locale: m['locale']! as String,
      birthDate: m['birth_date'] as DateTime?,
      createdAt: (m['created_at']! as DateTime).toUtc(),
      deletedAt: (m['deleted_at'] as DateTime?)?.toUtc(),
    );
  }

  Future<UserRecord?> _oneUser(String where, Map<String, Object?> p) async {
    final r = await _q(
      'SELECT $_userCols FROM users WHERE $where AND deleted_at IS NULL',
      p,
    );
    return r.isEmpty ? null : _user(r.first);
  }

  @override
  Future<PhoneCodeRecord?> phoneCode(String phone) async {
    final r = await _q('SELECT * FROM phone_codes WHERE phone_e164 = @p', {
      'p': phone,
    });
    if (r.isEmpty) return null;
    final m = r.first.toColumnMap();
    return PhoneCodeRecord(
      phone: m['phone_e164']! as String,
      codeHash: m['code_hash']! as String,
      expiresAt: (m['expires_at']! as DateTime).toUtc(),
      attempts: m['attempts']! as int,
      lastSentAt: (m['last_sent_at']! as DateTime).toUtc(),
      windowStart: (m['window_start']! as DateTime).toUtc(),
      sendsInWindow: m['sends_in_window']! as int,
    );
  }

  @override
  Future<void> savePhoneCode(PhoneCodeRecord c) => _q(
    '''
    INSERT INTO phone_codes (phone_e164, code_hash, expires_at, attempts,
                             last_sent_at, window_start, sends_in_window)
    VALUES (@p, @h, @e, @a, @l, @w, @s)
    ON CONFLICT (phone_e164) DO UPDATE SET
      code_hash = EXCLUDED.code_hash, expires_at = EXCLUDED.expires_at,
      attempts = EXCLUDED.attempts, last_sent_at = EXCLUDED.last_sent_at,
      window_start = EXCLUDED.window_start,
      sends_in_window = EXCLUDED.sends_in_window
    ''',
    {
      'p': c.phone,
      'h': c.codeHash,
      'e': c.expiresAt.toUtc(),
      'a': c.attempts,
      'l': c.lastSentAt.toUtc(),
      'w': c.windowStart.toUtc(),
      's': c.sendsInWindow,
    },
  );

  @override
  Future<int> addPhoneCodeAttempt(String phone) async {
    final r = await _q(
      'UPDATE phone_codes SET attempts = attempts + 1 '
      'WHERE phone_e164 = @p RETURNING attempts',
      {'p': phone},
    );
    return r.isEmpty ? 0 : r.first[0]! as int;
  }

  @override
  Future<void> deletePhoneCode(String phone) =>
      _q('DELETE FROM phone_codes WHERE phone_e164 = @p', {'p': phone});

  @override
  Future<UserRecord?> userById(UserId id) =>
      _oneUser('id::text = @id', {'id': id});

  @override
  Future<UserRecord?> userByPhone(String phone) =>
      _oneUser('phone_e164 = @p', {'p': phone});

  @override
  Future<UserRecord?> userByAppleSub(String sub) =>
      _oneUser('apple_sub = @s', {'s': sub});

  @override
  Future<UserRecord> createUser({
    required String displayName,
    required String locale,
    String? phone,
    String? appleSub,
    String? countryCode,
  }) async {
    final r = await _q(
      'INSERT INTO users (phone_e164, apple_sub, display_name, locale, '
      'country_code) VALUES (@p, @a, @n, @l, @c) RETURNING $_userCols',
      {
        'p': phone,
        'a': appleSub,
        'n': displayName,
        'l': locale,
        'c': countryCode,
      },
    );
    return _user(r.first);
  }

  @override
  Future<UserRecord> updateUser(
    UserId id, {
    String? displayName,
    String? locale,
    DateTime? birthDate,
  }) async {
    final r = await _q(
      '''
      UPDATE users SET
        display_name = COALESCE(@n, display_name),
        locale = COALESCE(@l, locale),
        birth_date = COALESCE(@b::date, birth_date)
      WHERE id::text = @id AND deleted_at IS NULL
      RETURNING $_userCols
      ''',
      {
        'id': id,
        'n': displayName,
        'l': locale,
        'b': birthDate == null ? null : _date(birthDate),
      },
    );
    return _user(r.first);
  }

  @override
  Future<void> deleteUser(UserId id, DateTime now) async {
    await _db.runTx((tx) async {
      await tx.execute(
        Sql.named('''
          UPDATE users SET phone_e164 = NULL, apple_sub = NULL,
            display_name = @n, avatar_url = NULL, birth_date = NULL,
            deleted_at = @now
          WHERE id::text = @id AND deleted_at IS NULL
        '''),
        parameters: {'id': id, 'n': deletedDisplayName, 'now': now.toUtc()},
      );
      await tx.execute(
        Sql.named(
          'UPDATE sessions SET revoked_at = @now '
          'WHERE user_id::text = @id AND revoked_at IS NULL',
        ),
        parameters: {'id': id, 'now': now.toUtc()},
      );
    });
  }

  SessionRecord _session(ResultRow row) {
    final m = row.toColumnMap();
    return SessionRecord(
      id: m['id']! as String,
      userId: m['user_id']! as String,
      familyId: m['family_id']! as String,
      tokenHash: m['token_hash']! as String,
      expiresAt: (m['expires_at']! as DateTime).toUtc(),
      revokedAt: (m['revoked_at'] as DateTime?)?.toUtc(),
    );
  }

  static const _insertSession =
      'INSERT INTO sessions (id, user_id, family_id, token_hash, expires_at) '
      'VALUES (@id::uuid, @u::uuid, @f::uuid, @h, @e)';

  Map<String, Object?> _sessionParams(SessionRecord s) => {
    'id': s.id,
    'u': s.userId,
    'f': s.familyId,
    'h': s.tokenHash,
    'e': s.expiresAt.toUtc(),
  };

  @override
  Future<void> createSession(SessionRecord s) =>
      _q(_insertSession, _sessionParams(s));

  @override
  Future<SessionRecord?> sessionByTokenHash(String tokenHash) async {
    final r = await _q(
      'SELECT id::text AS id, user_id::text AS user_id, '
      'family_id::text AS family_id, token_hash, expires_at, revoked_at '
      'FROM sessions WHERE token_hash = @h',
      {'h': tokenHash},
    );
    return r.isEmpty ? null : _session(r.first);
  }

  @override
  Future<bool> rotateSession(
    String oldId,
    SessionRecord next,
    DateTime now,
  ) async {
    return _db.runTx((tx) async {
      final r = await tx.execute(
        Sql.named(
          'UPDATE sessions SET revoked_at = @now '
          'WHERE id::text = @id AND revoked_at IS NULL RETURNING id',
        ),
        parameters: {'id': oldId, 'now': now.toUtc()},
      );
      if (r.isEmpty) return false;
      await tx.execute(
        Sql.named(_insertSession),
        parameters: _sessionParams(next),
      );
      return true;
    });
  }

  @override
  Future<void> revokeFamily(String familyId, DateTime now) => _q(
    'UPDATE sessions SET revoked_at = @now '
    'WHERE family_id::text = @f AND revoked_at IS NULL',
    {'f': familyId, 'now': now.toUtc()},
  );

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
