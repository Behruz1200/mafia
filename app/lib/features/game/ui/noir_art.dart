import 'dart:math';

import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';

/// "Neon noir": the Mafia artwork drawn on top of the Neon night look. A
/// rainy night city, a man in a fedora under a street lamp, and a glowing
/// silhouette for every role.
///
/// Everything is drawn in code from the path data below (original art made
/// for this app), so it is sharp on every screen, needs no image files and
/// works the same on phones and the web.
abstract final class NoirArt {
  /// The rim light around each role's silhouette.
  static Color rim(Role role) => switch (role) {
    Role.mafia => Palette.accent,
    Role.don => Palette.gold,
    Role.civilian => Palette.lavender,
    Role.detective => Palette.cyan,
    Role.doctor => const Color(0xFF4BE39A),
    Role.bodyguard => const Color(0xFF5B9BFF),
    Role.hypnotist => const Color(0xFFD27BFF),
    Role.maniac => const Color(0xFFFF8A3D),
    Role.immortal => const Color(0xFFFFE7A8),
  };

  /// Night sky over the city: deep violet into a red glow at the horizon.
  static const skyColors = [
    Color(0xFF170A30),
    Color(0xFF4A0E3E),
    Color(0xFFB21E4E),
    Color(0xFFFF3B5C),
  ];
  static const skyStops = [0.0, 0.55, 0.85, 1.0];

  static const ink = Color(0xFF05030B);
}

// ---------------------------------------------------------------------------
// Path data
// ---------------------------------------------------------------------------

/// Reads the small part of SVG path syntax the art below uses
/// (M L H V C Q Z, absolute and relative).
Path svgPath(String d) => _paths.putIfAbsent(d, () => _parse(d));

final _paths = <String, Path>{};

Path _parse(String d) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVvCcQqZz]|-?\d*\.?\d+')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  var i = 0;
  var cmd = 'M';
  double x = 0, y = 0, sx = 0, sy = 0;
  double n() => double.parse(tokens[i++]);
  bool isCmd(String s) => RegExp(r'^[A-Za-z]$').hasMatch(s);
  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + n();
        y = oy + n();
        sx = x;
        sy = y;
        path.moveTo(x, y);
        cmd = rel ? 'l' : 'L'; // more pairs after M are lines
      case 'L':
        x = ox + n();
        y = oy + n();
        path.lineTo(x, y);
      case 'H':
        x = ox + n();
        path.lineTo(x, y);
      case 'V':
        y = oy + n();
        path.lineTo(x, y);
      case 'C':
        final x1 = ox + n(), y1 = oy + n(), x2 = ox + n(), y2 = oy + n();
        x = ox + n();
        y = oy + n();
        path.cubicTo(x1, y1, x2, y2, x, y);
      case 'Q':
        final x1 = ox + n(), y1 = oy + n();
        x = ox + n();
        y = oy + n();
        path.quadraticBezierTo(x1, y1, x, y);
      case 'Z':
        path.close();
        x = sx;
        y = sy;
    }
  }
  return path;
}

/// A man in a fedora and trench coat, facing us. 100 x 200 box.
const _figure = [
  'M26 31 Q50 39 74 31 Q70 25.5 50 26.5 Q30 25.5 26 31 Z',
  'M35.5 29 C34.5 17 38 10.5 44 9.5 Q50 13.5 56 9.5 C62 10.5 65.5 17 64.5 29 Z',
  'M41.5 39 C41.5 26 58.5 26 58.5 39 C58.5 46 54 49 50 49 C46 49 41.5 46 41.5 39 Z',
  'M44 46 L56 46 L58 52 L42 52 Z',
  'M38 50 L44 43 L50 57 L56 43 L62 50 C72 52 76 58 77 67 L81 150 '
      'Q70 156 61 153 L59 192 L52.5 192 L50.5 152 L49.5 152 L47.5 192 '
      'L41 192 L39 153 Q30 156 19 150 L23 67 C24 58 28 52 38 50 Z',
  'M38 192 H49 V196 H36 Z M51 192 H62 L64 196 H51 Z',
];

/// A fedora on its own, 100 x 50 box.
const _fedoraBrim = 'M6 38 Q50 54 94 38 Q86 29 50 31 Q14 29 6 38 Z';
const _fedoraCrown =
    'M24 35 C22 16 30 5 41 4 Q50 10 59 4 C70 5 78 16 76 35 Q50 41 24 35 Z';
const _fedoraBand = 'M24.5 28 Q50 34 75.5 28 L76 35 Q50 41 24 35 Z';

/// Head and shoulders, 200 x 220 box.
abstract final class _Bust {
  static const coat =
      'M16 222 C20 172 46 150 78 141 L122 141 C154 150 180 172 184 222 Z';
  static const neck = 'M86 112 L114 112 L117 146 L83 146 Z';
  static const shirt = 'M80 141 L100 186 L120 141 Z';
  static const tie =
      'M95.5 146 L104.5 146 L107 155 L102.5 196 L97.5 196 L93 155 Z';
  static const bowTie = 'M86 146 L100 153 L114 146 L114 162 L100 155 L86 162 Z';
  static const lapelL = 'M78 141 L100 200 L88 204 L58 154 Z';
  static const lapelR = 'M122 141 L100 200 L112 204 L142 154 Z';
  static const collarL = 'M78 141 L64 128 L58 154 Z';
  static const collarR = 'M122 141 L136 128 L142 154 Z';
  static const face =
      'M76 90 C76 64 124 64 124 90 L124 102 C124 126 110 136 100 136 '
      'C90 136 76 126 76 102 Z';
  static const earL = 'M77 92 C69 90 68 106 78 108 Z';
  static const earR = 'M123 92 C131 90 132 106 122 108 Z';
  static const jaw = 'M78 104 C84 124 94 134 100 135';

  // fedora
  static const brim = 'M38 76 Q100 98 162 76 Q154 62 100 64 Q46 62 38 76 Z';
  static const crown =
      'M64 72 C61 42 72 24 88 22 Q100 32 112 22 C128 24 139 42 136 72 '
      'Q100 80 64 72 Z';
  static const band = 'M64.5 61 Q100 70 135.5 61 L136 72 Q100 80 64 72 Z';

  // flat cap
  static const capCrown =
      'M68 80 C62 54 80 42 100 42 C120 42 138 54 132 80 Q100 70 68 80 Z';
  static const capBrim = 'M72 82 Q100 96 128 82 Q122 72 100 72 Q78 72 72 82 Z';

  // top hat
  static const topCrown = 'M70 70 L73 14 Q100 8 127 14 L130 70 Z';
  static const topBand = 'M71 56 L129 56 L130 70 L70 70 Z';
  static const topBrim = 'M46 74 Q100 88 154 74 Q146 64 100 66 Q54 64 46 74 Z';

  // short hair, no hat
  static const hair =
      'M75 96 C70 62 88 54 100 54 C114 54 130 62 125 96 '
      'C122 80 114 72 100 72 C86 72 78 80 75 96 Z';

  // hood (behind the head) and the dark opening in it
  static const hood =
      'M54 222 C52 150 58 110 66 82 C74 48 88 34 100 34 '
      'C112 34 126 48 134 82 C142 110 148 150 146 222 Z';
  static const hoodOpening =
      'M80 94 C80 66 120 66 120 94 L120 108 C120 128 108 138 100 138 '
      'C92 138 80 128 80 108 Z';

  // extras
  static const glassL = 'M79 87 H98 V95 Q88.5 101 79 95 Z';
  static const glassR = 'M102 87 H121 V95 Q111.5 101 102 95 Z';
  static const earpiece =
      'M124 104 C134 112 124 120 132 128 C138 134 130 138 134 144';
  static const stethoscope =
      'M86 140 C80 170 92 184 100 186 C108 184 120 170 114 140';
  static const mirrorBand = 'M76 74 Q100 62 124 74';
}

// ---------------------------------------------------------------------------
// Painting helpers
// ---------------------------------------------------------------------------

class _Rng {
  _Rng(int seed) : _s = seed & 0xFFFFFFFF;
  int _s;
  double call() {
    _s = (_s * 1664525 + 1013904223) & 0xFFFFFFFF;
    return _s / 4294967296;
  }
}

/// A row of buildings with lit windows, standing on the bottom of [area].
void paintSkyline(
  Canvas canvas,
  Rect area, {
  int seed = 7,
  Color fill = NoirArt.ink,
  List<Color> lit = const [Palette.gold, Color(0xFFFF9F43)],
  double litChance = 0.18,
  double minH = 0.25,
  double maxH = 0.85,
}) {
  final r = _Rng(seed);
  final body = Paint()..color = fill;
  final window = Paint();
  final w = area.width, h = area.height;
  var x = -4.0;
  canvas
    ..save()
    ..translate(area.left, area.top);
  while (x < w) {
    final bw = 18 + r() * 34;
    final bh = h * (minH + r() * (maxH - minH));
    final top = h - bh;
    canvas.drawRect(Rect.fromLTWH(x, top, bw, bh + 2), body);
    if (r() < 0.35) {
      if (r() < 0.5) {
        canvas.drawRect(Rect.fromLTWH(x + bw / 2 - 1, top - 14, 2, 14), body);
      } else {
        canvas.drawPath(
          svgPath('M6 0 l2 -6 h10 l2 6 z M7 -6 h12 v-8 q-6 -4 -12 0 z')
              .shift(Offset(x, top)),
          body,
        );
      }
    }
    for (var wy = top + 8; wy < h - 10; wy += 9) {
      for (var wx = x + 5; wx < x + bw - 6; wx += 7) {
        if (r() < litChance) {
          final c = lit[(r() * lit.length).floor()];
          window.color = c.withValues(alpha: 0.9 * (0.55 + r() * 0.45));
          canvas.drawRect(Rect.fromLTWH(wx, wy, 3.2, 4.4), window);
        }
      }
    }
    x += bw + (r() < 0.3 ? 2 : 0);
  }
  canvas.restore();
}

/// Thin slanted rain streaks.
void paintRain(
  Canvas canvas,
  Size size, {
  int seed = 3,
  int count = 60,
  Color color = const Color(0xFFFFD9E2),
  double opacity = 0.3,
}) {
  final r = _Rng(seed);
  final p = Paint()..strokeWidth = 1;
  // About one streak per 1,800 square points, so big areas are as rainy
  // as small ones.
  final n = max(count, (size.width * size.height / 1800).round());
  for (var i = 0; i < n; i++) {
    final x = r() * (size.width + 40) - 20, y = r() * size.height;
    final l = 8 + r() * 14;
    p.color = color.withValues(alpha: opacity * (0.4 + r() * 0.6));
    canvas.drawLine(Offset(x, y), Offset(x - l * 0.28, y + l), p);
  }
}

void _paintMoon(Canvas canvas, Offset c, double r) {
  canvas
    ..drawCircle(
      c,
      r * 2.4,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFD9A0).withValues(alpha: 0.5),
            const Color(0x00FFD9A0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r * 2.4)),
    )
    ..drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFF4D6), Color(0xFFFFE2A8), Color(0xFFFFD27A)],
          stops: [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  final crater = Paint()..color = const Color(0x80F2CF8C);
  canvas
    ..drawCircle(c + Offset(-r * 0.3, -r * 0.2), r * 0.17, crater)
    ..drawCircle(c + Offset(r * 0.27, r * 0.3), r * 0.12, crater);
}

void _paintPaths(Canvas canvas, List<String> paths, Paint paint) {
  for (final d in paths) {
    canvas.drawPath(svgPath(d), paint);
  }
}

// ---------------------------------------------------------------------------
// Night city scene (the Quick match card)
// ---------------------------------------------------------------------------

/// A rainy night street: moon, two rows of buildings, and a man in a fedora
/// waiting under a street lamp. Fills whatever box it gets.
class NightCity extends StatelessWidget {
  const NightCity({
    super.key,
    this.figure = true,
    this.moon = const Alignment(-0.6, -0.5),
    this.lampAt = 0.6,
    this.shadeLeft = true,
  });

  /// Draw the street lamp and the man under it.
  final bool figure;

  /// Where the moon sits; null for no moon.
  final Alignment? moon;

  /// The lamp's place across the width, 0 to 1.
  final double lampAt;

  /// Darken the left and bottom so white text there reads well.
  final bool shadeLeft;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _NightCityPainter(
        figure: figure,
        moon: moon,
        lampAt: lampAt,
        shadeLeft: shadeLeft,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class _NightCityPainter extends CustomPainter {
  _NightCityPainter({
    required this.figure,
    required this.moon,
    required this.lampAt,
    required this.shadeLeft,
  });

  final bool figure;
  final Alignment? moon;
  final double lampAt;
  final bool shadeLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final all = Offset.zero & size;
    canvas
      ..clipRect(all)
      ..drawRect(
        all,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: NoirArt.skyColors,
            stops: NoirArt.skyStops,
          ).createShader(all),
      );
    if (moon case final moon?) {
      _paintMoon(canvas, moon.withinRect(all), min(30, h * 0.13));
    }
    paintSkyline(
      canvas,
      Rect.fromLTWH(0, h * 0.28, w, h * 0.72),
      seed: 11,
      fill: const Color(0xE62A0B33),
      lit: const [Color(0xFFFF7A8C)],
      litChance: 0.06,
      minH: 0.35,
      maxH: 0.95,
    );
    paintSkyline(
      canvas,
      Rect.fromLTWH(0, h * 0.42, w, h * 0.58),
      seed: 5,
      fill: const Color(0xFF0B0614),
      lit: const [Palette.gold, Color(0xFFFF9F43), Palette.cyan],
      litChance: 0.2,
      minH: 0.3,
      maxH: 0.9,
    );
    // Wet street.
    canvas
      ..drawRect(
        Rect.fromLTWH(0, h - 26, w, 26),
        Paint()..color = const Color(0xFF120818),
      )
      ..drawRect(
        Rect.fromLTWH(0, h - 26, w, 1.5),
        Paint()..color = Palette.accent.withValues(alpha: 0.5),
      );
    if (figure) _paintLampAndFigure(canvas, size);
    paintRain(canvas, size, seed: 9, count: 70);
    if (shadeLeft) {
      canvas
        ..drawRect(
          all,
          Paint()
            ..shader = LinearGradient(
              colors: [
                const Color(0xFF0A0618).withValues(alpha: 0.85),
                const Color(0xFF0A0618).withValues(alpha: 0.2),
                const Color(0x000A0618),
              ],
              stops: const [0, 0.55, 1],
            ).createShader(all),
        )
        ..drawRect(
          all,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0x000A0618),
                const Color(0xFF0A0618).withValues(alpha: 0.8),
              ],
              stops: const [0.45, 1],
            ).createShader(all),
        );
    }
  }

  void _paintLampAndFigure(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final lx = w * lampAt;
    final lampTop = h * 0.2;
    // Light cone and the pool of light on the street.
    final cone = Path()
      ..moveTo(lx, lampTop)
      ..lineTo(lx - w * 0.16, h - 8)
      ..lineTo(lx + w * 0.24, h - 8)
      ..close();
    canvas
      ..drawPath(
        cone,
        Paint()
          ..shader = RadialGradient(
            center: Alignment.topCenter,
            radius: 1,
            colors: [
              const Color(0xFFFFD98A).withValues(alpha: 0.55),
              const Color(0xFFFFB547).withValues(alpha: 0.08),
              const Color(0x00FFB547),
            ],
            stops: const [0, 0.7, 1],
          ).createShader(cone.getBounds()),
      )
      ..drawOval(
        Rect.fromCenter(center: Offset(lx + 4, h - 12), width: 140, height: 18),
        Paint()
          ..shader =
              RadialGradient(
                colors: [
                  const Color(0xFFFFC56B).withValues(alpha: 0.55),
                  const Color(0x00FFC56B),
                ],
              ).createShader(
                Rect.fromCenter(
                  center: Offset(lx + 4, h - 12),
                  width: 140,
                  height: 18,
                ),
              ),
      );
    // The lamp post.
    final post = Paint()..color = const Color(0xFF05030A);
    canvas
      ..drawRect(Rect.fromLTWH(lx + 18, lampTop, 4, h * 0.8), post)
      ..drawPath(
        Path()
          ..moveTo(lx + 20, lampTop)
          ..quadraticBezierTo(lx + 20, lampTop - 8, lx + 8, lampTop - 8)
          ..lineTo(lx - 4, lampTop - 8),
        Paint()
          ..color = const Color(0xFF05030A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      )
      ..drawPath(
        Path()
          ..moveTo(lx - 12, lampTop - 9)
          ..relativeLineTo(16, 0)
          ..relativeLineTo(-3, 7)
          ..relativeLineTo(-10, 0)
          ..close(),
        post,
      )
      ..drawOval(
        Rect.fromCenter(center: Offset(lx - 4, lampTop), width: 18, height: 8),
        Paint()
          ..color = const Color(0xFFFFE3A3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      ..drawOval(
        Rect.fromCenter(center: Offset(lx - 4, lampTop), width: 10, height: 4),
        Paint()..color = const Color(0xFFFFF6DA),
      );
    // The man, with a red rim of light, and his shadow.
    final s = min(0.92, (h - 20) / 210);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(lx - 4, h - 13), width: 80, height: 10),
      Paint()..color = Colors.black.withValues(alpha: 0.8),
    );
    canvas
      ..save()
      ..translate(lx - 4 - 50 * s, h - 13 - 196 * s)
      ..scale(s);
    _paintPaths(
      canvas,
      _figure,
      Paint()
        ..color = Palette.accent.withValues(alpha: 0.95)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 / s),
    );
    _paintPaths(canvas, _figure, Paint()..color = NoirArt.ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NightCityPainter old) =>
      old.figure != figure ||
      old.moon != moon ||
      old.lampAt != lampAt ||
      old.shadeLeft != shadeLeft;
}

/// Faint buildings along the bottom of a screen.
class SkylineStrip extends StatelessWidget {
  const SkylineStrip({
    super.key,
    this.height = 140,
    this.color = const Color(0xFF1A1236),
    this.windows = const Color(0xFF3A2E66),
    this.seed = 21,
  });

  final double height;
  final Color color;
  final Color windows;
  final int seed;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SkylinePainter(color: color, windows: windows, seed: seed),
      ),
    ),
  );
}

class _SkylinePainter extends CustomPainter {
  _SkylinePainter({
    required this.color,
    required this.windows,
    required this.seed,
  });

  final Color color;
  final Color windows;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) => paintSkyline(
    canvas,
    Offset.zero & size,
    seed: seed,
    fill: color,
    lit: [windows],
    litChance: 0.15,
  );

  @override
  bool shouldRepaint(_SkylinePainter old) =>
      old.color != color || old.windows != windows || old.seed != seed;
}

/// Rain over a whole screen, behind its content.
class RainLayer extends StatelessWidget {
  const RainLayer({
    super.key,
    this.color = Palette.lavender,
    this.opacity = 0.18,
    this.seed = 4,
  });

  final Color color;
  final double opacity;
  final int seed;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _RainPainter(color: color, opacity: opacity, seed: seed),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _RainPainter extends CustomPainter {
  _RainPainter({
    required this.color,
    required this.opacity,
    required this.seed,
  });

  final Color color;
  final double opacity;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) =>
      paintRain(canvas, size, seed: seed, color: color, opacity: opacity);

  @override
  bool shouldRepaint(_RainPainter old) =>
      old.color != color || old.opacity != opacity || old.seed != seed;
}

// ---------------------------------------------------------------------------
// Fedora icon
// ---------------------------------------------------------------------------

/// A fedora, for icons, watermarks and the back of the role card.
class FedoraIcon extends StatelessWidget {
  const FedoraIcon({
    super.key,
    this.size = 24,
    this.color = Colors.white,
    this.band,
  });

  /// Width; the height is half of it.
  final double size;
  final Color color;
  final Color? band;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size / 2),
    painter: _FedoraPainter(color: color, band: band),
  );
}

class _FedoraPainter extends CustomPainter {
  _FedoraPainter({required this.color, this.band});

  final Color color;
  final Color? band;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 100);
    final p = Paint()..color = color;
    canvas
      ..drawPath(svgPath(_fedoraCrown), p)
      ..drawPath(svgPath(_fedoraBrim), p);
    if (band case final band?) {
      canvas.drawPath(svgPath(_fedoraBand), Paint()..color = band);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FedoraPainter old) =>
      old.color != color || old.band != band;
}

// ---------------------------------------------------------------------------
// Role portraits
// ---------------------------------------------------------------------------

/// A role's character: a dark silhouette with a coloured rim of light and
/// the few details that tell the roles apart (hat, tie, glasses...).
///
/// Drawn in a 200 x 220 box scaled to fit, sitting on the bottom edge.
class RolePortrait extends StatelessWidget {
  const RolePortrait({super.key, required this.role, this.glow = true});

  final Role role;

  /// The blurred rim light. Off for tiny sizes, where it turns to mush.
  final bool glow;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 200 / 220,
    child: CustomPaint(
      painter: _PortraitPainter(role: role, glow: glow),
    ),
  );
}

/// A role's portrait in a round dark badge, for lists and chips.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role, this.size = 40});

  final Role role;
  final double size;

  @override
  Widget build(BuildContext context) {
    final rim = NoirArt.rim(role);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(0, -0.4),
          colors: [rim.withValues(alpha: 0.45), const Color(0xFF140C28)],
        ),
        border: Border.all(color: rim.withValues(alpha: 0.8), width: 1.5),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: size * 0.12),
        child: RolePortrait(role: role, glow: size >= 48),
      ),
    );
  }
}

class _PortraitPainter extends CustomPainter {
  _PortraitPainter({required this.role, required this.glow});

  final Role role;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final s = min(size.width / 200, size.height / 220);
    canvas
      ..save()
      ..translate((size.width - 200 * s) / 2, size.height - 220 * s)
      ..scale(s);
    _paint(canvas, s);
    canvas.restore();
  }

  void _paint(Canvas canvas, double scale) {
    final rim = NoirArt.rim(role);
    final ink = Paint()..color = const Color(0xFF06030D);
    final outline = _outline(role);

    if (glow) {
      _paintPaths(
        canvas,
        outline,
        Paint()
          ..color = rim
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
    _paintPaths(
      canvas,
      outline,
      Paint()
        ..color = rim.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    _paintPaths(canvas, outline, ink);

    final dim = Paint()..color = const Color(0xFF0E0820);
    final shirt = Paint()..color = const Color(0xFF1A1030);
    final accent = Paint()..color = rim;
    final eyes = Paint()..color = const Color(0xFFFFE7A8);
    final soft = Paint()
      ..color = rim.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Body details.
    switch (role) {
      case Role.maniac:
        break; // all hood
      case Role.civilian:
        canvas
          ..drawPath(
            svgPath(_Bust.shirt),
            Paint()..color = const Color(0xFF2A2050),
          )
          ..drawPath(svgPath(_Bust.collarL), dim)
          ..drawPath(svgPath(_Bust.collarR), dim);
      case Role.detective:
        canvas
          ..drawPath(svgPath(_Bust.shirt), shirt)
          ..drawPath(
            svgPath(_Bust.tie),
            Paint()..color = const Color(0xFF2A4660),
          )
          ..drawPath(svgPath(_Bust.lapelL), dim)
          ..drawPath(svgPath(_Bust.lapelR), dim)
          ..drawPath(svgPath(_Bust.collarL), dim)
          ..drawPath(svgPath(_Bust.collarR), dim);
      case Role.doctor:
        canvas
          ..drawPath(
            svgPath(_Bust.shirt),
            Paint()..color = const Color(0xFF26324A),
          )
          ..drawPath(
            svgPath(_Bust.lapelL),
            Paint()..color = const Color(0xFFDDE6F0),
          )
          ..drawPath(
            svgPath(_Bust.lapelR),
            Paint()..color = const Color(0xFFDDE6F0),
          )
          ..drawPath(
            svgPath(_Bust.stethoscope),
            Paint()
              ..color = const Color(0xFFB8C4D6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5,
          )
          ..drawCircle(const Offset(100, 187), 6, accent);
      case Role.don:
        canvas
          ..drawPath(
            svgPath(_Bust.shirt),
            Paint()..color = const Color(0xFFF3EBDD),
          )
          ..drawPath(svgPath(_Bust.bowTie), accent)
          ..drawPath(svgPath(_Bust.lapelL), dim)
          ..drawPath(svgPath(_Bust.lapelR), dim)
          ..drawCircle(const Offset(136, 166), 4, accent);
      default:
        canvas
          ..drawPath(svgPath(_Bust.shirt), shirt)
          ..drawPath(
            svgPath(_Bust.tie),
            role == Role.bodyguard ? (Paint()..color = Colors.black) : accent,
          )
          ..drawPath(svgPath(_Bust.lapelL), dim)
          ..drawPath(svgPath(_Bust.lapelR), dim);
    }

    // Head details.
    switch (role) {
      case Role.mafia:
        canvas.drawPath(
          svgPath(_Bust.band),
          Paint()..color = rim.withValues(alpha: 0.9),
        );
        _eyeGlints(canvas, eyes);
        canvas.drawPath(svgPath(_Bust.jaw), soft);
      case Role.don:
        canvas.drawPath(svgPath(_Bust.band), accent);
        _eyeGlints(canvas, eyes);
        canvas.drawPath(svgPath(_Bust.jaw), soft);
      case Role.detective:
        canvas.drawPath(
          svgPath(_Bust.band),
          Paint()..color = const Color(0xFF2A4660),
        );
        _eyeGlints(canvas, Paint()..color = const Color(0xFFCFFBF6));
        canvas.drawPath(svgPath(_Bust.jaw), soft);
        // Magnifying glass held up at the shoulder.
        canvas
          ..drawLine(
            const Offset(160, 196),
            const Offset(176, 216),
            Paint()
              ..color = const Color(0xFF3A2A1A)
              ..strokeWidth = 8
              ..strokeCap = StrokeCap.round,
          )
          ..drawCircle(
            const Offset(148, 180),
            18,
            Paint()..color = rim.withValues(alpha: 0.18),
          )
          ..drawCircle(
            const Offset(148, 180),
            18,
            Paint()
              ..color = rim
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4.5,
          );
      case Role.civilian:
        canvas.drawCircle(
          const Offset(100, 43),
          3.5,
          Paint()..color = const Color(0xFF2A2050),
        );
        _eyeGlints(canvas, eyes);
        canvas.drawPath(svgPath(_Bust.jaw), soft);
      case Role.doctor:
        canvas
          ..drawPath(
            svgPath(_Bust.mirrorBand),
            Paint()
              ..color = const Color(0xFFB8C4D6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,
          )
          ..drawCircle(
            const Offset(100, 70),
            11,
            Paint()..color = const Color(0xFFB8C4D6),
          )
          ..drawCircle(const Offset(100, 70), 6, Paint()..color = Colors.white)
          ..drawCircle(const Offset(97, 67), 2.2, Paint()..color = rim);
        _eyeGlints(canvas, Paint()..color = const Color(0xFFD6FFE9));
        canvas.drawPath(svgPath(_Bust.jaw), soft);
      case Role.bodyguard:
        final lens = Paint()..color = const Color(0xFF101828);
        final shine = Paint()
          ..color = rim
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas
          ..drawPath(svgPath(_Bust.glassL), lens)
          ..drawPath(svgPath(_Bust.glassR), lens)
          ..drawPath(svgPath(_Bust.glassL), shine)
          ..drawPath(svgPath(_Bust.glassR), shine)
          ..drawLine(const Offset(98, 89), const Offset(102, 89), shine)
          ..drawLine(
            const Offset(83, 89),
            const Offset(90, 89),
            Paint()
              ..color = Colors.white
              ..strokeWidth = 1.5,
          )
          ..drawPath(
            svgPath(_Bust.earpiece),
            Paint()
              ..color = rim.withValues(alpha: 0.8)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        canvas.drawPath(svgPath(_Bust.jaw), soft);
      case Role.hypnotist:
        canvas.drawPath(svgPath(_Bust.topBand), accent);
        _spiral(canvas, const Offset(90, 94), rim);
        _spiral(canvas, const Offset(110, 94), rim);
        canvas.drawPath(svgPath(_Bust.jaw), soft);
      case Role.maniac:
        // The edge of the hood, then glowing eyes deep inside it.
        canvas.drawPath(
          svgPath(_Bust.hoodOpening),
          Paint()
            ..color = rim.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
        final glowEye = Paint()
          ..color = rim
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas
          ..drawOval(
            Rect.fromCenter(
              center: const Offset(90, 100),
              width: 14,
              height: 6,
            ),
            glowEye,
          )
          ..drawOval(
            Rect.fromCenter(
              center: const Offset(110, 100),
              width: 14,
              height: 6,
            ),
            glowEye,
          )
          ..drawOval(
            Rect.fromCenter(
              center: const Offset(90, 100),
              width: 8,
              height: 3.4,
            ),
            Paint()..color = const Color(0xFFFFE0C2),
          )
          ..drawOval(
            Rect.fromCenter(
              center: const Offset(110, 100),
              width: 8,
              height: 3.4,
            ),
            Paint()..color = const Color(0xFFFFE0C2),
          );
      case Role.immortal:
        // A halo above the head.
        final halo = Rect.fromCenter(
          center: const Offset(100, 44),
          width: 64,
          height: 16,
        );
        canvas
          ..drawOval(
            halo,
            Paint()
              ..color = rim
              ..style = PaintingStyle.stroke
              ..strokeWidth = 7
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
          )
          ..drawOval(
            halo,
            Paint()
              ..color = const Color(0xFFFFF6DA)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5,
          );
        _eyeGlints(canvas, Paint()..color = Colors.white);
        canvas.drawPath(svgPath(_Bust.jaw), soft);
    }
  }

  static void _eyeGlints(Canvas canvas, Paint paint) => canvas
    ..drawOval(
      Rect.fromCenter(center: const Offset(90, 92), width: 8.4, height: 4.2),
      paint,
    )
    ..drawOval(
      Rect.fromCenter(center: const Offset(110, 92), width: 8.4, height: 4.2),
      paint,
    );

  static void _spiral(Canvas canvas, Offset c, Color color) {
    final p = Path()..moveTo(c.dx, c.dy);
    for (var a = 0.0; a < pi * 5; a += 0.2) {
      final r = 0.75 * a;
      p.lineTo(c.dx + r * cos(a), c.dy + r * sin(a));
    }
    canvas
      ..drawPath(
        p,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      )
      ..drawPath(
        p,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
  }

  /// The shapes that make the silhouette (rim light goes around these).
  static List<String> _outline(Role role) {
    const body = [_Bust.coat, _Bust.neck, _Bust.earL, _Bust.earR, _Bust.face];
    return switch (role) {
      Role.mafia ||
      Role.don ||
      Role.detective => [...body, _Bust.crown, _Bust.brim],
      Role.civilian => [...body, _Bust.capCrown, _Bust.capBrim],
      Role.hypnotist => [...body, _Bust.topCrown, _Bust.topBrim],
      Role.maniac => [_Bust.coat, _Bust.hood, _Bust.hoodOpening],
      Role.doctor || Role.bodyguard || Role.immortal => [...body, _Bust.hair],
    };
  }

  @override
  bool shouldRepaint(_PortraitPainter old) =>
      old.role != role || old.glow != glow;
}
