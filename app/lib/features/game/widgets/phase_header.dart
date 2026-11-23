import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../ui/game_style.dart';
import '../ui/game_text.dart';

/// Phase name, round and a live countdown to [PublicGameState.phaseEndsAt].
class PhaseHeader extends StatelessWidget {
  const PhaseHeader({super.key, required this.state});

  final PublicGameState state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (icon, color) = switch (state.phase) {
      GamePhase.night => (Icons.nightlight_round, GameStyle.moon),
      GamePhase.day => (Icons.wb_sunny_rounded, GameStyle.sun),
      GamePhase.voting => (Icons.how_to_vote_rounded, GameStyle.crimson),
      GamePhase.roleReveal => (Icons.style_rounded, GameStyle.gold),
      GamePhase.lastWord => (Icons.record_voice_over_rounded, GameStyle.gold),
      _ => (Icons.flag_rounded, GameStyle.gold),
    };
    return Container(
      height: 52,
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        spacing: 10,
        children: [
          Icon(icon, color: color, size: 22),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.phaseName(state.phase),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: Palette.display,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    height: 1.2,
                    color: color,
                  ),
                ),
                if (state.round > 0)
                  Text(
                    t.gameRound(state.round),
                    style: TextStyle(
                      color: color.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
              ],
            ),
          ),
          if (state.phaseEndsAt != null)
            Countdown(endsAt: state.phaseEndsAt!, color: color),
        ],
      ),
    );
  }
}

/// Seconds left, as `0:42`. Stops ticking at zero.
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.endsAt, this.color});

  final DateTime endsAt;
  final Color? color;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _timer;

  Duration get _left {
    final d = widget.endsAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(Countdown old) {
    super.didUpdateWidget(old);
    if (old.endsAt != widget.endsAt) _start();
  }

  void _start() {
    _timer?.cancel();
    if (_left == Duration.zero) return;
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_left == Duration.zero) _timer?.cancel();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = (_left.inMilliseconds / 1000).ceil();
    final text = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    final urgent = s <= 5;
    final color = urgent ? GameStyle.crimson : (widget.color ?? GameStyle.gold);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: urgent ? color : Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: Palette.display,
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: urgent ? Colors.white : color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
