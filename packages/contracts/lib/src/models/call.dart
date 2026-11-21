import '../json.dart';
import 'ids.dart';

/// Which LiveKit room a grant is for.
enum CallChannel {
  /// The whole table. During the night town players are muted here.
  table,

  /// The Mafia team's private call at night.
  mafia,
}

/// Permission to join a LiveKit room, minted by the game server.
/// The server decides who may publish; the app only shows toggles.
class CallGrant {
  const CallGrant({
    required this.serverUrl,
    required this.token,
    required this.livekitRoom,
    required this.channel,
    required this.canPublish,
    required this.expiresAt,
  });

  /// e.g. `wss://video.example.uz`. Self-hosted LiveKit.
  final String serverUrl;
  final String token;
  final String livekitRoom;
  final CallChannel channel;

  /// False while the player is dead or it is night for their team.
  final bool canPublish;
  final DateTime expiresAt;

  Json toJson() => {
    'serverUrl': serverUrl,
    'token': token,
    'livekitRoom': livekitRoom,
    'channel': channel.name,
    'canPublish': canPublish,
    'expiresAt': encodeTime(expiresAt),
  };

  factory CallGrant.fromJson(Json j) => CallGrant(
    serverUrl: j['serverUrl']! as String,
    token: j['token']! as String,
    livekitRoom: j['livekitRoom']! as String,
    channel: decodeEnum(CallChannel.values, j['channel']),
    canPublish: j['canPublish']! as bool,
    expiresAt: decodeTime(j['expiresAt']),
  );
}

/// One person in a call as the call widget shows them.
class CallParticipant {
  const CallParticipant({
    required this.userId,
    this.cameraOn = false,
    this.micOn = false,
    this.isSpeaking = false,
  });

  final UserId userId;
  final bool cameraOn;
  final bool micOn;
  final bool isSpeaking;
}
