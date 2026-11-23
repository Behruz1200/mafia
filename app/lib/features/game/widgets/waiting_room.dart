import 'package:contracts/contracts.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../call/call_view.dart';
import '../ui/game_style.dart';
import 'player_table.dart';

/// Before the match: invite code, who is seated, stake, and Start for the
/// host.
class WaitingRoom extends StatelessWidget {
  const WaitingRoom({
    super.key,
    required this.room,
    required this.players,
    required this.me,
    required this.onStart,
  });

  final Room room;

  /// Seated players, once a match has dealt them. Before that the room's
  /// members stand in, with the names the server sends along.
  final List<Player>? players;
  final UserId? me;
  final Future<void> Function() onStart;

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
            ),
        ];
    final isHost = room.hostId == me;
    final enough = seated.length >= room.settings.minPlayers;
    final stake = room.settings.stake;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              GamePanel(
                padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: [
                          Text(
                            t.gameInviteCode.toUpperCase(),
                            style: const TextStyle(
                              color: GameStyle.muted,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            room.inviteCode,
                            style: GameStyle.display(
                              32,
                              color: GameStyle.gold,
                            ).copyWith(letterSpacing: 5),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: t.gameCodeCopied,
                      style: IconButton.styleFrom(
                        fixedSize: const Size(52, 52),
                        backgroundColor: GameStyle.gold,
                        foregroundColor: GameStyle.felt,
                      ),
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: room.inviteCode),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(t.gameCodeCopied)),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: _Fact(
                      icon: Icons.groups_rounded,
                      color: GameStyle.town,
                      text: t.gamePlayersCount(
                        seated.length,
                        room.settings.maxPlayers,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _Fact(
                      icon: Icons.toll_rounded,
                      color: GameStyle.gold,
                      text: stake == 0
                          ? t.lobbyStakeFree
                          : t.gameStakeValue(t.coins(stake)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Cameras work here too, so friends can say hello and check
              // their camera and mic before the match.
              PlayerTable(
                players: seated,
                me: me,
                face: (id, placeholder) =>
                    SeatVideo(userId: id, placeholder: placeholder),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: const BoxDecoration(
            color: Palette.surfaceSheet,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                CallControls(roomId: room.id),
                if (!enough)
                  Text(
                    t.gameNeedMorePlayers(room.settings.minPlayers),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: GameStyle.muted),
                  ),
                if (isHost)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: enough
                          ? GameStyle.glow(GameStyle.crimson)
                          : null,
                    ),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(t.gameStart),
                      onPressed: enough ? onStart : null,
                    ),
                  )
                else
                  Text(
                    t.gameWaitingForHost,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: GameStyle.muted),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A small fact about the room: an icon on a tint and a line of text.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      padding: const EdgeInsets.all(10),
      child: Row(
        spacing: 10,
        children: [
          IconBlob(icon: icon, color: color, size: 36),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
