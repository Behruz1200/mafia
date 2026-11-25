import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:web/web.dart' as web;

import 'frame_grab.dart';

/// Browsers: plays the camera in a tiny hidden video element and copies
/// its picture onto a canvas. Works in every browser, unlike ImageCapture,
/// which Safari and Firefox lack.
FrameGrabber? grabberFor(lk.VideoTrack track) {
  try {
    // flutter_webrtc's web track keeps the browser's track in `jsTrack`.
    // ignore: avoid_dynamic_calls
    final js = (track.mediaStreamTrack as dynamic).jsTrack as JSObject;
    return _WebGrabber(js as web.MediaStreamTrack);
  } catch (_) {
    return null;
  }
}

class _WebGrabber implements FrameGrabber {
  _WebGrabber(web.MediaStreamTrack track)
    : _video = web.HTMLVideoElement()
        ..muted = true
        ..autoplay = true
        ..playsInline = true {
    // Safari only decodes video that is in the page.
    _video.style
      ..position = 'fixed'
      ..left = '0'
      ..top = '0'
      ..width = '2px'
      ..height = '2px'
      ..opacity = '0'
      ..pointerEvents = 'none';
    _video.srcObject = web.MediaStream([track].toJS);
    web.document.body?.append(_video);
    _video.play().toDart.ignore();
  }

  final web.HTMLVideoElement _video;

  @override
  Future<Uint8List?> grab() async {
    final w = _video.videoWidth, h = _video.videoHeight;
    if (w == 0 || h == 0) return null;
    try {
      final canvas = web.HTMLCanvasElement()
        ..width = w
        ..height = h;
      (canvas.getContext('2d')! as web.CanvasRenderingContext2D).drawImage(
        _video,
        0,
        0,
      );
      final done = Completer<web.Blob?>();
      canvas.toBlob(
        ((web.Blob? b) => done.complete(b)).toJS,
        'image/jpeg',
        0.85.toJS,
      );
      final blob = await done.future;
      if (blob == null) return null;
      return (await blob.arrayBuffer().toDart).toDart.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _video
      ..pause()
      ..srcObject = null
      ..remove();
  }
}
