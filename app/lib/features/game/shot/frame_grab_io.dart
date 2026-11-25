import 'dart:typed_data';

import 'package:livekit_client/livekit_client.dart' as lk;

import 'frame_grab.dart';

/// Phones: WebRTC's own frame capture, which works for remote cameras too.
FrameGrabber? grabberFor(lk.VideoTrack track) => _NativeGrabber(track);

class _NativeGrabber implements FrameGrabber {
  _NativeGrabber(this.track);

  final lk.VideoTrack track;

  @override
  Future<Uint8List?> grab() async {
    try {
      final bytes = await track.mediaStreamTrack.captureFrame();
      return bytes.lengthInBytes == 0 ? null : bytes.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {}
}
