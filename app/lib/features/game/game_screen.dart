import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/routes.dart';
import '../../l10n/generated/app_localizations.dart';
import 'game_providers.dart';
import 'ui/game_style.dart';
import 'widgets/match_view.dart';
import 'widgets/phase_header.dart';
import 'widgets/results_view.dart';
import 'widgets/role_card.dart';
import 'widgets/waiting_room.dart';

/// Stream 6 (game UI) owns this folder: the table, role card, night
/// actions, voting, results. It embeds the call from stream 3 and only
/// talks to the game through `RoomRepository`.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.roomId});

  final RoomId roomId;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  /// The match whose results the player has closed, to show the waiting
  /// room again.
  MatchId? _dismissedMatch;

  Future<void> _leave() async {
    final t = AppLocalizations.of(context);
    final phase = ref.read(publicStateProvider(widget.roomId)).value?.phase;
    final inMatch =
        phase != null && phase != GamePhase.lobby && phase != GamePhase.ended;
    if (inMatch) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.gameLeaveConfirmTitle),
          content: Text(t.gameLeaveConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.gameStay),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: GameStyle.crimson),
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.gameLeave),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref.read(gameActionsProvider(widget.roomId)).leave();
    if (mounted) context.go(Routes.lobby);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final id = widget.roomId;
    final me = ref.watch(myUserIdProvider);
    final actions = ref.watch(gameActionsProvider(id));
    final room = ref.watch(roomProvider(id)).value;
    final public = ref.watch(publicStateProvider(id)).value;
    final private = ref.watch(myStateProvider(id)).value;
    final result = ref.watch(matchEndProvider(id)).value;
    final isDemo = actions.demo != null;

    final showWaiting =
        public == null ||
        public.phase == GamePhase.lobby ||
        (public.phase == GamePhase.ended && public.matchId == _dismissedMatch);

    final Widget body;
    if (room == null) {
      body = Center(child: Text(t.gameConnecting));
    } else if (showWaiting) {
      body = WaitingRoom(
        room: room,
        players: public?.players,
        me: me,
        onStart: actions.startMatch,
      );
    } else if (public.phase == GamePhase.roleReveal) {
      body = _RoleReveal(state: public, private: private);
    } else if (public.phase == GamePhase.ended) {
      body = ResultsView(
        state: public,
        result: result?.matchId == public.matchId ? result : null,
        me: me,
        onPlayAgain: () {
          setState(() => _dismissedMatch = public.matchId);
          actions.playAgain();
        },
        onBackToLobby: _leave,
      );
    } else {
      body = MatchView(
        roomId: id,
        state: public,
        me: me,
        private: private,
        onNightAction: actions.nightAction,
        onVote: actions.vote,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: GameStyle.backgroundFor(
            showWaiting ? GamePhase.lobby : public.phase,
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            leading: IconButton(
              tooltip: t.gameLeave,
              icon: const Icon(Icons.close),
              onPressed: _leave,
            ),
            title: Text(showWaiting ? t.gameWaitingTitle : t.appTitle),
            actions: [
              if (isDemo)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(t.gameDemoBadge),
                    side: BorderSide.none,
                    backgroundColor: GameStyle.gold.withValues(alpha: 0.18),
                  ),
                ),
            ],
          ),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: KeyedSubtree(
              // Night, day and voting share one subtree so the call and
              // the table are not rebuilt between phases.
              key: ValueKey(switch (showWaiting
                  ? GamePhase.lobby
                  : public.phase) {
                GamePhase.night || GamePhase.day || GamePhase.voting => 'match',
                final p => p.name,
              }),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleReveal extends StatelessWidget {
  const _RoleReveal({required this.state, required this.private});

  final PublicGameState state;
  final PrivatePlayerState? private;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final mates = private?.teammates ?? const [];
    String name(UserId id) =>
        state.players
            .where((p) => p.userId == id)
            .map((p) => p.displayName)
            .firstOrNull ??
        '…';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          PhaseHeader(state: state),
          const SizedBox(height: 24),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: private == null
                    ? Text(t.gameConnecting)
                    : RoleCard(
                        role: private!.role,
                        teammateNames: [for (final m in mates) name(m)],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
