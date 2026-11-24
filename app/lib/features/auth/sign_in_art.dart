import 'dart:math';

import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../game/ui/noir_art.dart';

/// The night sky behind the sign-in screens: deep violet with two soft
/// glows.
class SignInBackdrop extends StatelessWidget {
  const SignInBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B0F3A), Palette.background],
          stops: [0, 0.6],
        ),
      ),
      child: Stack(
        children: [
          _Glow(alignment: Alignment(-1.4, -0.75), color: Palette.accent),
          _Glow(alignment: Alignment(1.5, -0.2), color: Color(0xFF6C4BD8)),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.alignment, required this.color});

  final Alignment alignment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 360,
        height: 360,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.38), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// A hand of role cards fanned out, the Mafia card on top: the picture on
/// the sign-in screen.
class RoleCardFan extends StatelessWidget {
  const RoleCardFan({super.key, this.height = 270});

  final double height;

  static const _cards = [
    // (role, angle in degrees, x offset)
    (Role.doctor, -22.0, -1.0),
    (Role.detective, -8.0, -0.4),
    (Role.don, 8.0, 0.4),
    (Role.mafia, 20.0, 1.0),
  ];

  @override
  Widget build(BuildContext context) {
    final cardH = height * 0.78;
    final cardW = cardH * 0.68;
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (final (i, (role, angle, dx)) in _cards.indexed)
            Transform.translate(
              offset: Offset(dx * cardW * 0.5, (i == 0 || i == 3) ? 18 : 0),
              child: Transform.rotate(
                angle: angle * pi / 180,
                child: _MiniCard(
                  width: cardW,
                  height: cardH,
                  role: role,
                  glow: i == _cards.length - 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small role card: the role's character in front of the night city.
class _MiniCard extends StatelessWidget {
  const _MiniCard({
    required this.width,
    required this.height,
    required this.role,
    this.glow = false,
  });

  final double width;
  final double height;
  final Role role;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final rim = NoirArt.rim(role);
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF120A22),
        borderRadius: BorderRadius.circular(width * 0.16),
        border: Border.all(
          color: rim.withValues(alpha: glow ? 1 : 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: glow
                ? rim.withValues(alpha: 0.55)
                : Colors.black.withValues(alpha: 0.45),
            blurRadius: glow ? 40 : 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: NightCity(figure: false, moon: null, shadeLeft: false),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height * 0.72,
            child: RolePortrait(role: role),
          ),
        ],
      ),
    );
  }
}

class UzFlag extends StatelessWidget {
  const UzFlag({super.key, this.width = 24});

  final double width;

  @override
  Widget build(BuildContext context) {
    final h = width * 0.66;
    Widget band(Color c, double f) => SizedBox(
      width: width,
      height: h * f,
      child: ColoredBox(color: c),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: width,
        height: h,
        child: Column(
          children: [
            band(const Color(0xFF1EB5E5), 0.32),
            band(const Color(0xFFCE1126), 0.02),
            band(Colors.white, 0.32),
            band(const Color(0xFFCE1126), 0.02),
            band(const Color(0xFF1EB53A), 0.32),
          ],
        ),
      ),
    );
  }
}
