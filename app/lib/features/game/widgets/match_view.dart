import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../call/call_view.dart';
import '../ui/game_style.dart';
import '../ui/game_text.dart';
import 'phase_header.dart';
import 'player_table.dart';
import 'role_card.dart';

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
  });

  final RoomId roomId;
  final PublicGameState state;
  final UserId? me;
  final PrivatePlayerState? private;
  final Future<void> Function(String type, UserId target) onNightAction;
  final Future<void> Function(UserId? target) onVote;

  @override
  State<MatchView> createState() => _MatchViewState();
}

class _MatchViewState extends State<MatchView> {
  UserId? _selected;
  bool _sending = false;
  bool _videoOpen = true;

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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
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
              _VideoPanel(
                open: _videoOpen,
                onToggle: () => setState(() => _videoOpen = !_videoOpen),
                sleeping: isNight && action == null && _meAlive,
              ),
              const SizedBox(height: 12),
              _Prompt(
                text: _promptText(t, action),
                icon: _meAlive ? Icons.info_outline : Icons.visibility,
              ),
              const SizedBox(height: 12),
              PlayerTable(
                players: s.players,
                me: widget.me,
                private: widget.private,
                votes: s.phase == GamePhase.voting ? s.votes : const {},
                selectable: _sending ? const {} : targets,
                selected: _selected,
                onSelect: (u) => setState(() => _selected = u),
              ),
              if (events.isNotEmpty) ...[
                const SizedBox(height: 12),
                _EventLog(lines: events),
              ],
            ],
          ),
        ),
        if (action != null)
          _ActionBar(
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

class _VideoPanel extends StatelessWidget {
  const _VideoPanel({
    required this.open,
    required this.onToggle,
    required this.sleeping,
  });

  final bool open;
  final VoidCallback onToggle;
  final bool sleeping;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return GamePanel(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.videocam, size: 18, color: GameStyle.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.gameVideo,
                  style: const TextStyle(color: GameStyle.muted),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                onPressed: onToggle,
              ),
            ],
          ),
          // The call stays mounted for the whole match (it joins and
          // leaves with its widget); collapsing only hides it.
          Visibility(
            visible: open,
            maintainState: true,
            child: SizedBox(
              height: 190,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Stream 3 (video) owns this widget.
                  const CallView(),
                  if (sleeping)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xF0070A12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 8,
                          children: [
                            const Icon(
                              Icons.bedtime,
                              size: 48,
                              color: GameStyle.moon,
                            ),
                            Text(
                              t.gameNightSleep,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: GameStyle.moon),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      children: [
        Icon(icon, size: 18, color: GameStyle.gold),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text(
            t.gameLogTitle,
            style: const TextStyle(
              color: GameStyle.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final (i, line) in lines.take(6).indexed)
            Text(
              line,
              style: TextStyle(
                color: i == 0 ? Colors.white : GameStyle.muted,
                fontWeight: i == 0 ? FontWeight.w600 : null,
              ),
            ),
        ],
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: GameStyle.felt,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          spacing: 12,
          children: [
            if (onSkip != null)
              OutlinedButton(onPressed: onSkip, child: Text(skipText)),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: GameStyle.crimson,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: onConfirm,
                child: Text(
                  confirmText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
