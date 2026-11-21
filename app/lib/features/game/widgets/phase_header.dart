import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

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
      GamePhase.day => (Icons.wb_sunny, GameStyle.sun),
      GamePhase.voting => (Icons.how_to_vote, GameStyle.crimson),
      GamePhase.roleReveal => (Icons.style, GameStyle.gold),
      _ => (Icons.flag, GameStyle.gold),
    };
    return Row(
      spacing: 12,
      children: [
        Icon(icon, color: color, size: 28),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.phaseName(state.phase),
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (state.round > 0)
                Text(
                  t.gameRound(state.round),
                  style: const TextStyle(color: GameStyle.muted),
                ),
            ],
          ),
        ),
        if (state.phaseEndsAt != null)
          Countdown(endsAt: state.phaseEndsAt!, color: color),
      ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (urgent ? GameStyle.crimson : (widget.color ?? GameStyle.gold))
            .withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          const Icon(Icons.timer_outlined, size: 18),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
