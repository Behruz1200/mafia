import '../json.dart';
import 'ids.dart';

/// How the player signed in.
enum SignInMethod { phone, apple, google }

/// The signed-in session the app holds. Tokens are issued by our own auth
/// service on the game server, not by Firebase.
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final UserId userId;

  /// Short-lived JWT sent as `Authorization: Bearer` and on the socket.
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  Json toJson() => {
    'userId': userId,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': encodeTime(expiresAt),
  };

  factory AuthSession.fromJson(Json j) => AuthSession(
    userId: j['userId']! as String,
    accessToken: j['accessToken']! as String,
    refreshToken: j['refreshToken']! as String,
    expiresAt: decodeTime(j['expiresAt']),
  );
}

/// A player's profile. Personal data: it is stored only in the database on
/// the server in Uzbekistan (data localisation), never in Firebase.
class UserProfile {
  const UserProfile({
    required this.userId,
    required this.displayName,
    required this.createdAt,
    this.avatarUrl,
    this.countryCode,
    this.locale = 'uz',
    this.isAdult = false,
  });

  final UserId userId;
  final String displayName;
  final String? avatarUrl;

  /// ISO 3166-1 alpha-2, e.g. `UZ`. Decided by the server, not the app.
  final String? countryCode;

  /// App language: `uz`, `ru` or `en`.
  final String locale;

  /// Passed the 18+ age gate. Required for staked matches.
  final bool isAdult;
  final DateTime createdAt;

  UserProfile copyWith({
    String? displayName,
    String? avatarUrl,
    String? locale,
  }) => UserProfile(
    userId: userId,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    countryCode: countryCode,
    locale: locale ?? this.locale,
    isAdult: isAdult,
    createdAt: createdAt,
  );

  Json toJson() => {
    'userId': userId,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'countryCode': countryCode,
    'locale': locale,
    'isAdult': isAdult,
    'createdAt': encodeTime(createdAt),
  };

  factory UserProfile.fromJson(Json j) => UserProfile(
    userId: j['userId']! as String,
    displayName: j['displayName']! as String,
    avatarUrl: j['avatarUrl'] as String?,
    countryCode: j['countryCode'] as String?,
    locale: j['locale'] as String? ?? 'uz',
    isAdult: j['isAdult'] as bool? ?? false,
    createdAt: decodeTime(j['createdAt']),
  );
}
