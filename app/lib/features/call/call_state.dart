import 'package:contracts/contracts.dart';

/// What the player's own camera and mic are doing, for the toggles.
class LocalCallState {
  const LocalCallState({
    this.cameraOn = false,
    this.micOn = false,
    this.canPublish = false,
    this.activeChannel,
    this.connected = false,
    this.mediaBlocked = false,
    this.audioBlocked = false,
  });

  /// Actually sending video / audio right now.
  final bool cameraOn;
  final bool micOn;

  /// The server lets this player talk somewhere right now. False at night
  /// for the town, and for players who are out.
  final bool canPublish;

  /// Where camera and mic go: the Mafia call at night for Mafia, otherwise
  /// the table. Null when the player may not talk anywhere.
  final CallChannel? activeChannel;
  final bool connected;

  /// The phone refused camera or mic access (Settings > Privacy).
  final bool mediaBlocked;

  /// The browser will not play other players' sound until the player taps
  /// something (autoplay rules, mostly iPhone Safari). Always false in the
  /// phone apps.
  final bool audioBlocked;

  LocalCallState copyWith({
    bool? cameraOn,
    bool? micOn,
    bool? canPublish,
    CallChannel? activeChannel,
    bool clearChannel = false,
    bool? connected,
    bool? mediaBlocked,
    bool? audioBlocked,
  }) => LocalCallState(
    cameraOn: cameraOn ?? this.cameraOn,
    micOn: micOn ?? this.micOn,
    canPublish: canPublish ?? this.canPublish,
    activeChannel: clearChannel ? null : activeChannel ?? this.activeChannel,
    connected: connected ?? this.connected,
    mediaBlocked: mediaBlocked ?? this.mediaBlocked,
    audioBlocked: audioBlocked ?? this.audioBlocked,
  );

  @override
  bool operator ==(Object other) =>
      other is LocalCallState &&
      other.cameraOn == cameraOn &&
      other.micOn == micOn &&
      other.canPublish == canPublish &&
      other.activeChannel == activeChannel &&
      other.connected == connected &&
      other.mediaBlocked == mediaBlocked &&
      other.audioBlocked == audioBlocked;

  @override
  int get hashCode => Object.hash(
    cameraOn,
    micOn,
    canPublish,
    activeChannel,
    connected,
    mediaBlocked,
    audioBlocked,
  );
}

/// One LiveKit room as the controller sees it.
class ChannelStatus {
  const ChannelStatus({required this.connected, required this.canPublish});
  final bool connected;
  final bool canPublish;
}

/// Where camera and mic should go, given what the player wants and what
/// the server allows. A phone has one camera, so media goes to one room at
/// a time: the Mafia call when it is open to this player, else the table.
class MediaPlan {
  const MediaPlan({
    required this.target,
    required this.camera,
    required this.mic,
  });

  final CallChannel? target;
  final bool camera;
  final bool mic;

  factory MediaPlan.decide({
    required bool wantCamera,
    required bool wantMic,
    required Map<CallChannel, ChannelStatus> channels,
  }) {
    bool open(CallChannel c) {
      final s = channels[c];
      return s != null && s.connected && s.canPublish;
    }

    final target = open(CallChannel.mafia)
        ? CallChannel.mafia
        : open(CallChannel.table)
        ? CallChannel.table
        : null;
    return MediaPlan(
      target: target,
      camera: target != null && wantCamera,
      mic: target != null && wantMic,
    );
  }
}

/// The parts of the call the view needs beyond the shared [CallController].
/// Implemented by the LiveKit controller.
abstract interface class TableCallController implements CallController {
  Stream<LocalCallState> watchLocal();
  LocalCallState get local;

  /// Leaves one room but stays in the others, e.g. the Mafia call at dawn.
  Future<void> leaveChannel(CallChannel channel);
}
