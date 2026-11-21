import 'package:contracts/contracts.dart';

/// A row in `users`. Personal data: stays in this server's database.
class UserRecord {
  const UserRecord({
    required this.id,
    required this.displayName,
    required this.locale,
    required this.createdAt,
    this.phone,
    this.appleSub,
    this.avatarUrl,
    this.countryCode,
    this.birthDate,
    this.deletedAt,
  });

  final UserId id;
  final String? phone;
  final String? appleSub;
  final String displayName;
  final String? avatarUrl;
  final String? countryCode;
  final String locale;
  final DateTime? birthDate;
  final DateTime createdAt;
  final DateTime? deletedAt;

  /// Full years old on [today], or null without a birth date.
  int? ageOn(DateTime today) {
    final b = birthDate;
    if (b == null) return null;
    var age = today.year - b.year;
    if (today.month < b.month ||
        (today.month == b.month && today.day < b.day)) {
      age--;
    }
    return age;
  }

  UserProfile toProfile(DateTime now, {int adultAge = 18}) => UserProfile(
    userId: id,
    displayName: displayName,
    avatarUrl: avatarUrl,
    countryCode: countryCode,
    locale: locale,
    isAdult: (ageOn(now) ?? 0) >= adultAge,
    hasBirthDate: birthDate != null,
    createdAt: createdAt,
  );
}

/// The pending SMS code for one phone number, plus its send counters.
class PhoneCodeRecord {
  const PhoneCodeRecord({
    required this.phone,
    required this.codeHash,
    required this.expiresAt,
    required this.lastSentAt,
    required this.windowStart,
    this.attempts = 0,
    this.sendsInWindow = 1,
  });

  final String phone;
  final String codeHash;
  final DateTime expiresAt;
  final int attempts;
  final DateTime lastSentAt;

  /// Start of the current hour-long window for [sendsInWindow].
  final DateTime windowStart;
  final int sendsInWindow;
}

/// A refresh token. Each refresh replaces it with a new one in the same
/// [familyId]; reusing an old one revokes the whole family.
class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.tokenHash,
    required this.expiresAt,
    this.revokedAt,
  });

  final String id;
  final UserId userId;
  final String familyId;
  final String tokenHash;
  final DateTime expiresAt;
  final DateTime? revokedAt;
}

/// Storage for accounts. `PostgresAccountStore` in production,
/// `MemoryAccountStore` in tests and local runs without a database.
abstract interface class AccountStore {
  Future<PhoneCodeRecord?> phoneCode(String phone);
  Future<void> savePhoneCode(PhoneCodeRecord code);

  /// Adds one failed attempt and returns the new count.
  Future<int> addPhoneCodeAttempt(String phone);
  Future<void> deletePhoneCode(String phone);

  Future<UserRecord?> userById(UserId id);
  Future<UserRecord?> userByPhone(String phone);
  Future<UserRecord?> userByAppleSub(String sub);
  Future<UserRecord> createUser({
    required String displayName,
    required String locale,
    String? phone,
    String? appleSub,
    String? countryCode,
  });

  /// Changes only the non-null fields.
  Future<UserRecord> updateUser(
    UserId id, {
    String? displayName,
    String? locale,
    DateTime? birthDate,
  });

  /// Account deletion: wipes personal data, keeps the id so coin ledger
  /// rows stay consistent, and revokes every session.
  Future<void> deleteUser(UserId id, DateTime now);

  Future<void> createSession(SessionRecord session);
  Future<SessionRecord?> sessionByTokenHash(String tokenHash);

  /// Revokes [oldId] and stores [next], atomically. False when [oldId] was
  /// already revoked (a race or a replay); nothing is stored then.
  Future<bool> rotateSession(String oldId, SessionRecord next, DateTime now);
  Future<void> revokeFamily(String familyId, DateTime now);
}
