import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../call_state.dart';

/// Video and sound settings. Our LiveKit runs on a shared 2-core server,
/// and at a 12-player table each player receives up to 11 cameras, so every
/// number here is a budget.
///
/// Each camera is sent twice (simulcast): a sharp copy and a small one. The
/// server forwards each viewer only the copy that fits the tile on their
/// screen ([adaptiveStream]) and that their connection can carry right now,
/// so a weak phone network falls back to the small copy instead of freezing.
///  * Upload per camera: about 400 + 170 kbit/s, plus 32 for the mic.
///  * A phone (small tiles) receives about 170 kbit/s per camera, 1.9
///    Mbit/s for a full table; a laptop with big tiles about 400 each.
abstract final class CallQuality {
  /// The sharp copy, and what the camera captures: 480x360 at 24 fps.
  static const camera = lk.VideoParameters(
    dimensions: lk.VideoDimensionsPresets.h360_43,
    encoding: _sharp,
  );
  static const _sharp = lk.VideoEncoding(
    maxBitrate: 400 * 1000,
    maxFramerate: 24,
  );

  /// The small copy, for phone-sized tiles and weak connections.
  static const cameraSmall = lk.VideoParameters(
    dimensions: lk.VideoDimensionsPresets.h240_43,
    encoding: lk.VideoEncoding(maxBitrate: 170 * 1000, maxFramerate: 20),
  );

  /// Clear speech. Opus at 32 kbit/s, and close to nothing while silent.
  static const voice = lk.AudioEncoding(maxBitrate: 32 * 1000);

  /// Caps how many real pixels a tile asks the server for, per screen
  /// point. Phones have 3 pixels per point; asking for all of them would
  /// pull the sharp copy into every small seat. At 2, phone seats take the
  /// small copy and big seats on a laptop or tablet take the sharp one.
  static const maxPixelDensity = 2.0;

  static const roomOptions = lk.RoomOptions(
    // Only fetch video for tiles on screen, at the size they are shown.
    adaptiveStream: true,
    // Stop sending video nobody is watching.
    dynacast: true,
    defaultCameraCaptureOptions: lk.CameraCaptureOptions(params: camera),
    defaultVideoPublishOptions: lk.VideoPublishOptions(
      videoCodec: 'vp8',
      videoEncoding: _sharp,
      simulcast: true,
      videoSimulcastLayers: [cameraSmall],
      backupVideoCodec: lk.BackupVideoCodec(enabled: false),
    ),
    // All of the phone's or browser's voice clean-up, on purpose: players
    // sit in noisy rooms and often use the loudspeaker.
    defaultAudioCaptureOptions: lk.AudioCaptureOptions(
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
      highPassFilter: true, // cuts rumble: fans, traffic, table knocks
      voiceIsolation: true,
      typingNoiseDetection: true,
    ),
    defaultAudioPublishOptions: lk.AudioPublishOptions(
      encoding: voice,
      dtx: true, // send almost nothing while silent
      red: true, // resend each sound once, so lost packets do not cut words
    ),
  );
}

class _Channel {
  _Channel(this.room, this.grant, this.listener);
  final lk.Room room;
  CallGrant grant;
  final lk.EventsListener<lk.RoomEvent> listener;

  bool get connected => room.connectionState == lk.ConnectionState.connected;

  /// The server can change this live (night mute), so trust the room's
  /// permissions once connected.
  bool get canPublish =>
      room.localParticipant?.permissions.canPublish ?? grant.canPublish;
}

/// The real call, on our self-hosted LiveKit. Holds the table room and, for
/// Mafia at night, the private Mafia room at the same time, so nobody at
/// the table sees a Mafia player leave.
class LiveKitCallController implements TableCallController {
  LiveKitCallController({this.roomOptions = CallQuality.roomOptions});

  final lk.RoomOptions roomOptions;
  final _channels = <CallChannel, _Channel>{};
  final _people = StreamController<List<CallParticipant>>.broadcast();
  final _localCtrl = StreamController<LocalCallState>.broadcast();
  var _local = const LocalCallState();
  var _lastPeople = const <CallParticipant>[];
  bool _wantCamera = false;
  bool _wantMic = false;
  Future<void> _queue = Future.value();

  @override
  LocalCallState get local => _local;

  @override
  Stream<LocalCallState> watchLocal() async* {
    yield _local;
    yield* _localCtrl.stream;
  }

  @override
  Stream<List<CallParticipant>> watchParticipants() async* {
    yield _lastPeople;
    yield* _people.stream;
  }

  /// The room whose people the grid shows: the Mafia call while in it.
  lk.Room? get _shown =>
      (_channels[CallChannel.mafia] ?? _channels[CallChannel.table])?.room;

  /// Video of [userId] in the shown room, if their camera is on.
  lk.VideoTrack? videoTrackFor(UserId userId) {
    final room = _shown;
    if (room == null) return null;
    final lk.Participant? p = room.localParticipant?.identity == userId
        ? room.localParticipant
        : room.remoteParticipants[userId];
    if (p == null) return null;
    for (final pub in p.videoTrackPublications) {
      final track = pub.track;
      if (!pub.muted && track is lk.VideoTrack) return track;
    }
    return null;
  }

  /// The name the server put in the token.
  String? displayNameFor(UserId userId) {
    final room = _shown;
    if (room == null) return null;
    if (room.localParticipant?.identity == userId) {
      return room.localParticipant?.name;
    }
    final name = room.remoteParticipants[userId]?.name;
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<void> _serial(Future<void> Function() job) =>
      _queue = _queue.then((_) => job()).catchError((Object _) {});

  @override
  Future<void> join(CallGrant grant) => _serial(() async {
    final existing = _channels[grant.channel];
    if (existing != null &&
        existing.grant.livekitRoom == grant.livekitRoom &&
        existing.room.connectionState != lk.ConnectionState.disconnected) {
      existing.grant = grant; // permissions are pushed by the server
      await _apply();
      return;
    }
    if (existing != null) await _close(grant.channel);

    final room = lk.Room(roomOptions: roomOptions);
    final listener = room.createListener()
      ..on<lk.RoomDisconnectedEvent>((_) {
        // e.g. the server closed the Mafia room at dawn.
        if (_channels[grant.channel]?.room == room) {
          unawaited(_serial(() => _close(grant.channel)));
        }
      })
      ..on<lk.ParticipantPermissionsUpdatedEvent>(
        (_) => unawaited(_serial(_apply)),
      )
      // Browsers only: sound may wait for a tap (see [startAudio]).
      ..on<lk.AudioPlaybackStatusChanged>((_) => unawaited(_serial(_apply)));
    room.addListener(_emit);
    _channels[grant.channel] = _Channel(room, grant, listener);
    try {
      await room.connect(grant.serverUrl, grant.token);
    } on Object {
      await _close(grant.channel);
      rethrow;
    }
    await _apply();
  });

  @override
  Future<void> setCamera({required bool on}) => _serial(() async {
    _wantCamera = on;
    await _apply();
  });

  @override
  Future<void> setMic({required bool on}) => _serial(() async {
    _wantMic = on;
    await _apply();
  });

  /// Starts other players' sound after the browser held it back. Call it
  /// straight from a tap: browsers only allow it inside one.
  Future<void> startAudio() async {
    for (final c in [..._channels.values]) {
      if (!c.room.canPlaybackAudio) await c.room.startAudio();
    }
    await _serial(_apply);
  }

  @override
  Future<void> leaveChannel(CallChannel channel) => _serial(() async {
    await _close(channel);
    await _apply();
  });

  @override
  Future<void> leave() => _serial(() async {
    for (final c in [..._channels.keys]) {
      await _close(c);
    }
    _emit();
  });

  Future<void> dispose() async {
    await leave();
    await _people.close();
    await _localCtrl.close();
  }

  Future<void> _close(CallChannel channel) async {
    final c = _channels.remove(channel);
    if (c == null) return;
    c.room.removeListener(_emit);
    await c.listener.dispose();
    await c.room.disconnect();
    await c.room.dispose();
  }

  /// Moves camera and mic to the right room. Turns them off everywhere else
  /// first, because a phone can only capture its camera once.
  Future<void> _apply() async {
    final plan = MediaPlan.decide(
      wantCamera: _wantCamera,
      wantMic: _wantMic,
      channels: {
        for (final MapEntry(:key, :value) in _channels.entries)
          key: ChannelStatus(
            connected: value.connected,
            canPublish: value.canPublish,
          ),
      },
    );
    var blocked = false;
    for (final MapEntry(:key, :value) in _channels.entries) {
      final me = value.room.localParticipant;
      if (key == plan.target || me == null || !value.connected) continue;
      if (me.isCameraEnabled()) await me.setCameraEnabled(false);
      if (me.isMicrophoneEnabled()) await me.setMicrophoneEnabled(false);
    }
    final target = plan.target == null ? null : _channels[plan.target];
    final me = target?.room.localParticipant;
    if (me != null) {
      try {
        if (me.isCameraEnabled() != plan.camera) {
          await me.setCameraEnabled(plan.camera);
        }
        if (me.isMicrophoneEnabled() != plan.mic) {
          await me.setMicrophoneEnabled(plan.mic);
        }
      } on lk.TrackCreateException {
        // Camera or mic permission denied by the phone.
        blocked = true;
        _wantCamera = me.isCameraEnabled();
        _wantMic = me.isMicrophoneEnabled();
      }
    }
    _local = LocalCallState(
      cameraOn: me?.isCameraEnabled() ?? false,
      micOn: me?.isMicrophoneEnabled() ?? false,
      canPublish: plan.target != null,
      activeChannel: plan.target,
      connected: _channels.values.any((c) => c.connected),
      mediaBlocked: blocked,
      audioBlocked: _channels.values.any((c) => !c.room.canPlaybackAudio),
    );
    _emit();
  }

  void _emit() {
    if (_people.isClosed) return;
    final room = _shown;
    final people = <CallParticipant>[];
    if (room != null) {
      final all = <lk.Participant>[
        ?room.localParticipant,
        ...room.remoteParticipants.values,
      ];
      for (final p in all) {
        people.add(
          CallParticipant(
            userId: p.identity,
            cameraOn: p.isCameraEnabled(),
            micOn: p.isMicrophoneEnabled(),
            isSpeaking: p.isSpeaking,
          ),
        );
      }
    }
    _lastPeople = people;
    _people.add(people);
    _localCtrl.add(_local);
  }
}
