import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/last_room.dart';
import '../../core/routes.dart';
import '../../l10n/generated/app_localizations.dart';
import '../call/call_providers.dart';
import '../../core/providers.dart';
import '../rooms/data/http_room_repository.dart';
import 'game_providers.dart';
import 'ui/game_text.dart';
import 'ui/game_style.dart';
import 'ui/noir_art.dart';
import 'widgets/match_view.dart';
import 'widgets/phase_header.dart';
import 'widgets/results_view.dart';
import 'widgets/role_card.dart';
import 'widgets/skip_timer_bar.dart';
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

  /// The last match's final table, kept so a player still reading the
  /// results is not pulled into a match that started without them.
  PublicGameState? _ended;

  /// How many of my actions the server has refused, so the table can let
  /// me pick again.
  int _refusals = 0;

  void _onRefused(SocketError e) {
    final t = AppLocalizations.of(context);
    if (!e.code.startsWith('chat_')) setState(() => _refusals++);
    final text = t.errorText(e.code, fallback: t.errorNotSent);
    if (text == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Remember the room, so a reload or restart brings the player back.
    ref.read(lastRoomStoreProvider).write(widget.roomId);
    // Back from the lock screen or another app: reconnect at once, so the
    // seat is not lost to the 60-second away rule, ask again for the room
    // and the table, and rejoin the call in case a camera froze.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        final repo = ref.read(roomRepositoryProvider);
        if (repo is HttpRoomRepository) repo.wake();
        ref.read(callSessionProvider(widget.roomId)).resync();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

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
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.gameLeave),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref.read(gameActionsProvider(widget.roomId)).leave();
    await ref.read(lastRoomStoreProvider).write(null);
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
    ref.listen(roomProvider(id), (prev, next) {
      final was = prev?.value?.hostId;
      final now = next.value?.hostId;
      if (was != null && was != me && now == me && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t.gameYouAreHostNow)));
      }
    });
    ref.listen(roomErrorsProvider, (_, next) {
      final e = next.value;
      if (e != null) _onRefused(e);
    });
    // The call lives as long as this screen, so players can see and hear
    // each other in the waiting room and stay connected into the match.
    ref.watch(callSessionProvider(id));

    if (public != null && public.phase == GamePhase.ended) _ended = public;
    final ended = _ended;
    // Still on the last results by the server's count.
    final notBack = room != null && me != null && room.notBackIds.contains(me);
    // A match I am not in started while I was reading the results.
    final startedWithoutMe =
        notBack &&
        ended != null &&
        public != null &&
        public.matchId != ended.matchId &&
        public.phase != GamePhase.lobby &&
        !public.players.any((p) => p.userId == me);
    final showWaiting =
        !startedWithoutMe &&
        (public == null ||
            public.phase == GamePhase.lobby ||
            (public.phase == GamePhase.ended &&
                public.matchId == _dismissedMatch));

    final Widget body;
    if (room == null) {
      body = Center(child: Text(t.gameConnecting));
    } else if (showWaiting) {
      body = WaitingRoom(
        room: room,
        // After Play again the last match's table is still the latest
        // state; the waiting room shows who is seated now instead.
        players: public?.phase == GamePhase.lobby ? public!.players : null,
        me: me,
        onStart: actions.startMatch,
        onSetRoles: actions.setRoles,
        onMakeHost: actions.setHost,
        rematch: public?.phase == GamePhase.ended,
      );
    } else if (startedWithoutMe) {
      final last = ended;
      body = ResultsView(
        state: last,
        result: result?.matchId == last.matchId ? result : null,
        me: me,
        room: room,
        startedWithoutMe: true,
        onPlayAgain: () {
          setState(() => _dismissedMatch = last.matchId);
          actions.playAgain();
        },
        onBackToLobby: _leave,
      );
    } else if (public.phase == GamePhase.roleReveal) {
      body = _RoleReveal(
        state: public,
        private: private,
        me: me,
        onSkipTimer: (skip) => actions.skipTimer(skip: skip),
      );
    } else if (public.phase == GamePhase.ended) {
      body = ResultsView(
        state: public,
        result: result?.matchId == public.matchId ? result : null,
        me: me,
        room: room,
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
        onSkipTimer: (skip) => actions.skipTimer(skip: skip),
        refusals: _refusals,
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The city at night along the bottom, and rain after dark.
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Opacity(opacity: 0.3, child: SkylineStrip(height: 120)),
            ),
            if (!showWaiting && public.phase == GamePhase.night)
              const RainLayer(),
            Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: IconButton(
                    tooltip: t.gameLeave,
                    style: IconButton.styleFrom(
                      backgroundColor: GameStyle.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _leave,
                  ),
                ),
                leadingWidth: 64,
                title: Text(showWaiting ? t.gameWaitingTitle : t.appTitle),
                actions: [
                  if (isDemo)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          t.gameDemoBadge,
                          style: const TextStyle(color: GameStyle.gold),
                        ),
                        side: BorderSide.none,
                        backgroundColor: GameStyle.gold.withValues(alpha: 0.16),
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
                    GamePhase.night ||
                    GamePhase.day ||
                    GamePhase.voting ||
                    GamePhase.lastWord => 'match',
                    final p => p.name,
                  }),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleReveal extends StatelessWidget {
  const _RoleReveal({
    required this.state,
    required this.private,
    required this.me,
    required this.onSkipTimer,
  });

  final PublicGameState state;
  final PrivatePlayerState? private;
  final UserId? me;
  final Future<void> Function(bool skip) onSkipTimer;

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
          if (private?.allowedActions.contains('skipPhase') ?? false)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SkipTimerBar(state: state, me: me, onSkip: onSkipTimer),
            ),
        ],
      ),
    );
  }
}
