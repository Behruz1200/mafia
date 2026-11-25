import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../story/comic_art.dart';

/// The last picture of a player's camera, turned into a comic-book panel:
/// flat poster colours on paper with halftone dots, and a grey copy for
/// their seat once they are out.
///
/// Made on the device from a still of the camera (see `FrameGrabber`); it
/// never leaves the device.
class FrozenFrame {
  FrozenFrame._({
    required this.color,
    required this.comic,
    required this.gray,
    required this.cols,
    required this.rows,
    required this.ink,
  });

  /// The picture as taken, scaled down to [width].
  final ui.Image color;

  /// Poster colours on paper.
  final ui.Image comic;

  /// Poster greys, for after.
  final ui.Image gray;

  /// The halftone grid: how dark each [cell] × [cell] square is, 0 to 1.
  final int cols, rows;
  final Float32List ink;

  /// Pictures are made this wide; plenty for a phone-wide panel once the
  /// halftone dots are drawn on top in full sharpness.
  static const width = 240;
  static const cell = 6;

  static const _paper = [251, 238, 210];

  int get height => color.height;

  /// Turns an encoded still (PNG or JPEG) into a frame, or null if it
  /// can't be read.
  static Future<FrozenFrame?> fromEncoded(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null || image.height < cell) {
        image.dispose();
        return null;
      }
      return await fromPixels(image, data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  /// Makes the comic and grey copies of [color] from its RGBA [px].
  static Future<FrozenFrame> fromPixels(ui.Image color, Uint8List px) async {
    final w = color.width, h = color.height;
    final comic = Uint8List(px.length), gray = Uint8List(px.length);
    final cols = (w / cell).ceil(), rows = (h / cell).ceil();
    final ink = Float32List(cols * rows);
    final count = Float32List(cols * rows);
    int q(double v) => ((v.clamp(0, 255) / 255 * 3).round() / 3 * 255).round();
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final r = px[i].toDouble(), g = px[i + 1].toDouble();
        final b = px[i + 2].toDouble();
        final l = 0.3 * r + 0.59 * g + 0.11 * b;
        // Brighter colours, then only four steps of each.
        final pr = q(l + (r - l) * 1.7);
        final pg = q(l + (g - l) * 1.7);
        final pb = q(l + (b - l) * 1.7);
        comic[i] = (pr * 0.82 + _paper[0] * 0.18).round();
        comic[i + 1] = (pg * 0.82 + _paper[1] * 0.18).round();
        comic[i + 2] = (pb * 0.82 + _paper[2] * 0.18).round();
        final m = (pr + pg + pb) / 3 * 0.85 + 30;
        gray[i] = m.round().clamp(0, 255);
        gray[i + 1] = m.round().clamp(0, 255);
        gray[i + 2] = (m * 0.95).round().clamp(0, 255);
        comic[i + 3] = gray[i + 3] = 255;
        final c = (y ~/ cell) * cols + x ~/ cell;
        ink[c] += 1 - l / 255;
        count[c] += 1;
      }
    }
    for (var c = 0; c < ink.length; c++) {
      if (count[c] > 0) ink[c] /= count[c];
    }
    return FrozenFrame._(
      color: color,
      comic: await _image(comic, w, h),
      gray: await _image(gray, w, h),
      cols: cols,
      rows: rows,
      ink: ink,
    );
  }

  static Future<ui.Image> _image(Uint8List px, int w, int h) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  void dispose() {
    color.dispose();
    comic.dispose();
    gray.dispose();
  }
}

/// The last camera picture of each player who said a last word in the
/// current match, kept on this device only. Cleared when a new match
/// starts.
final frozenFramesProvider =
    NotifierProvider<FrozenFrames, Map<UserId, FrozenFrame>>(FrozenFrames.new);

class FrozenFrames extends Notifier<Map<UserId, FrozenFrame>> {
  String? _matchId;

  /// The same pictures as [state], so they can be freed when the provider
  /// goes away (state can't be read then).
  var _kept = <UserId, FrozenFrame>{};

  @override
  Map<UserId, FrozenFrame> build() {
    ref.onDispose(_free);
    return const {};
  }

  void _free() {
    for (final f in _kept.values) {
      f.dispose();
    }
    _kept = {};
  }

  /// Keeps [frame] as [userId]'s latest picture in [matchId].
  void put(String matchId, UserId userId, FrozenFrame frame) {
    if (_matchId != matchId) {
      _free();
      _matchId = matchId;
    }
    final old = _kept[userId];
    _kept = {..._kept, userId: frame};
    state = _kept;
    old?.dispose();
  }

  /// The pictures taken in [matchId]; none from an earlier match.
  Map<UserId, FrozenFrame> forMatch(String matchId) =>
      _matchId == matchId ? state : const {};
}

/// Paints a [FrozenFrame] as a comic panel filling its box: poster colours
/// (fading to grey with [grayness]), halftone dots and an ink frame.
/// [focus] is the point of the picture kept in view when cropping.
class ComicFramePainter extends CustomPainter {
  ComicFramePainter({
    required this.frame,
    this.grayness = 0,
    this.colorness = 0,
    this.border = 0,
    this.focus = const Offset(0.5, 0.4),
  });

  final FrozenFrame frame;

  /// 0 shows the colour comic, 1 the grey one.
  final double grayness;

  /// 1 shows the picture as taken, before it turns into a comic.
  final double colorness;
  final double border;
  final Offset focus;

  @override
  void paint(Canvas canvas, Size size) {
    final fw = frame.color.width.toDouble(), fh = frame.height.toDouble();
    final scale = math.max(size.width / fw, size.height / fh);
    final sw = size.width / scale, sh = size.height / scale;
    final sx = (focus.dx * fw - sw / 2).clamp(0.0, fw - sw);
    final sy = (focus.dy * fh - sh / 2).clamp(0.0, fh - sh);
    final src = Rect.fromLTWH(sx, sy, sw, sh);
    final dst = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(frame.comic, src, dst, paint);
    if (grayness > 0) {
      canvas.drawImageRect(
        frame.gray,
        src,
        dst,
        paint..color = Color.fromRGBO(0, 0, 0, grayness.clamp(0, 1)),
      );
    }
    // Halftone: a dot per cell, bigger where the picture is darker.
    final dots = Paint()
      ..color = Color.lerp(
        const Color(0x8C1E0C28),
        const Color(0x99191420),
        grayness,
      )!;
    final cell = FrozenFrame.cell * scale;
    for (var r = 0; r < frame.rows; r++) {
      final y = (r * FrozenFrame.cell - sy) * scale + cell / 2;
      if (y < -cell || y > size.height + cell) continue;
      final shift = r.isOdd ? cell / 2 : 0.0;
      for (var c = 0; c < frame.cols; c++) {
        final x = (c * FrozenFrame.cell - sx) * scale + cell / 2 + shift;
        if (x < -cell || x > size.width + cell) continue;
        final rad = frame.ink[r * frame.cols + c] * cell * 0.62;
        if (rad > 0.6) canvas.drawCircle(Offset(x, y), rad, dots);
      }
    }
    if (colorness > 0) {
      canvas.drawImageRect(
        frame.color,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(0, 0, 0, colorness.clamp(0, 1)),
      );
    }
    if (border > 0) {
      canvas.drawRect(
        dst.deflate(border / 2),
        Comic.stroke(border)..strokeJoin = StrokeJoin.miter,
      );
    }
  }

  @override
  bool shouldRepaint(ComicFramePainter old) =>
      old.frame != frame ||
      old.grayness != grayness ||
      old.colorness != colorness ||
      old.border != border ||
      old.focus != focus;
}

/// Even halftone dots over a picture we have no pixels for, like a seat's
/// letter when the camera was off.
class HalftonePainter extends CustomPainter {
  const HalftonePainter({this.color = const Color(0x40140C24), this.step = 7});

  final Color color;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    var row = 0;
    for (var y = step / 2; y < size.height + step; y += step, row++) {
      for (
        var x = row.isOdd ? step : step / 2;
        x < size.width + step;
        x += step
      ) {
        // Denser towards the bottom, like a printed shadow.
        final r = step * (0.12 + 0.22 * (y / size.height).clamp(0, 1));
        canvas.drawCircle(Offset(x, y), r, p);
      }
    }
  }

  @override
  bool shouldRepaint(HalftonePainter old) =>
      old.color != color || old.step != step;
}

/// The seat of a player who was shot or voted out: their last camera
/// picture as a grey comic panel (or their letter, if the camera was off),
/// with a little burst where the shot landed and an OUT tag.
class ComicOutFace extends StatelessWidget {
  const ComicOutFace({
    super.key,
    required this.frame,
    required this.fallback,
    required this.shot,
    required this.label,
  });

  final FrozenFrame? frame;

  /// The seat's own letter tile, shown when there is no picture.
  final Widget fallback;

  /// Shot at night (a small burst on the picture) or voted out.
  final bool shot;

  /// The OUT tag's text.
  final String label;

  @override
  Widget build(BuildContext context) {
    final f = frame;
    return Stack(
      key: const ValueKey('comic-out-face'),
      fit: StackFit.expand,
      children: [
        if (f != null)
          CustomPaint(
            painter: ComicFramePainter(
              frame: f,
              grayness: 1,
              focus: const Offset(0.5, 0.36),
            ),
          )
        else ...[
          ColorFiltered(colorFilter: _grayscale, child: fallback),
          const CustomPaint(painter: HalftonePainter()),
        ],
        if (shot)
          const Align(
            alignment: Alignment(0, -0.42),
            child: SizedBox.square(
              dimension: 24,
              child: CustomPaint(painter: ShotBurstPainter()),
            ),
          ),
        Positioned(
          right: 4,
          top: 6,
          child: Transform.rotate(
            angle: 0.18,
            child: Container(
              padding: const EdgeInsets.fromLTRB(5, 1, 5, 0),
              decoration: BoxDecoration(
                color: Comic.red,
                border: Border.all(color: Comic.ink, width: 2),
              ),
              child: Text(
                label,
                style: Comic.lettersFor(label, 13, color: Colors.white),
              ),
            ),
          ),
        ),
        // Ink frame.
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Comic.ink, width: 3),
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ],
    );
  }

  static const _grayscale = ColorFilter.matrix([
    0.3, 0.59, 0.11, 0, 0, //
    0.3, 0.59, 0.11, 0, 0, //
    0.3, 0.59, 0.11, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);
}

/// A spiky comic burst filling its box: yellow with a red heart.
class ShotBurstPainter extends CustomPainter {
  const ShotBurstPainter({this.points = 14});

  final int points;

  static Path star(Offset c, double r, int n) {
    final p = Path();
    for (var i = 0; i < n * 2; i++) {
      final a = i / (n * 2) * math.pi * 2;
      final rr = i.isOdd ? r * 0.6 : r * (i % 4 == 0 ? 1 : 0.86);
      final o = c + Offset(math.cos(a) * rr, math.sin(a) * rr * 0.86);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    final w = math.max(1.5, r / 9);
    Comic.inked(canvas, star(c, r, points), Comic.yellow, w);
    Comic.inked(canvas, star(c, r * 0.6, points), Comic.red, w);
  }

  @override
  bool shouldRepaint(ShotBurstPainter old) => old.points != points;
}
