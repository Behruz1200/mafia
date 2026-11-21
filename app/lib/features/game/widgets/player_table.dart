import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../ui/game_style.dart';
import '../ui/game_text.dart';

/// Everyone at the table, in seat order. Shows who is alive, open vote
/// counts, and what only I know (my Mafia teammates, my check results).
/// When [selectable] is not empty, those seats can be tapped to pick a
/// target.
class PlayerTable extends StatelessWidget {
  const PlayerTable({
    super.key,
    required this.players,
    required this.me,
    this.private,
    this.votes = const {},
    this.selectable = const {},
    this.selected,
    this.onSelect,
  });

  final List<Player> players;
  final UserId? me;
  final PrivatePlayerState? private;
  final Map<UserId, UserId?> votes;
  final Set<UserId> selectable;
  final UserId? selected;
  final ValueChanged<UserId>? onSelect;

  @override
  Widget build(BuildContext context) {
    final tally = <UserId, int>{};
    for (final target in votes.values) {
      if (target != null) tally[target] = (tally[target] ?? 0) + 1;
    }
    final seats = [...players]..sort((a, b) => a.seat.compareTo(b.seat));
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth > 560 ? 6 : 4;
        return GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: seats.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (context, i) {
            final p = seats[i];
            return SeatTile(
              key: ValueKey('seat-${p.userId}'),
              player: p,
              isMe: p.userId == me,
              isTeammate: private?.teammates.contains(p.userId) ?? false,
              checked: private?.checks[p.userId],
              votes: tally[p.userId] ?? 0,
              myVote: me != null && votes[me] == p.userId,
              selectable: selectable.contains(p.userId),
              selected: selected == p.userId,
              onTap: selectable.contains(p.userId) && onSelect != null
                  ? () => onSelect!(p.userId)
                  : null,
            );
          },
        );
      },
    );
  }
}

class SeatTile extends StatelessWidget {
  const SeatTile({
    super.key,
    required this.player,
    this.isMe = false,
    this.isTeammate = false,
    this.checked,
    this.votes = 0,
    this.myVote = false,
    this.selectable = false,
    this.selected = false,
    this.onTap,
  });

  final Player player;
  final bool isMe;
  final bool isTeammate;
  final Team? checked;
  final int votes;
  final bool myVote;
  final bool selectable;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final dead = !player.isAlive;
    final border = selected
        ? GameStyle.gold
        : selectable
        ? Colors.white.withValues(alpha: 0.35)
        : isTeammate
        ? GameStyle.crimson.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.06);
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: player.displayName,
      child: Material(
        color: selected
            ? GameStyle.gold.withValues(alpha: 0.16)
            : GameStyle.card.withValues(alpha: dead ? 0.4 : 0.85),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 6,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        PlayerAvatar(name: player.displayName, dimmed: dead),
                        if (dead)
                          const Positioned.fill(
                            child: Icon(
                              Icons.close,
                              color: GameStyle.crimson,
                              size: 40,
                            ),
                          ),
                        if (player.isHost)
                          const Positioned(
                            top: -8,
                            right: -8,
                            child: Icon(
                              Icons.star,
                              size: 18,
                              color: GameStyle.gold,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      isMe ? t.gameYou : player.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isMe ? FontWeight.w800 : FontWeight.w500,
                        color: dead ? GameStyle.muted : null,
                        decoration: dead ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (checked != null)
                      _Tag(
                        text: t.teamName(checked!),
                        color: GameStyle.teamColor(checked!),
                      )
                    else if (isTeammate)
                      _Tag(text: t.gameTeamMafia, color: GameStyle.crimson)
                    else if (!player.isConnected)
                      _Tag(text: t.gameOffline, color: GameStyle.muted),
                  ],
                ),
              ),
              Positioned(
                left: 6,
                top: 4,
                child: Text(
                  '${player.seat + 1}',
                  style: const TextStyle(fontSize: 11, color: GameStyle.muted),
                ),
              ),
              if (votes > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Tooltip(
                    message: t.gameVotes(votes),
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: myVote
                          ? GameStyle.gold
                          : GameStyle.crimson,
                      child: Text(
                        '$votes',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
