import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../ui/game_style.dart';
import '../ui/game_text.dart';

/// Shows what fills a seat: a player's camera, given their id and the
/// picture to show when there is no video.
typedef SeatFace = Widget Function(UserId userId, Widget placeholder);

/// Everyone at the table, in seat order. Shows who is alive, open vote
/// counts, and what only I know (my Mafia teammates, my check results).
/// When [selectable] is not empty, those seats can be tapped to pick a
/// target. With [face], each seat shows that player's camera.
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
    this.face,
    this.overlays = const {},
    this.highlight,
  });

  final List<Player> players;
  final UserId? me;
  final PrivatePlayerState? private;
  final Map<UserId, UserId?> votes;
  final Set<UserId> selectable;
  final UserId? selected;
  final ValueChanged<UserId>? onSelect;
  final SeatFace? face;

  /// Drawn over a seat, e.g. an emoji the player just popped.
  final Map<UserId, Widget> overlays;

  /// A seat to ring in gold, e.g. the player saying their last word.
  final UserId? highlight;

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
            childAspectRatio: 0.76,
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
              face: face,
              overlay: overlays[p.userId],
              highlighted: highlight == p.userId,
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
    this.face,
    this.onTap,
    this.overlay,
    this.highlighted = false,
  });

  final Player player;
  final bool isMe;
  final bool isTeammate;
  final Team? checked;
  final int votes;
  final bool myVote;
  final bool selectable;
  final bool selected;
  final SeatFace? face;
  final VoidCallback? onTap;
  final Widget? overlay;

  /// Gold ring and live camera even when out (their last word).
  final bool highlighted;

  static const _radius = 18.0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final dead = !player.isAlive;
    final name = isMe ? t.gameYou : player.displayName;
    final tint = playerColor(player.displayName);

    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dead
              ? const [Palette.surfaceHigh, Palette.surface]
              : [tint, Color.lerp(tint, Palette.background, 0.55)!],
        ),
      ),
      child: Align(
        alignment: const Alignment(0, -0.25),
        child: Text(
          player.displayName.isEmpty
              ? '?'
              : player.displayName.characters.first.toUpperCase(),
          style: GameStyle.display(
            30,
            color: Colors.white.withValues(alpha: dead ? 0.25 : 0.6),
          ),
        ),
      ),
    );

    final (ringColor, ringWidth) = highlighted
        ? (Palette.gold, 3.0)
        : selected
        ? (Colors.white, 3.0)
        : selectable
        ? (Colors.white.withValues(alpha: 0.45), 1.5)
        : isTeammate
        ? (Palette.accent, 2.0)
        : isMe
        ? (Palette.gold, 2.0)
        : (Colors.transparent, 0.0);

    final tag = checked != null
        ? _Tag(text: t.teamName(checked!), color: GameStyle.teamColor(checked!))
        : isTeammate
        ? _Tag(text: t.gameTeamMafia, color: Palette.accent)
        : !player.isConnected
        ? _Tag(text: t.gameOffline, color: Palette.surfaceHigh)
        : null;

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: player.displayName,
      child: AnimatedScale(
        scale: selected ? 1.04 : 1,
        duration: const Duration(milliseconds: 150),
        child: Material(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(_radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Opacity(
              opacity: dead && !highlighted ? 0.55 : 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (face != null && (!dead || highlighted))
                    face!(player.userId, placeholder)
                  else
                    placeholder,
                  // Darkens the bottom so the name reads over any video.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.45, 1],
                        colors: [Colors.transparent, Color(0xB3000000)],
                      ),
                    ),
                  ),
                  if (dead && !highlighted)
                    const Center(
                      child: Icon(
                        Icons.close_rounded,
                        size: 44,
                        color: Palette.accent,
                      ),
                    ),
                  Positioned(
                    left: 7,
                    top: 5,
                    child: Row(
                      spacing: 2,
                      children: [
                        Text(
                          '${player.seat + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        if (player.isHost)
                          Tooltip(
                            message: t.gameHost,
                            child: const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: Palette.gold,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (votes > 0)
                    Positioned(
                      right: 5,
                      top: 5,
                      child: Tooltip(
                        message: t.gameVotes(votes),
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 24),
                          height: 24,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: myVote ? Palette.gold : Palette.accent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$votes',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: myVote ? Palette.background : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 5,
                    right: 5,
                    bottom: 7,
                    child: Column(
                      spacing: 4,
                      children: [
                        ?tag,
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isMe
                                ? FontWeight.w800
                                : FontWeight.w700,
                            decoration: dead
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ?overlay,
                  // The ring sits on top so video never covers it.
                  if (ringWidth > 0)
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(_radius),
                          border: Border.all(
                            color: ringColor,
                            width: ringWidth,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w800,
          color: color.computeLuminance() > 0.5
              ? Palette.background
              : Colors.white,
        ),
      ),
    );
  }
}
