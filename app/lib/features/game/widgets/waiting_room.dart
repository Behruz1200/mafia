import 'package:contracts/contracts.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
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

  /// Seated players with names, once the server has sent them. Until then
  /// the room's member ids stand in.
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
              displayName: id,
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
            padding: const EdgeInsets.all(16),
            children: [
              GamePanel(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: [
                          Text(
                            t.gameInviteCode,
                            style: const TextStyle(color: GameStyle.muted),
                          ),
                          Text(
                            room.inviteCode,
                            style: const TextStyle(
                              fontSize: 32,
                              letterSpacing: 6,
                              fontWeight: FontWeight.w800,
                              color: GameStyle.gold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: t.gameCodeCopied,
                      icon: const Icon(Icons.copy),
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.group, size: 18),
                    label: Text(
                      t.gamePlayersCount(
                        seated.length,
                        room.settings.maxPlayers,
                      ),
                    ),
                  ),
                  Chip(
                    avatar: const Icon(
                      Icons.toll,
                      size: 18,
                      color: GameStyle.gold,
                    ),
                    label: Text(
                      stake == 0
                          ? t.lobbyStakeFree
                          : t.gameStakeValue(t.coins(stake)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              PlayerTable(players: seated, me: me),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: GameStyle.felt,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                if (!enough)
                  Text(
                    t.gameNeedMorePlayers(room.settings.minPlayers),
                    style: const TextStyle(color: GameStyle.muted),
                  ),
                if (isHost)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: GameStyle.crimson,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(t.gameStart),
                    onPressed: enough ? onStart : null,
                  )
                else
                  Text(
                    t.gameWaitingForHost,
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
