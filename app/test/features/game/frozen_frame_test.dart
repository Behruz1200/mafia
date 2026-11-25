import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/features/game/shot/frozen_frame.dart';

Future<ui.Image> _image(Uint8List px, int w, int h) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

void main() {
  test('a camera picture becomes comic dots: dark parts, big dots', () async {
    // Left half black, right half white.
    const w = 24, h = 12;
    final px = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final v = x < w / 2 ? 0 : 255;
        px[i] = px[i + 1] = px[i + 2] = v;
        px[i + 3] = 255;
      }
    }
    final frame = await FrozenFrame.fromPixels(await _image(px, w, h), px);
    expect(frame.cols, 4);
    expect(frame.rows, 2);
    expect(frame.ink[0], closeTo(1, 0.01)); // black cell
    expect(frame.ink[3], closeTo(0, 0.01)); // white cell
    expect(frame.comic.width, w);
    expect(frame.gray.height, h);
    frame.dispose();
  });

  test('a picture that cannot be read gives no frame', () async {
    expect(await FrozenFrame.fromEncoded(Uint8List.fromList([1, 2, 3])), null);
  });
}
