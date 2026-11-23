import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';

/// The look of the lobby and the match table, on top of the app theme
/// ("Neon night", see `core/theme.dart`): hot pink-red for the Mafia and
/// the main action, cyan for the town, gold for coins.
abstract final class GameStyle {
  static const felt = Palette.background;
  static const feltLight = Palette.surfaceHigh;
  static const card = Palette.surface;
  static const crimson = Palette.accent;
  static const town = Palette.cyan;
  static const gold = Palette.gold;
  static const moon = Palette.lavender;
  static const sun = Palette.sun;
  static const muted = Palette.muted;

  static const radius = 22.0;

  /// A soft violet glow in the top right corner.
  static const lobbyGradient = RadialGradient(
    center: Alignment(1.1, -1.05),
    radius: 1.3,
    colors: [Color(0xFF3D1650), Palette.background],
    stops: [0, 0.75],
  );

  static const nightGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF05041A), Color(0xFF130C38)],
  );

  static const dayGradient = RadialGradient(
    center: Alignment(-1.1, -1.1),
    radius: 1.4,
    colors: [Color(0xFF3A2440), Palette.background],
    stops: [0, 0.7],
  );

  static const votingGradient = RadialGradient(
    center: Alignment(0, -1.2),
    radius: 1.3,
    colors: [Color(0xFF461030), Palette.background],
    stops: [0, 0.7],
  );

  /// A warm spotlight for the player saying their last word.
  static const lastWordGradient = RadialGradient(
    center: Alignment(0, -1.15),
    radius: 1.3,
    colors: [Color(0xFF4A2C1A), Palette.background],
    stops: [0, 0.7],
  );

  static Color teamColor(Team team) => switch (team) {
    Team.town => town,
    Team.mafia => crimson,
  };

  /// The two colours of a role card's face.
  static List<Color> teamGradient(Team team) => switch (team) {
    Team.mafia => const [Palette.accent, Palette.accentDeep],
    Team.town => const [Color(0xFF18B9C7), Color(0xFF3A2A9E)],
  };

  static IconData roleIcon(Role role) => switch (role) {
    Role.civilian => Icons.person,
    Role.doctor => Icons.medical_services,
    Role.detective => Icons.search,
    Role.mafia => Icons.theater_comedy,
    Role.don => Icons.workspace_premium,
  };

  static Gradient backgroundFor(GamePhase? phase) => switch (phase) {
    GamePhase.night => nightGradient,
    GamePhase.voting => votingGradient,
    GamePhase.lastWord => lastWordGradient,
    GamePhase.lobby || null => lobbyGradient,
    _ => dayGradient,
  };

  /// A glow under the main action button.
  static List<BoxShadow> glow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.45),
      blurRadius: 32,
      offset: const Offset(0, 12),
    ),
  ];

  /// Headline text in the display face.
  static TextStyle display(double size, {Color? color}) => TextStyle(
    fontFamily: Palette.display,
    fontWeight: FontWeight.w800,
    fontSize: size,
    height: 1.12,
    letterSpacing: -0.4,
    color: color,
  );
}

/// A rounded panel used across the game screens.
class GamePanel extends StatelessWidget {
  const GamePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? GameStyle.card,
        borderRadius: BorderRadius.circular(GameStyle.radius),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: 1.5),
      ),
      child: child,
    );
  }
}

/// A small rounded square with an icon on a tint of [color].
class IconBlob extends StatelessWidget {
  const IconBlob({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
    this.filled = false,
  });

  final IconData icon;
  final Color color;
  final double size;

  /// White on a solid colour instead of colour on a tint.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled
            ? Colors.white.withValues(alpha: 0.2)
            : color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        icon,
        size: size * 0.52,
        color: filled ? Colors.white : color,
      ),
    );
  }
}

/// A gold coin, drawn rather than an icon so it reads as money.
class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: GameStyle.gold,
      ),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.56,
        height: size * 0.56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFB8860B),
            width: size * 0.09,
          ),
        ),
      ),
    );
  }
}

/// The coin balance pill shown at the top of the lobby. Tapping it opens
/// the shop, which the little plus says.
class CoinChip extends StatelessWidget {
  const CoinChip({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GameStyle.feltLight,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              const CoinIcon(size: 26),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: GameStyle.gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              if (onTap != null)
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: GameStyle.gold,
                  ),
                  child: const Icon(Icons.add, size: 16, color: GameStyle.felt),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A player's colour, the same on every screen.
Color playerColor(String name) {
  const palette = [
    Color(0xFF6C4BD8),
    Color(0xFF1E8FA8),
    Color(0xFFB0408F),
    Color(0xFF3E8F5A),
    Color(0xFFD0682A),
    Color(0xFF3F63D1),
    Color(0xFFC23E5A),
    Color(0xFF8A6A2E),
  ];
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// Rounded-square initials avatar for a player.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.color,
    this.dimmed = false,
  });

  final String name;
  final double size;
  final Color? color;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final bg = color ?? playerColor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        color: dimmed ? GameStyle.feltLight : bg,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: Palette.display,
          color: dimmed ? GameStyle.muted : Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
