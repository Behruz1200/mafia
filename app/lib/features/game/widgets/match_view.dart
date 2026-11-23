import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../core/theme.dart';
import '../../call/call_view.dart';
import '../ui/game_style.dart';
import '../ui/game_text.dart';
import 'phase_header.dart';
import 'player_table.dart';
import 'role_card.dart';
import 'skip_timer_bar.dart';

/// The table during a match: night, day and voting.
///
/// Holds only what the player is picking right now. Everything else comes
/// from the server's states; the buttons shown follow
/// [PrivatePlayerState.allowedActions].
class MatchView extends StatefulWidget {
  const MatchView({
    super.key,
    required this.roomId,
    required this.state,
    required this.me,
    required this.private,
    required this.onNightAction,
    required this.onVote,
    this.onSkipTimer,
  });

  final RoomId roomId;
  final PublicGameState state;
  final UserId? me;
  final PrivatePlayerState? private;
  final Future<void> Function(String type, UserId target) onNightAction;
  final Future<void> Function(UserId? target) onVote;

  /// Agree or stop agreeing to end the day's timer early.
  final Future<void> Function(bool skip)? onSkipTimer;

  @override
  State<MatchView> createState() => _MatchViewState();
}

class _MatchViewState extends State<MatchView> {
  UserId? _selected;
  bool _sending = false;

  /// The current turn; the pick is cleared whenever it changes.
  String get _turn =>
      '${widget.state.matchId}/${widget.state.round}/${widget.state.phase.name}';
  late String _lastTurn = _turn;

  /// The one action this player may take now, if any.
  String? get _action {
    final allowed = widget.private?.allowedActions ?? const [];
    const order = ['nightKill', 'nightHeal', 'nightCheck', 'castVote'];
    for (final a in order) {
      if (allowed.contains(a)) return a;
    }
    return null;
  }

  Set<UserId> _targets(String? action) {
    final me = widget.me;
    final mates = widget.private?.teammates ?? const [];
    final checks = widget.private?.checks ?? const {};
    final alive = widget.state.alive.map((p) => p.userId);
    return switch (action) {
      'nightKill' => {
        for (final u in alive)
          if (u != me && !mates.contains(u)) u,
      },
      'nightHeal' => alive.toSet(),
      'nightCheck' => {
        for (final u in alive)
          if (u != me && !checks.containsKey(u)) u,
      },
      'castVote' => {
        for (final u in alive)
          if (u != me) u,
      },
      _ => const {},
    };
  }

  String _name(UserId id) =>
      widget.state.players
          .where((p) => p.userId == id)
          .map((p) => p.displayName)
          .firstOrNull ??
      '…';

  bool get _meAlive =>
      widget.state.players.any((p) => p.userId == widget.me && p.isAlive);

  Future<void> _confirm(String action, {bool skip = false}) async {
    setState(() => _sending = true);
    try {
      if (action == 'castVote') {
        await widget.onVote(skip ? null : _selected);
      } else {
        await widget.onNightAction(action, _selected!);
      }
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
    if (_turn != _lastTurn) {
      _lastTurn = _turn;
      _selected = null;
    }
    final s = widget.state;
    final action = _action;
    final targets = _targets(action);
    if (_selected != null && !targets.contains(_selected)) _selected = null;
    final role = widget.private?.role;
    final isNight = s.phase == GamePhase.night;
    final events = [for (final e in s.log.reversed) ?t.eventText(e, _name)];

    final sleeping = isNight && action == null && _meAlive;
    final canSkip =
        widget.onSkipTimer != null &&
        (widget.private?.allowedActions ?? const []).contains('skipPhase');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            spacing: 10,
            children: [
              Expanded(child: PhaseHeader(state: s)),
              if (role != null)
                RolePeekButton(
                  role: role,
                  teammateNames: [
                    for (final m in widget.private!.teammates) _name(m),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              PlayerTable(
                players: s.players,
                me: widget.me,
                private: widget.private,
                votes: s.phase == GamePhase.voting ? s.votes : const {},
                selectable: _sending ? const {} : targets,
                selected: _selected,
                onSelect: (u) => setState(() => _selected = u),
                // Stream 3 (video) owns SeatVideo: each seat is that
                // player's camera.
                face: (id, placeholder) =>
                    SeatVideo(userId: id, placeholder: placeholder),
              ),
              const SizedBox(height: 14),
              _Prompt(
                text: _promptText(t, action),
                latest: events.firstOrNull,
                icon: !_meAlive
                    ? Icons.visibility_rounded
                    : sleeping
                    ? Icons.bedtime_rounded
                    : action != null
                    ? Icons.touch_app_rounded
                    : Icons.forum_rounded,
                color: !_meAlive
                    ? GameStyle.muted
                    : isNight
                    ? GameStyle.moon
                    : action != null
                    ? GameStyle.crimson
                    : GameStyle.gold,
              ),
              if (events.length > 1) ...[
                const SizedBox(height: 12),
                _EventLog(lines: events.skip(1).toList()),
              ],
            ],
          ),
        ),
        _BottomBar(
          action: action == null
              ? (canSkip
                    ? SkipTimerBar(
                        state: s,
                        me: widget.me,
                        onSkip: widget.onSkipTimer!,
                      )
                    : null)
              : _ActionBar(
                  confirmText: _selected == null
                      ? t.gameConfirm
                      : '${t.gameConfirm}: ${_name(_selected!)}',
                  onConfirm: _selected == null || _sending
                      ? null
                      : () => _confirm(action),
                  onSkip: action == 'castVote' && !_sending
                      ? () => _confirm(action, skip: true)
                      : null,
                  skipText: t.gameSkipVote,
                ),
          // Stream 3 (video) owns CallControls. It stays mounted for the
          // whole match: the call joins and leaves with it.
          call: CallControls(roomId: widget.roomId),
        ),
      ],
    );
  }

  String _promptText(AppLocalizations t, String? action) {
    if (!_meAlive) return t.gameDeadSpectator;
    return switch ((widget.state.phase, action)) {
      (_, 'nightKill') => t.gameNightKillPrompt,
      (_, 'nightHeal') => t.gameNightHealPrompt,
      (_, 'nightCheck') => t.gameNightCheckPrompt,
      (_, 'castVote') => t.gameVotePrompt,
      (GamePhase.night, _) => t.gameNightSleep,
      (GamePhase.day, _) => t.gameDayPrompt,
      _ => t.gameActionSent,
    };
  }
}

/// What to do now, with the latest thing that happened under it.
class _Prompt extends StatelessWidget {
  const _Prompt({
    required this.text,
    required this.icon,
    required this.color,
    this.latest,
  });

  final String text;
  final IconData icon;
  final Color color;
  final String? latest;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        spacing: 12,
        children: [
          IconBlob(icon: icon, color: color, size: 40),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    height: 1.3,
                  ),
                ),
                if (latest != null)
                  Text(
                    latest!,
                    style: const TextStyle(
                      color: GameStyle.muted,
                      fontSize: 13,
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

class _EventLog extends StatelessWidget {
  const _EventLog({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return GamePanel(
      color: Colors.transparent,
      borderColor: Palette.outlineSoft,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text(
            t.gameLogTitle.toUpperCase(),
            style: const TextStyle(
              color: GameStyle.muted,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
          for (final line in lines.take(5))
            Text(line, style: const TextStyle(color: GameStyle.muted)),
        ],
      ),
    );
  }
}

/// The bottom of the table: the pick-and-confirm row when the player has
/// something to do, and the camera and mic under it.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.action, required this.call});

  final Widget? action;
  final Widget call;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Palette.surfaceSheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [?action, call],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.confirmText,
    required this.onConfirm,
    required this.onSkip,
    required this.skipText,
  });

  final String confirmText;
  final VoidCallback? onConfirm;
  final VoidCallback? onSkip;
  final String skipText;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 10,
      children: [
        if (onSkip != null)
          OutlinedButton(onPressed: onSkip, child: Text(skipText)),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: onConfirm == null
                  ? null
                  : GameStyle.glow(GameStyle.crimson),
            ),
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: onConfirm,
              child: Text(
                confirmText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
