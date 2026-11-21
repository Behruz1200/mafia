import '../json.dart';
import 'ids.dart';

/// A player as everyone at the table sees them. Never carries a role.
class Player {
  const Player({
    required this.userId,
    required this.displayName,
    required this.seat,
    this.avatarUrl,
    this.isAlive = true,
    this.isConnected = true,
    this.isHost = false,
  });

  final UserId userId;
  final String displayName;
  final String? avatarUrl;

  /// Position around the table, 0-based. Stable for the whole match.
  final int seat;
  final bool isAlive;
  final bool isConnected;
  final bool isHost;

  Player copyWith({bool? isAlive, bool? isConnected, bool? isHost}) => Player(
    userId: userId,
    displayName: displayName,
    avatarUrl: avatarUrl,
    seat: seat,
    isAlive: isAlive ?? this.isAlive,
    isConnected: isConnected ?? this.isConnected,
    isHost: isHost ?? this.isHost,
  );

  Json toJson() => {
    'userId': userId,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'seat': seat,
    'isAlive': isAlive,
    'isConnected': isConnected,
    'isHost': isHost,
  };

  factory Player.fromJson(Json j) => Player(
    userId: j['userId']! as String,
    displayName: j['displayName']! as String,
    avatarUrl: j['avatarUrl'] as String?,
    seat: j['seat']! as int,
    isAlive: j['isAlive'] as bool? ?? true,
    isConnected: j['isConnected'] as bool? ?? true,
    isHost: j['isHost'] as bool? ?? false,
  );
}
