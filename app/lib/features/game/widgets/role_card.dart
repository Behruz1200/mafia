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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          border: Border.all(color: GameStyle.gold.withValues(alpha: 0.5)),
          boxShadow: const [
            BoxShadow(
              blurRadius: 24,
              color: Colors.black54,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _CardFrame(
      colors: const [Color(0xFF3A0F14), Color(0xFF12161F)],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 16,
        children: [
          const Icon(Icons.theater_comedy, size: 72, color: GameStyle.gold),
          Text(
            t.appTitle.toUpperCase(),
            style: const TextStyle(
              letterSpacing: 6,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: GameStyle.gold,
            ),
          ),
          Text(
            t.gameTapToReveal,
            textAlign: TextAlign.center,
            style: const TextStyle(color: GameStyle.muted),
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
    final color = GameStyle.teamColor(role.team);
    return _CardFrame(
      colors: [color.withValues(alpha: 0.55), GameStyle.felt],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 12,
        children: [
          Icon(GameStyle.roleIcon(role), size: 72, color: Colors.white),
          Text(
            t.roleName(role),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          if (t.teamName(role.team) != t.roleName(role))
            Chip(
              label: Text(t.teamName(role.team)),
              backgroundColor: color.withValues(alpha: 0.3),
              side: BorderSide.none,
            ),
          Text(t.roleGoal(role), textAlign: TextAlign.center),
          if (teammateNames.isNotEmpty)
            Text(
              t.gameTeammates(teammateNames.join(', ')),
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
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
      icon: const Icon(Icons.style),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: GameStyle.felt,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(48, 24, 48, 32),
          child: SizedBox(
            height: 380,
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
