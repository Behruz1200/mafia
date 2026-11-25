import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_ui/material_ui.dart';

import '../../../core/providers.dart';
import '../../call/data/livekit_call_controller.dart';
import 'frame_grab.dart';
import 'frozen_frame.dart';

/// While [userId] says their last word, takes a still of their camera
/// about once a second and keeps the newest in [frozenFramesProvider], so
/// the picture is there the moment the last word ends (their camera may
/// be cut right then). Shows nothing.
class LastFrameKeeper extends ConsumerStatefulWidget {
  const LastFrameKeeper({
    super.key,
    required this.matchId,
    required this.userId,
  });

  final String matchId;
  final UserId userId;

  static const every = Duration(milliseconds: 900);

  @override
  ConsumerState<LastFrameKeeper> createState() => _LastFrameKeeperState();
}

class _LastFrameKeeperState extends ConsumerState<LastFrameKeeper> {
  Timer? _timer;
  lk.VideoTrack? _track;
  FrameGrabber? _grabber;
  bool _busy = false;
  late final FrozenFrames _frames = ref.read(frozenFramesProvider.notifier);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(LastFrameKeeper.every, (_) => _take());
    Timer(const Duration(milliseconds: 400), _take);
  }

  Future<void> _take() async {
    if (_busy || !mounted) return;
    final call = ref.read(callControllerProvider);
    if (call is! LiveKitCallController) return;
    final track = call.videoTrackFor(widget.userId);
    if (track != _track) {
      _grabber?.dispose();
      _track = track;
      _grabber = track == null ? null : FrameGrabber.forTrack(track);
    }
    final grabber = _grabber;
    if (grabber == null) return;
    _busy = true;
    try {
      // A grab waits for the camera's next frame, which never comes if the
      // camera stops; don't let that block every later grab.
      final bytes = await grabber.grab().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      if (bytes == null) return;
      final frame = await FrozenFrame.fromEncoded(bytes);
      if (frame == null) return;
      // Kept even if the last word just ended: this is the newest picture.
      _frames.put(widget.matchId, widget.userId, frame);
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _grabber?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
