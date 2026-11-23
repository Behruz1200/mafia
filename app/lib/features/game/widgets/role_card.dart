import 'dart:math';

import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../ui/game_style.dart';
import '../ui/game_text.dart';

/// The player's secret role card. Face down until tapped, then flips.
class RoleCard extends StatefulWidget {
  const RoleCard({
    super.key,
    required this.role,
    this.teammateNames = const [],
    this.startFaceUp = false,
  });

  final Role role;
  final List<String> teammateNames;
  final bool startFaceUp;

  @override
  State<RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<RoleCard> {
  late bool _faceUp = widget.startFaceUp;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _faceUp = !_faceUp),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _faceUp ? 1 : 0),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        builder: (context, v, _) {
          final showFront = v >= 0.5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(pi * v),
            child: showFront
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(pi),
                    child: _Front(
                      role: widget.role,
                      teammateNames: widget.teammateNames,
                    ),
                  )
                : const _Back(),
          );
        },
      ),
    );
  }
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child, required this.colors});

  final Widget child;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.68,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: GameStyle.glow(colors.first),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -60,
              top: -60,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.all(22), child: child),
          ],
        ),
      ),
    );
  }
}

/// The big round badge in the middle of a card.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.22),
      ),
      child: Icon(icon, size: 62, color: Colors.white),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _CardFrame(
      colors: const [Color(0xFF4B2A9E), Color(0xFF1A1040)],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 18,
        children: [
          const _Badge(icon: Icons.question_mark_rounded),
          Text(
            t.appTitle.toUpperCase(),
            style: GameStyle.display(30, color: Colors.white),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              t.gameTapToReveal,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _Front extends StatelessWidget {
  const _Front({required this.role, required this.teammateNames});

  final Role role;
  final List<String> teammateNames;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _CardFrame(
      colors: GameStyle.teamGradient(role.team),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "Town" over a Doctor; nothing over the Mafia, which says it.
          Text(
            t.teamName(role.team) == t.roleName(role)
                ? ''
                : t.teamName(role.team).toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 1.4,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const Spacer(),
          Center(child: _Badge(icon: GameStyle.roleIcon(role))),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              t.roleName(role).toUpperCase(),
              style: GameStyle.display(34, color: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            t.roleGoal(role),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          if (teammateNames.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                t.gameTeammates(teammateNames.join(', ')),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small "my role" button for the table; shows the card in a sheet.
class RolePeekButton extends StatelessWidget {
  const RolePeekButton({
    super.key,
    required this.role,
    this.teammateNames = const [],
  });

  final Role role;
  final List<String> teammateNames;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return IconButton(
      tooltip: t.gameMyRole,
      style: IconButton.styleFrom(
        fixedSize: const Size(52, 52),
        backgroundColor: GameStyle.card,
        foregroundColor: GameStyle.gold,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      icon: const Icon(Icons.style_rounded),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(48, 8, 48, 40),
          child: SizedBox(
            height: 400,
            child: Center(
              child: RoleCard(
                role: role,
                teammateNames: teammateNames,
                startFaceUp: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
