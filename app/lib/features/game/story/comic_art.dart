import 'dart:math' as math;

import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';

/// The comic-book drawing kit for the end-of-match story: ink outlines,
/// flat fills, halftone dots and big sound words. Everything is drawn with
/// shapes, so there is nothing to download.
///
/// Scenes are laid out on a fixed 360 × 400 stage (see [ComicStage]); the
/// sizes below are in stage units.
abstract final class Comic {
  static const ink = Color(0xFF140C24);
  static const skin = Color(0xFFFFD9B8);
  static const paper = Color(0xFFFFFFFF);
  static const yellow = Color(0xFFFFE14D);
  static const glass = Color(0xFFBFF6F1);
  static const steel = Color(0xFF2A2A33);
  static const red = Palette.accent;

  static const stageWidth = 360.0;
  static const stageHeight = 400.0;

  /// Where the characters' feet stand.
  static const ground = 330.0;

  /// How much bigger than its drawing units a character is shown.
  static const figureScale = 1.3;

  /// Lettering. Bangers has no Cyrillic, so Russian falls back to the
  /// app's display face.
  static TextStyle letters(double size, {Color color = ink}) => TextStyle(
    fontFamily: 'Bangers',
    fontFamilyFallback: const [Palette.display],
    fontSize: size,
    height: 1.1,
    letterSpacing: 0.6,
    color: color,
  );

  /// [letters] sized for [text]: the Cyrillic fallback face is wider, so
  /// Russian is set a little smaller to fit the same space.
  static TextStyle lettersFor(String text, double size, {Color color = ink}) =>
      letters(_cyrillic.hasMatch(text) ? size * 0.78 : size, color: color);

  static final _cyrillic = RegExp('[\u0400-\u04FF]');

  static Paint fill(Color c) => Paint()..color = c;
  static Paint stroke(double w, [Color c = ink]) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  /// Fills [path] with [color] and outlines it in ink.
  static void inked(Canvas canvas, Path path, Color color, [double w = 3.5]) {
    canvas
      ..drawPath(path, fill(color))
      ..drawPath(path, stroke(w));
  }
}

/// The colours a role wears.
class RoleLook {
  const RoleLook(this.body, this.hat, this.accent);

  final Color body;
  final Color hat;
  final Color accent;

  static RoleLook of(Role role) => switch (role) {
    Role.mafia => const RoleLook(
      Color(0xFF3A2D5C),
      Color(0xFF1B1430),
      Palette.accent,
    ),
    Role.don => const RoleLook(
      Color(0xFF2B2140),
      Color(0xFF120C22),
      Palette.gold,
    ),
    Role.doctor => const RoleLook(
      Color(0xFFF4F1FF),
      Color(0xFFF4F1FF),
      Palette.cyan,
    ),
    Role.detective => const RoleLook(
      Color(0xFFE0A93B),
      Color(0xFF9A6A1E),
      Palette.gold,
    ),
    Role.civilian => const RoleLook(
      Color(0xFFA996FF),
      Color(0xFF6F5BD9),
      Palette.lavender,
    ),
  };
}

enum ComicFace { smile, scared, smirk }

enum ArmTool { none, gun, lens, point }

/// The arm hanging down, and raised straight ahead.
const armDown = 75 * math.pi / 180;
const armUp = 0.0;

/// One cartoon player, feet at the bottom centre of a 110 × 176 box.
///
/// Arms and tools may reach outside the box; nothing clips them.
class ComicFigure extends StatelessWidget {
  const ComicFigure({
    super.key,
    required this.role,
    this.face = ComicFace.smile,
    this.facingLeft = false,
    this.arm = armDown,
    this.tool = ArmTool.none,
  });

  static const width = 110.0;
  static const height = 176.0;

  final Role role;
  final ComicFace face;
  final bool facingLeft;

  /// Arm angle in radians: [armDown] hangs, [armUp] points ahead.
  final double arm;
  final ArmTool tool;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(width, height),
    painter: _FigurePainter(role, face, facingLeft, arm, tool),
  );
}

class _FigurePainter extends CustomPainter {
  _FigurePainter(this.role, this.face, this.left, this.arm, this.tool);

  final Role role;
  final ComicFace face;
  final bool left;
  final double arm;
  final ArmTool tool;

  @override
  void paint(Canvas canvas, Size size) {
    final look = RoleLook.of(role);
    final isMafia = role.team == Team.mafia;
    canvas
      ..save()
      ..translate(size.width / 2, size.height)
      ..scale(Comic.figureScale * (left ? -1 : 1), Comic.figureScale);

    _arm(canvas, look);

    // Body.
    final body = Path()
      ..moveTo(-22, 0)
      ..lineTo(-22, -46)
      ..quadraticBezierTo(-22, -72, 0, -72)
      ..quadraticBezierTo(22, -72, 22, -46)
      ..lineTo(22, 0)
      ..close();
    Comic.inked(canvas, body, look.body);
    if (isMafia) {
      final tie = Path()
        ..moveTo(0, -70)
        ..lineTo(-5, -60)
        ..lineTo(0, -38)
        ..lineTo(5, -60)
        ..close();
      Comic.inked(canvas, tie, look.accent, 2);
    }
    if (role == Role.doctor) {
      Comic.inked(canvas, _cross(0, -48, 4, 10), Comic.red, 2);
    }
    if (role == Role.detective) {
      canvas
        ..drawLine(
          const Offset(-22, -30),
          const Offset(22, -30),
          Comic.stroke(3),
        )
        ..drawCircle(const Offset(0, -30), 3, Comic.fill(Palette.gold));
    }

    // Head and face.
    canvas
      ..drawCircle(const Offset(0, -92), 19, Comic.fill(Comic.skin))
      ..drawCircle(const Offset(0, -92), 19, Comic.stroke(3.5));
    if (isMafia) {
      final mask = Path()
        ..moveTo(-15, -97)
        ..quadraticBezierTo(-8, -101, -2, -97)
        ..lineTo(-2, -90)
        ..quadraticBezierTo(-8, -88, -15, -91)
        ..close()
        ..moveTo(2, -97)
        ..quadraticBezierTo(8, -101, 15, -97)
        ..lineTo(15, -91)
        ..quadraticBezierTo(8, -88, 2, -90)
        ..close();
      canvas
        ..drawPath(mask, Comic.fill(Comic.ink))
        ..drawCircle(const Offset(-7, -93), 1.8, Comic.fill(Comic.paper))
        ..drawCircle(const Offset(9, -93), 1.8, Comic.fill(Comic.paper));
    } else {
      canvas
        ..drawCircle(const Offset(-6, -94), 2.6, Comic.fill(Comic.ink))
        ..drawCircle(const Offset(8, -94), 2.6, Comic.fill(Comic.ink));
    }
    switch (face) {
      case ComicFace.scared:
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(2, -82), width: 8, height: 10),
          Comic.fill(Comic.ink),
        );
      case ComicFace.smirk:
        canvas.drawPath(
          Path()
            ..moveTo(-4, -83)
            ..quadraticBezierTo(4, -79, 10, -85),
          Comic.stroke(2.5),
        );
      case ComicFace.smile:
        canvas.drawPath(
          Path()
            ..moveTo(-5, -84)
            ..quadraticBezierTo(2, -78, 9, -84),
          Comic.stroke(2.5),
        );
    }

    _hat(canvas, look);
    canvas.restore();
  }

  void _arm(Canvas canvas, RoleLook look) {
    canvas
      ..save()
      ..translate(10, -54)
      ..rotate(arm);
    Comic.inked(
      canvas,
      Path()..addRRect(RRect.fromLTRBR(0, -5, 36, 5, const Radius.circular(5))),
      look.body,
    );
    switch (tool) {
      case ArmTool.gun:
        for (final r in const [
          Rect.fromLTWH(34, -9, 22, 9),
          Rect.fromLTWH(36, -2, 7, 10),
        ]) {
          Comic.inked(
            canvas,
            Path()
              ..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(2))),
            Comic.steel,
          );
        }
      case ArmTool.lens:
        canvas
          ..drawLine(const Offset(34, 0), const Offset(44, -6), Comic.stroke(5))
          ..drawCircle(const Offset(54, -12), 11, Comic.fill(Comic.glass))
          ..drawCircle(const Offset(54, -12), 11, Comic.stroke(3.5));
      case ArmTool.point:
        canvas
          ..drawCircle(const Offset(38, 0), 6, Comic.fill(Comic.skin))
          ..drawCircle(const Offset(38, 0), 6, Comic.stroke(3));
      case ArmTool.none:
        break;
    }
    canvas.restore();
  }

  void _hat(Canvas canvas, RoleLook look) {
    switch (role) {
      case Role.mafia || Role.don:
        Comic.inked(
          canvas,
          Path()
            ..moveTo(-15, -106)
            ..lineTo(-12, -124)
            ..quadraticBezierTo(0, -130, 12, -124)
            ..lineTo(15, -106)
            ..close(),
          look.hat,
        );
        canvas.drawRect(
          const Rect.fromLTWH(-14, -112, 28, 5),
          Comic.fill(look.accent),
        );
        Comic.inked(
          canvas,
          Path()..addOval(
            Rect.fromCenter(
              center: const Offset(0, -106),
              width: 56,
              height: 10,
            ),
          ),
          look.hat,
        );
      case Role.detective:
        Comic.inked(
          canvas,
          Path()
            ..moveTo(-20, -103)
            ..quadraticBezierTo(-20, -125, 0, -125)
            ..quadraticBezierTo(20, -125, 20, -103)
            ..close(),
          look.hat,
        );
        Comic.inked(
          canvas,
          Path()
            ..moveTo(4, -104)
            ..lineTo(32, -104)
            ..quadraticBezierTo(26, -97, 4, -99)
            ..close(),
          look.hat,
        );
      case Role.doctor:
        Comic.inked(
          canvas,
          Path()..addRRect(
            RRect.fromLTRBR(-16, -124, 16, -108, const Radius.circular(5)),
          ),
          Comic.paper,
        );
        canvas.drawPath(_cross(0, -116, 2, 6), Comic.fill(Comic.red));
      case Role.civilian:
        Comic.inked(
          canvas,
          Path()
            ..moveTo(-17, -100)
            ..quadraticBezierTo(-14, -116, 0, -113)
            ..quadraticBezierTo(6, -122, 12, -112)
            ..quadraticBezierTo(20, -108, 18, -98)
            ..quadraticBezierTo(8, -106, -17, -100)
            ..close(),
          look.hat,
        );
    }
  }

  /// A plus sign centred on (cx, cy): arms [half] wide, [reach] long.
  static Path _cross(double cx, double cy, double half, double reach) => Path()
    ..addRect(Rect.fromLTRB(cx - half, cy - reach, cx + half, cy + reach))
    ..addRect(Rect.fromLTRB(cx - reach, cy - half, cx + reach, cy + half));

  @override
  bool shouldRepaint(_FigurePainter old) =>
      old.role != role ||
      old.face != face ||
      old.left != left ||
      old.arm != arm ||
      old.tool != tool;
}

/// A white name tag with the role underneath, comic style.
class ComicNameTag extends StatelessWidget {
  const ComicNameTag({
    super.key,
    required this.name,
    required this.role,
    required this.roleName,
  });

  final String name;
  final Role role;
  final String roleName;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        constraints: const BoxConstraints(minWidth: 60, maxWidth: 84),
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 1),
        decoration: BoxDecoration(
          color: Comic.paper,
          border: Border.all(color: Comic.ink, width: 2.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          name.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Comic.lettersFor(name, 13.5),
        ),
      ),
      const SizedBox(height: 2),
      SizedBox(
        width: 68,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: InkedText(
            roleName,
            style: TextStyle(
              fontFamily: Palette.body,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              color: RoleLook.of(role).accent,
            ),
            strokeWidth: 3,
          ),
        ),
      ),
    ],
  );
}

/// Text with an ink outline behind it.
class InkedText extends StatelessWidget {
  const InkedText(
    this.text, {
    super.key,
    required this.style,
    this.strokeWidth = 5,
    this.textAlign = TextAlign.center,
  });

  final String text;
  final TextStyle style;
  final double strokeWidth;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Text(
        text,
        textAlign: textAlign,
        style: style.copyWith(
          color: null,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeJoin = StrokeJoin.round
            ..color = Comic.ink,
        ),
      ),
      Text(text, textAlign: textAlign, style: style),
    ],
  );
}

/// A big sound word, like BANG! or SAVED!
class ComicWord extends StatelessWidget {
  const ComicWord(this.text, {super.key, required this.color, this.size = 40});

  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => InkedText(
    text,
    style: Comic.lettersFor(text, size, color: color),
    strokeWidth: size / 7,
  );
}

enum Backdrop { night, day, townWin, mafiaWin }

/// The panel behind a scene: sky, halftone dots, moon or sun, ground and
/// the panel's ink frame.
class ComicBackdrop extends StatelessWidget {
  const ComicBackdrop(this.kind, {super.key});

  final Backdrop kind;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: const Size(Comic.stageWidth, Comic.stageHeight),
      painter: _BackdropPainter(kind),
    ),
  );
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.kind);

  final Backdrop kind;

  static final _dots = _halftone();

  static Path _halftone() {
    final p = Path();
    final a = math.pi / 6;
    final c = math.cos(a), s = math.sin(a);
    for (var i = -30; i < 70; i++) {
      for (var j = -30; j < 70; j++) {
        final x = i * 9.0, y = j * 9.0;
        final rx = x * c - y * s, ry = x * s + y * c;
        if (rx < -4 || rx > 364 || ry < -4 || ry > 404) continue;
        p.addOval(Rect.fromCircle(center: Offset(rx, ry), radius: 1.8));
      }
    }
    return p;
  }

  static const _stars = [
    Offset(30, 40),
    Offset(90, 26),
    Offset(150, 58),
    Offset(205, 30),
    Offset(250, 110),
    Offset(40, 120),
    Offset(120, 96),
    Offset(330, 140),
    Offset(180, 130),
    Offset(340, 30),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.clipRRect(RRect.fromRectAndRadius(r, const Radius.circular(14)));
    final (sky, ground, dots) = switch (kind) {
      Backdrop.night => (
        const Color(0xFF2B1F66),
        const Color(0xFF1B1442),
        const Color(0x21FFFFFF),
      ),
      Backdrop.day => (
        Palette.sun,
        const Color(0xFFC9772A),
        const Color(0x29140C24),
      ),
      Backdrop.townWin => (
        Palette.cyan,
        const Color(0xFF1FA79B),
        const Color(0x29140C24),
      ),
      Backdrop.mafiaWin => (
        Palette.accent,
        const Color(0xFF8E1230),
        const Color(0x29140C24),
      ),
    };
    canvas.drawRect(r, Comic.fill(sky));
    if (kind == Backdrop.townWin || kind == Backdrop.mafiaWin) {
      _rays(
        canvas,
        const Offset(180, 150),
        kind == Backdrop.townWin
            ? const Color(0xFF7FF3EA)
            : const Color(0xFFFF7A93),
        18,
        0,
        420,
      );
    }
    canvas.drawPath(_dots, Comic.fill(dots));
    switch (kind) {
      case Backdrop.night:
        canvas
          ..drawCircle(const Offset(292, 70), 30, Comic.fill(Comic.yellow))
          ..drawCircle(const Offset(292, 70), 30, Comic.stroke(4))
          ..drawCircle(const Offset(304, 62), 25, Comic.fill(sky));
        for (final s in _stars) {
          canvas
            ..drawCircle(s, 2.6, Comic.fill(Comic.yellow))
            ..drawCircle(s, 2.6, Comic.stroke(1.2));
        }
      case Backdrop.day:
        _rays(canvas, const Offset(70, 74), Comic.yellow, 12, 46, 62);
        canvas
          ..drawCircle(const Offset(70, 74), 30, Comic.fill(Comic.yellow))
          ..drawCircle(const Offset(70, 74), 30, Comic.stroke(4));
      case Backdrop.townWin || Backdrop.mafiaWin:
        break;
    }
    final g = Rect.fromLTWH(-4, Comic.ground, size.width + 8, 80);
    canvas
      ..drawRect(g, Comic.fill(ground))
      ..drawLine(
        const Offset(0, Comic.ground),
        Offset(size.width, Comic.ground),
        Comic.stroke(4),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(r.deflate(2.5), const Radius.circular(13)),
        Comic.stroke(5),
      );
  }

  static void _rays(
    Canvas canvas,
    Offset c,
    Color color,
    int n,
    double r0,
    double r1,
  ) {
    final paint = Comic.fill(color.withValues(alpha: 0.55));
    for (var i = 0; i < n; i++) {
      final a = i / n * math.pi * 2, b = a + math.pi / n * 0.55;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx + math.cos(a) * r0, c.dy + math.sin(a) * r0)
          ..lineTo(c.dx + math.cos(a) * r1, c.dy + math.sin(a) * r1)
          ..lineTo(c.dx + math.cos(b) * r1, c.dy + math.sin(b) * r1)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.kind != kind;
}

/// A spiky yellow burst with a sound word on it.
class ComicBurst extends StatelessWidget {
  const ComicBurst(this.text, {super.key, this.radius = 34, this.size = 24});

  final String text;
  final double radius;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: radius * 2,
    child: CustomPaint(
      painter: _BurstPainter(),
      child: Center(
        child: Transform.rotate(
          angle: -8 * math.pi / 180,
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: InkedText(
                text,
                style: Comic.letters(size, color: Comic.red),
                strokeWidth: 3,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _BurstPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    final p = Path();
    const n = 14;
    for (var i = 0; i < n * 2; i++) {
      final a = i / (n * 2) * math.pi * 2;
      final rr = i.isOdd ? r * 0.58 : r;
      final o = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    p.close();
    Comic.inked(canvas, p, Comic.yellow, 4);
  }

  @override
  bool shouldRepaint(_BurstPainter old) => false;
}

/// The Doctor's shield: a glass bubble with a heart.
class ComicShield extends StatelessWidget {
  const ComicShield({super.key});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size.square(56), painter: _ShieldPainter());
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas
      ..drawCircle(c, 26, Comic.fill(Comic.glass))
      ..drawCircle(c, 26, Comic.stroke(4));
    Comic.inked(canvas, heartPath(c, 1), Comic.red, 2.5);
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => false;
}

/// A heart centred on [c].
Path heartPath(Offset c, double s) => Path()
  ..moveTo(c.dx, c.dy + 10 * s)
  ..cubicTo(
    c.dx - 16 * s,
    c.dy - 2 * s,
    c.dx - 12 * s,
    c.dy - 16 * s,
    c.dx,
    c.dy - 8 * s,
  )
  ..cubicTo(
    c.dx + 12 * s,
    c.dy - 16 * s,
    c.dx + 16 * s,
    c.dy - 2 * s,
    c.dx,
    c.dy + 10 * s,
  )
  ..close();

/// A role card turned face up. [role] null draws a "not that" card (a big
/// cross), used when the Don's check misses.
class ComicRoleCard extends StatelessWidget {
  const ComicRoleCard({super.key, required this.role, required this.label});

  final Role? role;
  final String label;

  static const width = 72.0;
  static const height = 96.0;

  @override
  Widget build(BuildContext context) {
    final color = role == null
        ? const Color(0xFF8C86A8)
        : switch (role!) {
            Role.mafia || Role.don => Comic.red,
            Role.detective => Palette.gold,
            Role.doctor => Palette.cyan,
            Role.civilian => Palette.lavender,
          };
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _CardPainter(role, color),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FittedBox(
              child: InkedText(
                label.toUpperCase(),
                style: Comic.letters(16, color: Comic.paper),
                strokeWidth: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardPainter extends CustomPainter {
  _CardPainter(this.role, this.color);

  final Role? role;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    Comic.inked(
      canvas,
      Path()..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      ),
      Comic.paper,
      4,
    );
    Comic.inked(
      canvas,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(8, 8, size.width - 16, size.height - 16),
          const Radius.circular(5),
        ),
      ),
      color,
      2.5,
    );
    final c = Offset(size.width / 2, 40);
    final inkFill = Comic.fill(Comic.ink);
    switch (role) {
      case Role.mafia || Role.don:
        canvas
          ..drawPath(
            Path()
              ..moveTo(c.dx - 12, c.dy + 2)
              ..lineTo(c.dx - 9, c.dy - 14)
              ..quadraticBezierTo(c.dx, c.dy - 19, c.dx + 9, c.dy - 14)
              ..lineTo(c.dx + 12, c.dy + 2)
              ..close(),
            inkFill,
          )
          ..drawOval(
            Rect.fromCenter(
              center: c + const Offset(0, 2),
              width: 42,
              height: 9,
            ),
            inkFill,
          );
      case Role.detective:
        canvas
          ..drawCircle(c + const Offset(-3, -3), 11, Comic.stroke(4))
          ..drawLine(
            c + const Offset(5, 5),
            c + const Offset(14, 14),
            Comic.stroke(5),
          );
      case Role.doctor:
        canvas
          ..drawRect(Rect.fromCenter(center: c, width: 8, height: 26), inkFill)
          ..drawRect(Rect.fromCenter(center: c, width: 26, height: 8), inkFill);
      case Role.civilian:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - 14, c.dy + 12)
            ..lineTo(c.dx - 14, c.dy - 2)
            ..lineTo(c.dx, c.dy - 14)
            ..lineTo(c.dx + 14, c.dy - 2)
            ..lineTo(c.dx + 14, c.dy + 12)
            ..close(),
          inkFill,
        );
      case null:
        canvas
          ..drawLine(
            c + const Offset(-13, -13),
            c + const Offset(13, 13),
            Comic.stroke(6),
          )
          ..drawLine(
            c + const Offset(13, -13),
            c + const Offset(-13, 13),
            Comic.stroke(6),
          );
    }
  }

  @override
  bool shouldRepaint(_CardPainter old) =>
      old.role != role || old.color != color;
}

/// A yellow voting token with a tick.
class VoteToken extends StatelessWidget {
  const VoteToken({super.key});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size.square(24), painter: _TokenPainter());
}

class _TokenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas
      ..drawCircle(c, 11, Comic.fill(Comic.yellow))
      ..drawCircle(c, 11, Comic.stroke(3))
      ..drawPath(
        Path()
          ..moveTo(c.dx - 5, c.dy)
          ..lineTo(c.dx - 1.5, c.dy + 4)
          ..lineTo(c.dx + 5, c.dy - 4),
        Comic.stroke(2.8),
      );
  }

  @override
  bool shouldRepaint(_TokenPainter old) => false;
}

/// A little ghost, for a player who is out.
class ComicGhost extends StatelessWidget {
  const ComicGhost({super.key});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(44, 52), painter: _GhostPainter());
}

class _GhostPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Path()
      ..moveTo(4, h - 4)
      ..lineTo(4, 22)
      ..arcToPoint(Offset(w - 4, 22), radius: Radius.circular(w / 2 - 4))
      ..lineTo(w - 4, h - 4)
      ..lineTo(w - 12, h - 10)
      ..lineTo(w / 2, h - 4)
      ..lineTo(12, h - 10)
      ..close();
    Comic.inked(canvas, p, Comic.paper, 3);
    canvas
      ..drawCircle(Offset(w / 2 - 7, 20), 3, Comic.fill(Comic.ink))
      ..drawCircle(Offset(w / 2 + 7, 20), 3, Comic.fill(Comic.ink))
      ..drawOval(
        Rect.fromCenter(center: Offset(w / 2, 31), width: 6, height: 8),
        Comic.fill(Comic.ink),
      );
  }

  @override
  bool shouldRepaint(_GhostPainter old) => false;
}

/// Falling confetti, positioned by time [t] in seconds.
class ComicConfetti extends StatelessWidget {
  const ComicConfetti({super.key, required this.t});

  final double t;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(Comic.stageWidth, Comic.stageHeight),
    painter: _ConfettiPainter(t),
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);

  final double t;

  static const _colors = [
    Palette.accent,
    Palette.cyan,
    Palette.gold,
    Palette.lavender,
    Comic.paper,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 26; i++) {
      final x = (i * 53) % 360.0;
      final delay = (i % 7) * 0.18 + 0.2;
      final dur = 2.2 + (i % 4) * 0.4;
      final local = t - delay;
      if (local < 0) continue;
      final p = (local % dur) / dur;
      final y = -60 + p * 530;
      canvas
        ..save()
        ..translate(x + 4, y)
        ..rotate(p * 4 * math.pi);
      const r = Rect.fromLTWH(-4.5, -7, 9, 14);
      canvas
        ..drawRect(r, Comic.fill(_colors[i % 5]))
        ..drawRect(r, Comic.stroke(1.5))
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// The flashlight beam from the Detective's lens.
class ComicBeam extends StatelessWidget {
  const ComicBeam({super.key, required this.length});

  final double length;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(length, 150), painter: _BeamPainter());
}

class _BeamPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final p = Path()
      ..moveTo(0, mid - 6)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, mid + 6)
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Palette.gold.withValues(alpha: 0.85),
            Palette.gold.withValues(alpha: 0.08),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_BeamPainter old) => false;
}
