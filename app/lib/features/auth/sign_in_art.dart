import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';

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
    // (icon, top colour, bottom colour, angle in degrees, x offset)
    (Icons.medical_services, Color(0xFF18B9C7), Color(0xFF235D9E), -22.0, -1.0),
    (Icons.search, Color(0xFF6C4BD8), Color(0xFF2E1D7A), -8.0, -0.4),
    (Icons.person, Color(0xFFD0682A), Color(0xFF7A2E1D), 8.0, 0.4),
    (Icons.theater_comedy, Palette.accent, Palette.accentDeep, 20.0, 1.0),
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
          for (final (i, (icon, top, bottom, angle, dx)) in _cards.indexed)
            Transform.translate(
              offset: Offset(dx * cardW * 0.5, (i == 0 || i == 3) ? 18 : 0),
              child: Transform.rotate(
                angle: angle * pi / 180,
                child: _MiniCard(
                  width: cardW,
                  height: cardH,
                  icon: icon,
                  colors: [top, bottom],
                  glow: i == _cards.length - 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({
    required this.width,
    required this.height,
    required this.icon,
    required this.colors,
    this.glow = false,
  });

  final double width;
  final double height;
  final IconData icon;
  final List<Color> colors;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      // Keeps the light circle in the corner inside the rounded card.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: glow
                ? colors.first.withValues(alpha: 0.55)
                : Colors.black.withValues(alpha: 0.45),
            blurRadius: glow ? 40 : 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -width * 0.3,
            top: -width * 0.3,
            child: Container(
              width: width * 0.8,
              height: width * 0.8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Center(
            child: Container(
              width: width * 0.56,
              height: width * 0.56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.22),
              ),
              child: Icon(icon, size: width * 0.3, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uzbekistan's flag, small, for the phone number prefix.
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
