import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

/// The look of the lobby and the match table. Night-club dark: deep navy
/// felt, crimson for the Mafia, teal for the town, gold for coins.
///
/// Kept inside the game UI folders so the app-wide theme (foundation) stays
/// untouched; if the team likes it, it can move into `core/theme.dart`.
abstract final class GameStyle {
  static const felt = Color(0xFF12161F);
  static const feltLight = Color(0xFF1C2230);
  static const card = Color(0xFF232A3A);
  static const crimson = Color(0xFFD32F2F);
  static const town = Color(0xFF26A69A);
  static const gold = Color(0xFFF2C14E);
  static const moon = Color(0xFF9FA8DA);
  static const sun = Color(0xFFFFB74D);
  static const muted = Color(0xFF8A93A6);

  static const radius = 18.0;

  static const nightGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF070A12), Color(0xFF141A2E)],
  );

  static const dayGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2A2233), felt],
  );

  static const lobbyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3A0F14), felt, felt],
  );

  static Color teamColor(Team team) => switch (team) {
    Team.town => town,
    Team.mafia => crimson,
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
    GamePhase.lobby || null => lobbyGradient,
    _ => dayGradient,
  };
}

/// A rounded, slightly raised panel used across the game screens.
class GamePanel extends StatelessWidget {
  const GamePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
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
        color: color ?? GameStyle.card.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(GameStyle.radius),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: child,
    );
  }
}

/// The gold coin pill shown in app bars.
class CoinChip extends StatelessWidget {
  const CoinChip({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GameStyle.gold.withValues(alpha: 0.15),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              const Icon(Icons.toll, size: 18, color: GameStyle.gold),
              Text(
                label,
                style: const TextStyle(
                  color: GameStyle.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round initials avatar for a player.
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

  static const _palette = [
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFAB47BC),
    Color(0xFFEF6C00),
    Color(0xFF42A5F5),
    Color(0xFF8D6E63),
    Color(0xFFEC407A),
    Color(0xFF9CCC65),
  ];

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final bg = color ?? _palette[name.hashCode.abs() % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dimmed ? Colors.grey.shade800 : bg,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: dimmed ? Colors.grey.shade500 : Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
