import 'dart:typed_data';

import 'package:livekit_client/livekit_client.dart' as lk;

import 'frame_grab_io.dart'
    if (dart.library.js_interop) 'frame_grab_web.dart'
    as impl;

/// Takes still pictures of one camera, e.g. the player saying their last
/// word, so their seat can keep the last frame after they are out.
abstract class FrameGrabber {
  /// For [track], or null where this platform can't take pictures.
  static FrameGrabber? forTrack(lk.VideoTrack track) => impl.grabberFor(track);

  /// The camera's current picture as PNG or JPEG bytes, or null if there
  /// is no picture yet.
  Future<Uint8List?> grab();

  void dispose();
}
