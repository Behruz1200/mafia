import 'package:contracts/contracts.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../call/call_view.dart';
import '../ui/game_style.dart';
import 'chat_panel.dart';
import 'player_table.dart';
import 'role_setup_panel.dart';

/// Before the match: invite code, who is seated, stake, and Start for the
/// host.
class WaitingRoom extends StatelessWidget {
  const WaitingRoom({
    super.key,
    required this.room,
    required this.players,
    required this.me,
    required this.onStart,
    this.onSetRoles,
    this.onMakeHost,
    this.rematch = false,
  });

  final Room room;

  /// Seated players, once a match has dealt them. Before that the room's
  /// members stand in, with the names the server sends along.
  final List<Player>? players;
  final UserId? me;
  final Future<void> Function() onStart;

  /// Host only: saves the roles for the next match (null: standard deal).
  final Future<void> Function(Map<Role, int>? roleCounts)? onSetRoles;

  /// Host only: hands the host role to another player, who taps their
  /// seat to get here.
  final Future<void> Function(UserId userId)? onMakeHost;

  /// Back here after a match (Play again), so the host is told when
  /// everyone is back.
  final bool rematch;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final seated =
        players ??
        [
          for (final (i, id) in room.memberIds.indexed)
            Player(
              userId: id,
              displayName: room.memberNames[id] ?? '…',
              seat: i,
              isHost: id == room.hostId,
              isConnected: !room.offlineIds.contains(id),
            ),
        ];
    final isHost = room.hostId == me;
    // Only players who are here and back from the last results get a
    // card, so they are the ones who count.
    final ready = room.readyIds.length;
    final total = room.memberIds.length;
    final enough = ready >= room.settings.minPlayers;
    final stake = room.settings.stake;
    final hostName = room.memberNames[room.hostId];
    final (IconData, String)? note = switch (()) {
      _ when !enough && ready < total => (
        Icons.hourglass_top_rounded,
        '${t.gameBackCount(ready, total)} · '
            '${t.gameNeedMorePlayers(room.settings.minPlayers)}',
      ),
      _ when !enough => (
        Icons.group_add_rounded,
        t.gameNeedMorePlayers(room.settings.minPlayers),
      ),
      _ when isHost && ready < total => (
        Icons.hourglass_top_rounded,
        t.gameStartWithBack(ready, total),
      ),
      _ when isHost && rematch => (
        Icons.celebration_rounded,
        t.gameEveryoneBack,
      ),
      _ when ready < total => (
        Icons.hourglass_top_rounded,
        t.gameBackCount(ready, total),
      ),
      _ => null,
    };

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              // Small, so the camera seats get the room: friends at the
              // table already have the code, newcomers can still copy it.
              _RoomBar(
                code: room.inviteCode,
                players: t.gamePlayersCount(
                  seated.length,
                  room.settings.maxPlayers,
                ),
                stake: stake == 0
                    ? t.lobbyStakeFree
                    : t.gameStakeValue(t.coins(stake)),
              ),
              const SizedBox(height: 12),
              // Cameras work here too, so friends can say hello and check
              // their camera and mic before the match.
              SeatReactions(
                roomId: room.id,
                builder: (context, showing) => PlayerTable(
                  players: seated,
                  me: me,
                  notes: {for (final u in room.notBackIds) u: t.gameNotBack},
                  // The host taps a friend's seat to make them the host.
                  selectable: isHost && onMakeHost != null
                      ? {
                          for (final p in seated)
                            if (p.userId != me) p.userId,
                        }
                      : const {},
                  onSelect: (id) => _askMakeHost(
                    context,
                    room.memberNames[id] ??
                        seated.firstWhere((p) => p.userId == id).displayName,
                    () => onMakeHost!(id),
                  ),
                  face: (id, placeholder) =>
                      SeatVideo(userId: id, placeholder: placeholder),
                  overlays: {
                    for (final e in showing.entries)
                      e.key: ReactionPop(emoji: e.value),
                  },
                ),
              ),
              if (isHost && onMakeHost != null && seated.length > 1) ...[
                const SizedBox(height: 10),
                _Note(
                  icon: Icons.star_outline_rounded,
                  text: t.gameTapToMakeHost,
                ),
              ],
              const SizedBox(height: 12),
              RoleSetupPanel(
                room: room,
                // Dealt only to those who are here and back.
                seated: ready,
                isHost: isHost,
                onSetRoles: onSetRoles,
              ),
              const SizedBox(height: 12),
              ChatPanel(roomId: room.id, state: null, private: null, me: me),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: Palette.surfaceSheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            // Lifts the bar off the list, so what scrolls under it reads
            // as more to scroll to and not as a cut-off card.
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                if (note != null)
                  _Note(
                    key: const ValueKey('waiting-note'),
                    icon: note.$1,
                    text: note.$2,
                  ),
                // Camera and mic on the left, Start (or the wait) beside
                // them: one row, so nothing floats alone on a small phone.
                CallControls(
                  roomId: room.id,
                  trailing: isHost
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: enough
                                ? GameStyle.glow(GameStyle.crimson)
                                : null,
                          ),
                          child: FilledButton.icon(
                            key: const ValueKey('start-game'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(t.gameStart, maxLines: 1),
                            ),
                            onPressed: enough ? onStart : null,
                          ),
                        )
                      : Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Palette.surface,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: 8,
                            children: [
                              const Icon(
                                Icons.hourglass_top_rounded,
                                size: 18,
                                color: GameStyle.muted,
                              ),
                              Flexible(
                                child: Text(
                                  hostName == null
                                      ? t.gameWaitingForHost
                                      : t.gameWaitingForHostName(hostName),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: GameStyle.muted,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
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
    );
  }
}

/// Asks the host whether to hand the host role to [name].
Future<void> _askMakeHost(
  BuildContext context,
  String name,
  Future<void> Function() makeHost,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: GameStyle.felt,
    showDragHandle: true,
    builder: (context) {
      final t = AppLocalizations.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                spacing: 14,
                children: [
                  const IconBlob(
                    icon: Icons.star_rounded,
                    color: GameStyle.gold,
                    size: 48,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GameStyle.display(20),
                        ),
                        Text(
                          t.gameMakeHostHint,
                          style: const TextStyle(color: GameStyle.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              FilledButton.icon(
                key: const ValueKey('make-host'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: GameStyle.gold,
                  foregroundColor: GameStyle.felt,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(Icons.star_rounded),
                label: Text(t.gameMakeHost(name)),
                onPressed: () {
                  Navigator.of(context).pop();
                  makeHost();
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// One muted line with an icon, above the bottom bar's buttons.
class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      children: [
        Icon(icon, size: 18, color: GameStyle.muted),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: GameStyle.muted,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

/// The invite code with a copy button, and how many are seated and the
/// stake, in one short row.
class _RoomBar extends StatelessWidget {
  const _RoomBar({
    required this.code,
    required this.players,
    required this.stake,
  });

  final String code;
  final String players;
  final String stake;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return GamePanel(
      key: const ValueKey('room-bar'),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                _Line(
                  icon: Icons.groups_rounded,
                  color: GameStyle.town,
                  text: players,
                ),
                _Line(
                  icon: Icons.toll_rounded,
                  color: GameStyle.gold,
                  text: stake,
                ),
              ],
            ),
          ),
          Tooltip(
            message: t.gameInviteCode,
            child: Material(
              color: GameStyle.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('copy-code'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(t.gameCodeCopied)));
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      Text(
                        code,
                        style: GameStyle.display(
                          20,
                          color: GameStyle.gold,
                        ).copyWith(letterSpacing: 3),
                      ),
                      const Icon(
                        Icons.copy_rounded,
                        size: 18,
                        color: GameStyle.gold,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 6,
      children: [
        Icon(icon, size: 16, color: color),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
