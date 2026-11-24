import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../ui/game_style.dart';
import '../ui/game_text.dart';
import '../ui/noir_art.dart';

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
  const _CardFrame({required this.child, required this.rim});

  final Widget child;

  /// The neon edge and glow.
  final Color rim;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.68,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: rim, width: 2),
          boxShadow: GameStyle.glow(rim),
        ),
        child: child,
      ),
    );
  }
}

const _cardColor = Color(0xFF120A22);

/// Fades the bottom of the art into the card.
const _fade = DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x00120A22), _cardColor],
      stops: [0.7, 1],
    ),
  ),
);

class _Back extends StatelessWidget {
  const _Back();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _CardFrame(
      rim: GameStyle.moon,
      child: Stack(
        children: [
          const Positioned.fill(
            child: NightCity(
              figure: false,
              moon: Alignment(-0.5, -0.65),
              shadeLeft: false,
            ),
          ),
          const Positioned.fill(child: _fade),
          // A glowing fedora in the middle.
          Align(
            alignment: const Alignment(0, -0.2),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: const FedoraIcon(size: 150, color: GameStyle.crimson),
                ),
                const FedoraIcon(
                  size: 140,
                  color: NoirArt.ink,
                  band: GameStyle.crimson,
                ),
              ],
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 20,
            child: Column(
              spacing: 12,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    t.appTitle.toUpperCase(),
                    style: GameStyle.display(30, color: Colors.white).copyWith(
                      letterSpacing: 2,
                      shadows: [
                        Shadow(
                          color: GameStyle.crimson.withValues(alpha: 0.9),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    t.gameTapToReveal,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
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
    final rim = NoirArt.rim(role);
    // "Town" over a Doctor; nothing over the Mafia, which says it.
    final team = t.teamName(role.team) == t.roleName(role)
        ? null
        : t.teamName(role.team).toUpperCase();
    return _CardFrame(
      rim: rim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(
                  child: NightCity(
                    figure: false,
                    moon: Alignment(-0.55, -0.45),
                    shadeLeft: false,
                  ),
                ),
                Positioned.fill(
                  top: 18,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: RolePortrait(role: role),
                  ),
                ),
                const Positioned.fill(child: _fade),
                if (team != null)
                  Positioned(
                    left: 14,
                    top: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: rim.withValues(alpha: 0.6)),
                      ),
                      child: Text(
                        team,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 1.4,
                          color: rim,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    t.roleName(role).toUpperCase(),
                    style: GameStyle.display(34, color: Colors.white).copyWith(
                      letterSpacing: 1,
                      shadows: [
                        Shadow(
                          color: rim.withValues(alpha: 0.9),
                          blurRadius: 14,
                        ),
                        Shadow(color: rim, blurRadius: 3),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t.roleGoal(role),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: Color(0xFFD9D3F2),
                  ),
                ),
                if (teammateNames.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: rim.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: rim.withValues(alpha: 0.45)),
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
              ],
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
