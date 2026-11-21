import '../json.dart';
import 'ids.dart';
import 'role.dart';

enum RoomStatus { open, inMatch, closed }

enum RoomVisibility {
  /// Only joinable with the invite code.
  private,

  /// Can be found through quick match.
  public,
}

/// How long each timed phase lasts. The server enforces these.
class PhaseDurations {
  const PhaseDurations({
    this.roleReveal = const Duration(seconds: 10),
    this.night = const Duration(seconds: 30),
    this.day = const Duration(seconds: 120),
    this.voting = const Duration(seconds: 30),
  });

  final Duration roleReveal;
  final Duration night;
  final Duration day;
  final Duration voting;

  Json toJson() => {
    'roleRevealSec': roleReveal.inSeconds,
    'nightSec': night.inSeconds,
    'daySec': day.inSeconds,
    'votingSec': voting.inSeconds,
  };

  factory PhaseDurations.fromJson(Json j) => PhaseDurations(
    roleReveal: Duration(seconds: j['roleRevealSec']! as int),
    night: Duration(seconds: j['nightSec']! as int),
    day: Duration(seconds: j['daySec']! as int),
    voting: Duration(seconds: j['votingSec']! as int),
  );
}

/// What the host picks when creating a room.
class RoomSettings {
  const RoomSettings({
    this.minPlayers = 6,
    this.maxPlayers = 12,
    this.stake = 0,
    this.visibility = RoomVisibility.private,
    this.roleCounts,
    this.durations = const PhaseDurations(),
  });

  final int minPlayers;
  final int maxPlayers;

  /// Coins each player puts in at match start. 0 means a free match.
  /// The server decides whether a stake is allowed for a player (age,
  /// region); see `RegionPolicy`.
  final int stake;
  final RoomVisibility visibility;

  /// Fixed deal, e.g. `{mafia: 2, don: 1, doctor: 1, detective: 1}`, with
  /// civilians filling the rest. `null` lets the engine pick by player count.
  final Map<Role, int>? roleCounts;
  final PhaseDurations durations;

  Json toJson() => {
    'minPlayers': minPlayers,
    'maxPlayers': maxPlayers,
    'stake': stake,
    'visibility': visibility.name,
    'roleCounts': roleCounts?.map((k, v) => MapEntry(k.name, v)),
    'durations': durations.toJson(),
  };

  factory RoomSettings.fromJson(Json j) => RoomSettings(
    minPlayers: j['minPlayers']! as int,
    maxPlayers: j['maxPlayers']! as int,
    stake: j['stake']! as int,
    visibility: decodeEnum(RoomVisibility.values, j['visibility']),
    roleCounts: (j['roleCounts'] as Json?)?.map(
      (k, v) => MapEntry(Role.values.byName(k), v! as int),
    ),
    durations: PhaseDurations.fromJson(j['durations']! as Json),
  );
}

/// A room as the server sends it to its members. Only the server changes it.
class Room {
  const Room({
    required this.id,
    required this.inviteCode,
    required this.hostId,
    required this.status,
    required this.settings,
    required this.memberIds,
    required this.createdAt,
    this.currentMatchId,
  });

  final RoomId id;
  final InviteCode inviteCode;
  final UserId hostId;
  final RoomStatus status;
  final RoomSettings settings;

  /// Everyone in the room, in seat order. The server only streams a room's
  /// game state to these users.
  final List<UserId> memberIds;
  final MatchId? currentMatchId;
  final DateTime createdAt;

  Json toJson() => {
    'id': id,
    'inviteCode': inviteCode,
    'hostId': hostId,
    'status': status.name,
    'settings': settings.toJson(),
    'memberIds': memberIds,
    'currentMatchId': currentMatchId,
    'createdAt': encodeTime(createdAt),
  };

  factory Room.fromJson(Json j) => Room(
    id: j['id']! as String,
    inviteCode: j['inviteCode']! as String,
    hostId: j['hostId']! as String,
    status: decodeEnum(RoomStatus.values, j['status']),
    settings: RoomSettings.fromJson(j['settings']! as Json),
    memberIds: decodeStrings(j['memberIds']),
    currentMatchId: j['currentMatchId'] as String?,
    createdAt: decodeTime(j['createdAt']),
  );
}
