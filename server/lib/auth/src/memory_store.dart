import 'dart:math';

import 'package:contracts/contracts.dart';

import 'store.dart';

/// In-memory [AccountStore] for tests and for running the server without
/// PostgreSQL (`AUTH_STORE=memory`). Everything is lost on restart.
class MemoryAccountStore implements AccountStore {
  MemoryAccountStore({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _codes = <String, PhoneCodeRecord>{};
  final users = <UserId, UserRecord>{};
  final sessions = <String, SessionRecord>{};
  final _rand = Random();

  String _uuid() {
    String hex(int n) =>
        List.generate(n, (_) => _rand.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }

  @override
  Future<PhoneCodeRecord?> phoneCode(String phone) async => _codes[phone];

  @override
  Future<void> savePhoneCode(PhoneCodeRecord code) async =>
      _codes[code.phone] = code;

  @override
  Future<int> addPhoneCodeAttempt(String phone) async {
    final c = _codes[phone];
    if (c == null) return 0;
    _codes[phone] = PhoneCodeRecord(
      phone: c.phone,
      codeHash: c.codeHash,
      expiresAt: c.expiresAt,
      attempts: c.attempts + 1,
      lastSentAt: c.lastSentAt,
      windowStart: c.windowStart,
      sendsInWindow: c.sendsInWindow,
    );
    return c.attempts + 1;
  }

  @override
  Future<void> deletePhoneCode(String phone) async => _codes.remove(phone);

  bool _live(UserRecord u) => u.deletedAt == null;

  @override
  Future<UserRecord?> userById(UserId id) async {
    final u = users[id];
    return u != null && _live(u) ? u : null;
  }

  @override
  Future<UserRecord?> userByPhone(String phone) async =>
      users.values.where((u) => _live(u) && u.phone == phone).firstOrNull;

  @override
  Future<UserRecord?> userByAppleSub(String sub) async =>
      users.values.where((u) => _live(u) && u.appleSub == sub).firstOrNull;

  @override
  Future<UserRecord> createUser({
    required String displayName,
    required String locale,
    String? phone,
    String? appleSub,
    String? countryCode,
  }) async {
    final u = UserRecord(
      id: _uuid(),
      phone: phone,
      appleSub: appleSub,
      displayName: displayName,
      locale: locale,
      countryCode: countryCode,
      createdAt: _now().toUtc(),
    );
    return users[u.id] = u;
  }

  @override
  Future<UserRecord> updateUser(
    UserId id, {
    String? displayName,
    String? locale,
    DateTime? birthDate,
  }) async {
    final u = users[id]!;
    return users[id] = UserRecord(
      id: u.id,
      phone: u.phone,
      appleSub: u.appleSub,
      displayName: displayName ?? u.displayName,
      avatarUrl: u.avatarUrl,
      countryCode: u.countryCode,
      locale: locale ?? u.locale,
      birthDate: birthDate ?? u.birthDate,
      createdAt: u.createdAt,
    );
  }

  @override
  Future<void> deleteUser(UserId id, DateTime now) async {
    final u = users[id];
    if (u == null) return;
    users[id] = UserRecord(
      id: u.id,
      displayName: deletedDisplayName,
      locale: u.locale,
      createdAt: u.createdAt,
      deletedAt: now,
    );
    for (final s in sessions.values.where((s) => s.userId == id).toList()) {
      sessions[s.id] = _revoked(s, now);
    }
  }

  @override
  Future<void> createSession(SessionRecord session) async =>
      sessions[session.id] = session;

  @override
  Future<SessionRecord?> sessionByTokenHash(String tokenHash) async =>
      sessions.values.where((s) => s.tokenHash == tokenHash).firstOrNull;

  @override
  Future<bool> rotateSession(
    String oldId,
    SessionRecord next,
    DateTime now,
  ) async {
    final old = sessions[oldId];
    if (old == null || old.revokedAt != null) return false;
    sessions[oldId] = _revoked(old, now);
    sessions[next.id] = next;
    return true;
  }

  @override
  Future<void> revokeFamily(String familyId, DateTime now) async {
    for (final s in sessions.values.toList()) {
      if (s.familyId == familyId && s.revokedAt == null) {
        sessions[s.id] = _revoked(s, now);
      }
    }
  }

  SessionRecord _revoked(SessionRecord s, DateTime now) => SessionRecord(
    id: s.id,
    userId: s.userId,
    familyId: s.familyId,
    tokenHash: s.tokenHash,
    expiresAt: s.expiresAt,
    revokedAt: s.revokedAt ?? now,
  );
}

/// What other players see for a deleted account.
const deletedDisplayName = 'Deleted player';
