import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../story/comic_art.dart';
import '../ui/game_style.dart';
import 'frozen_frame.dart';

/// How a player left the table, for [ShotPanel].
enum OutKind { shot, votedOut }

/// The comic panel that plays when a player's last word ends: their camera
/// freezes on its last picture, turns into a comic, and then the Mafia's
/// shot lands (a crosshair, a cartoon bullet and a BANG!), or, for a day
/// vote, a VOTED OUT stamp. Plays once, then folds away and calls [onDone].
///
/// Everyone at the table sees it, the player who is out too. Nothing here
/// says who fired: the Maniac shoots at night as well.
class ShotPanel extends StatefulWidget {
  const ShotPanel({
    super.key,
    required this.kind,
    required this.name,
    required this.frame,
    required this.onDone,
  });

  final OutKind kind;

  /// The player's name as shown at the table.
  final String name;

  /// Their last camera picture; null if the camera was off.
  final FrozenFrame? frame;
  final VoidCallback onDone;

  static const shotLength = Duration(milliseconds: 4400);
  static const voteLength = Duration(milliseconds: 3200);

  @override
  State<ShotPanel> createState() => _ShotPanelState();
}

class _ShotPanelState extends State<ShotPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.kind == OutKind.shot
        ? ShotPanel.shotLength
        : ShotPanel.voteLength,
  )..forward().whenComplete(() => mounted ? widget.onDone() : null);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Seconds into the panel.
  double get _s => _c.value * _c.duration!.inMilliseconds / 1000;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final s = _s;
        final shot = widget.kind == OutKind.shot;
        final end = _c.duration!.inMilliseconds / 1000;
        final fold = _ease(_span(s, end - 0.45, end));
        // When the shot lands the panel shakes; a vote's stamp, a little.
        final hit = shot ? 2.2 : 0.85;
        final shake = (1 - _span(s, hit, hit + 0.4)) * (shot ? 7 : 4);
        final shaking = s >= hit && s < hit + 0.4;
        return Align(
          alignment: Alignment.topCenter,
          heightFactor: 1 - fold,
          child: Opacity(
            opacity: 1 - fold,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Transform.translate(
                offset: shaking
                    ? Offset(
                        math.sin(s * 170) * shake,
                        math.cos(s * 130) * shake,
                      )
                    : Offset.zero,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(GameStyle.radius),
                    child: LayoutBuilder(
                      builder: (context, box) =>
                          _panel(t, box.biggest, s, shot),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _panel(AppLocalizations t, Size size, double s, bool shot) {
    final target = Offset(size.width * 0.5, size.height * 0.34);
    final comic = _ease(_span(s, 0.15, 0.75));
    final gray = shot ? _span(s, 3.0, 3.6) : _span(s, 1.8, 2.4);
    final frame = widget.frame;
    final caption = shot
        ? (s < 2.2 ? t.shotCaptionAim : t.shotCaptionOut(widget.name))
        : t.shotCaptionVote;
    return Stack(
      key: const ValueKey('shot-panel'),
      fit: StackFit.expand,
      children: [
        if (frame != null)
          CustomPaint(
            painter: ComicFramePainter(
              frame: frame,
              colorness: 1 - comic,
              grayness: gray,
              border: 6 * comic,
              focus: const Offset(0.5, 0.42),
            ),
          )
        else
          _LetterPanel(name: widget.name, comic: comic, gray: gray),
        CustomPaint(
          painter: _ShotFx(
            s: s,
            shot: shot,
            target: target,
            span: size.shortestSide,
          ),
        ),
        // The camera's "click" as it freezes.
        IgnorePointer(
          child: ColoredBox(
            color: Colors.white.withValues(alpha: (1 - _span(s, 0, 0.3)) * 0.9),
          ),
        ),
        if (shot && s >= 2.2 && s < 3.0)
          Positioned(
            left: target.dx - size.width * 0.4,
            width: size.width * 0.8,
            top: target.dy - size.height * 0.2,
            height: size.height * 0.4,
            child: Opacity(
              opacity: 1 - _span(s, 2.75, 3.0),
              child: Transform.scale(
                scale: _backOut(_span(s, 2.2, 2.42)),
                child: Transform.rotate(
                  angle: -0.12,
                  child: FittedBox(
                    child: ComicWord(
                      t.storyBang,
                      color: Colors.white,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (!shot && s >= 0.85)
          Positioned(
            left: 0,
            right: 0,
            top: size.height * 0.52,
            child: Center(
              child: Transform.scale(
                scale: 1.8 - 0.8 * _backOut(_span(s, 0.85, 1.1)),
                child: Transform.rotate(
                  angle: -0.12,
                  child: _Stamp(text: t.shotStampVotedOut),
                ),
              ),
            ),
          ),
        if (s >= 0.4)
          Positioned(
            left: 12,
            top: 12,
            right: 12,
            child: Align(
              alignment: Alignment.topLeft,
              child: Opacity(
                opacity: _span(s, 0.4, 0.6),
                child: Transform.rotate(
                  angle: -0.025,
                  child: _Caption(text: caption),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

double _span(double s, double a, double b) => ((s - a) / (b - a)).clamp(0, 1);

double _ease(double t) =>
    t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

double _backOut(double t) {
  const c1 = 1.70158, c3 = c1 + 1;
  return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
}

/// The yellow narration box in a comic panel's corner.
class _Caption extends StatelessWidget {
  const _Caption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 5, 10, 3),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE27A),
      border: Border.all(color: Comic.ink, width: 3),
    ),
    child: Text(
      text.toUpperCase(),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Comic.lettersFor(text, 20),
    ),
  );
}

/// The red rubber stamp for a day vote.
class _Stamp extends StatelessWidget {
  const _Stamp({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
    decoration: BoxDecoration(
      color: Comic.ink.withValues(alpha: 0.55),
      border: Border.all(color: Comic.red, width: 4),
      borderRadius: BorderRadius.circular(8),
    ),
    child: InkedText(
      text.toUpperCase(),
      style: Comic.lettersFor(text, 38, color: Comic.red),
      strokeWidth: 4,
    ),
  );
}

/// The panel when the camera was off: the player's letter, in comic dots.
class _LetterPanel extends StatelessWidget {
  const _LetterPanel({
    required this.name,
    required this.comic,
    required this.gray,
  });

  final String name;
  final double comic;
  final double gray;

  @override
  Widget build(BuildContext context) {
    final tint = Color.lerp(playerColor(name), const Color(0xFF8C8794), gray)!;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [tint, Color.lerp(tint, const Color(0xFF140C24), 0.55)!],
            ),
          ),
        ),
        Opacity(
          opacity: comic,
          child: const CustomPaint(painter: HalftonePainter(step: 9)),
        ),
        Align(
          alignment: const Alignment(0, -0.1),
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: Comic.letters(
              120,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Comic.ink.withValues(alpha: comic),
              width: 6,
            ),
          ),
        ),
      ],
    );
  }
}

/// The crosshair, the cartoon bullet and the burst where it lands.
class _ShotFx extends CustomPainter {
  _ShotFx({
    required this.s,
    required this.shot,
    required this.target,
    required this.span,
  });

  final double s;
  final bool shot;
  final Offset target;

  /// The panel's short side, to size things.
  final double span;

  @override
  void paint(Canvas canvas, Size size) {
    if (!shot) return;
    final k = span / 300;
    // An ink crosshair spins in and locks onto the forehead.
    if (s >= 0.6 && s < 2.25) {
      final m = _ease(_span(s, 0.6, 1.9));
      final settle = 1 - _span(s, 1.8, 2.0);
      final r = (190 - 150 * m) * k;
      final at =
          target +
          Offset(
            math.sin(s * 6) * (1 - m) * 22 * k,
            math.cos(s * 5) * (1 - m) * 16 * k,
          );
      canvas
        ..save()
        ..translate(at.dx, at.dy)
        ..rotate((1 - m) * 2.5 + math.sin(s * 20) * 0.04 * settle);
      final ink = Comic.stroke(9 * k);
      final red = Comic.stroke(4.5 * k, Comic.red);
      final ticks = Path();
      for (final d in const [
        Offset(0, -1),
        Offset(0, 1),
        Offset(-1, 0),
        Offset(1, 0),
      ]) {
        ticks
          ..moveTo(d.dx * r * 0.45, d.dy * r * 0.45)
          ..lineTo(d.dx * r * 1.35, d.dy * r * 1.35);
      }
      final a = (_span(s, 0.6, 0.8) * 255).round();
      canvas
        ..drawCircle(Offset.zero, r, ink..color = Comic.ink.withAlpha(a))
        ..drawCircle(Offset.zero, r, red..color = Comic.red.withAlpha(a))
        ..drawPath(ticks, Comic.stroke(8 * k)..color = Comic.ink.withAlpha(a))
        ..drawPath(
          ticks,
          Comic.stroke(3.5 * k, Comic.red)..color = Comic.red.withAlpha(a),
        )
        ..restore();
    }
    // A cartoon bullet with speed lines flies in from the left.
    if (s >= 1.85 && s < 2.22) {
      final m = 1 - math.pow(1 - _span(s, 1.85, 2.2), 3).toDouble();
      final from = Offset(-60 * k, target.dy + 40 * k);
      final to = target - Offset(18 * k, 0);
      final at = Offset.lerp(from, to, m)!;
      canvas
        ..save()
        ..translate(at.dx, at.dy)
        ..rotate(-0.18)
        ..scale(k);
      final lines = Comic.stroke(4);
      for (final (y, len) in const [(-9.0, 70.0), (0.0, 110.0), (9.0, 60.0)]) {
        canvas.drawLine(Offset(-30, y), Offset(-30 - len, y), lines);
      }
      final body = Path()
        ..moveTo(-28, -10)
        ..lineTo(6, -10)
        ..quadraticBezierTo(30, -8, 34, 0)
        ..quadraticBezierTo(30, 8, 6, 10)
        ..lineTo(-28, 10)
        ..close();
      Comic.inked(canvas, body, const Color(0xFFD9A441), 3.5);
      Comic.inked(
        canvas,
        Path()..addRect(const Rect.fromLTWH(-28, -10, 12, 20)),
        const Color(0xFFB5772A),
        3.5,
      );
      canvas
        ..drawRect(
          const Rect.fromLTWH(-10, -6, 20, 3),
          Comic.fill(Colors.white.withValues(alpha: 0.4)),
        )
        ..restore();
    }
    // The burst: big with BANG! on it (drawn by the panel), then a small
    // one stays on the forehead.
    if (s >= 2.2) {
      final grow = _backOut(_span(s, 2.2, 2.42));
      final shrink = _ease(_span(s, 2.9, 3.5));
      final r = (120 * grow * (1 - shrink) + 30 * shrink) * k;
      if (r > 1) {
        final c = s < 2.9 ? target + Offset(18 * k, 6 * k) : target;
        final burst = ShotBurstPainter.star(c, r, 14);
        Comic.inked(canvas, burst, Comic.yellow, 4);
        Comic.inked(
          canvas,
          ShotBurstPainter.star(c, r * 0.68, 14),
          Comic.red,
          4,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ShotFx old) =>
      old.s != s || old.target != target || old.shot != shot;
}
