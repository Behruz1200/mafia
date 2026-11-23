import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../ui/game_style.dart';

/// "Skip timer" during the day's talk (and the role reveal). Each living
/// player taps it; the server ends the timer only once all of them have,
/// so one player can never skip for everyone. Shows how many agreed and
/// lets the player take theirs back.
class SkipTimerBar extends StatefulWidget {
  const SkipTimerBar({
    super.key,
    required this.state,
    required this.me,
    required this.onSkip,
  });

  final PublicGameState state;
  final UserId? me;

  /// true to agree, false to take it back.
  final Future<void> Function(bool skip) onSkip;

  @override
  State<SkipTimerBar> createState() => _SkipTimerBarState();
}

class _SkipTimerBarState extends State<SkipTimerBar> {
  bool _sending = false;

  Future<void> _send(bool skip) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSkip(skip);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).lobbyError)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final alive = {for (final p in widget.state.alive) p.userId};
    final agreed = widget.state.skipVotes.where(alive.contains).length;
    final total = alive.length;
    final mine = widget.state.skipVotes.contains(widget.me);
    final progress = total == 0 ? 0.0 : agreed / total;

    if (mine) {
      return Container(
        key: const ValueKey('skip-agreed'),
        height: 52,
        padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
        decoration: BoxDecoration(
          color: GameStyle.town.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: GameStyle.town.withValues(alpha: 0.5)),
        ),
        child: Row(
          spacing: 10,
          children: [
            SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                color: GameStyle.town,
                backgroundColor: GameStyle.town.withValues(alpha: 0.2),
              ),
            ),
            Expanded(
              child: Text(
                t.gameSkipAgreed(agreed, total),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: _sending ? null : () => _send(false),
              style: TextButton.styleFrom(foregroundColor: GameStyle.muted),
              child: Text(t.gameSkipUndo),
            ),
          ],
        ),
      );
    }

    return Tooltip(
      message: t.gameSkipHint,
      child: OutlinedButton.icon(
        key: const ValueKey('skip-timer'),
        onPressed: _sending ? null : () => _send(true),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: GameStyle.town,
          side: BorderSide(
            color: GameStyle.town.withValues(alpha: 0.6),
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: Palette.display,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        icon: const Icon(Icons.fast_forward_rounded),
        label: Text(
          agreed == 0 ? t.gameSkipTimer : t.gameSkipTimerCount(agreed, total),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
