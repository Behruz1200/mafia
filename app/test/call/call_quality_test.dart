import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:mafia_app/features/call/data/livekit_call_controller.dart';

/// The video server is small and shared, so the quality settings are a
/// budget. These checks keep a later tweak from quietly breaking it.
int _longSide(lk.VideoParameters p) =>
    math.max(p.dimensions.width, p.dimensions.height);

void main() {
  const o = CallQuality.roomOptions;
  final sharp = CallQuality.camera;
  final small = CallQuality.cameraSmall;
  const table = 12; // the most players at one table

  test('each camera is sent as a sharp and a small copy', () {
    final publish = o.defaultVideoPublishOptions;
    expect(publish.simulcast, isTrue);
    expect(publish.videoSimulcastLayers, [small]);
    expect(publish.videoEncoding, sharp.encoding);
    expect(o.defaultCameraCaptureOptions.params, sharp);
    // The SDK only splits a camera of at least 480 pixels into copies.
    expect(_longSide(sharp), greaterThanOrEqualTo(480));
    expect(_longSide(small), lessThan(_longSide(sharp)));
    expect(small.encoding!.maxBitrate, lessThan(sharp.encoding!.maxBitrate));
  });

  test('the server only sends video someone is looking at', () {
    expect(o.adaptiveStream, isTrue);
    expect(o.dynacast, isTrue);
    expect(CallQuality.maxPixelDensity, lessThanOrEqualTo(2));
  });

  test('a full table stays inside the bandwidth budget', () {
    final voice = CallQuality.voice.maxBitrate;
    final upload =
        sharp.encoding!.maxBitrate + small.encoding!.maxBitrate + voice;
    final phoneDownload = (table - 1) * (small.encoding!.maxBitrate + voice);
    expect(upload, lessThanOrEqualTo(650 * 1000));
    expect(phoneDownload, lessThanOrEqualTo(2500 * 1000));
  });

  test('voice clean-up is on and silence costs nothing', () {
    final mic = o.defaultAudioCaptureOptions;
    expect(mic.echoCancellation, isTrue);
    expect(mic.noiseSuppression, isTrue);
    expect(mic.autoGainControl, isTrue);
    expect(mic.highPassFilter, isTrue);
    final send = o.defaultAudioPublishOptions;
    expect(send.encoding, CallQuality.voice);
    expect(send.dtx, isTrue);
    expect(send.red, isTrue);
  });
}
