import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../ui/game_style.dart';
import '../ui/game_text.dart';

/// Shows what fills a seat: a player's camera, given their id and the
/// picture to show when there is no video.
typedef SeatFace = Widget Function(UserId userId, Widget placeholder);

/// What fills the seat of a player who is out, or null for the usual
/// dimmed seat with a cross.
typedef OutFace = Widget? Function(UserId userId, Widget placeholder);

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
    this.votesSettled = false,
    this.selectable = const {},
    this.selected,
    this.onSelect,
    this.face,
    this.outFace,
    this.overlays = const {},
    this.highlight,
    this.notes = const {},
  });

  final List<Player> players;
  final UserId? me;
  final PrivatePlayerState? private;

  /// Open votes, voter -> target (null: skipped). Each voter's seat says
  /// who they voted for, and each target's seat how many votes it has.
  final Map<UserId, UserId?> votes;

  /// [votes] is how the last vote ended, not a vote still running: shown
  /// quieter.
  final bool votesSettled;
  final Set<UserId> selectable;
  final UserId? selected;
  final ValueChanged<UserId>? onSelect;
  final SeatFace? face;

  /// The seats of players who are out, e.g. their frozen last picture.
  final OutFace? outFace;

  /// Drawn over a seat, e.g. an emoji the player just popped.
  final Map<UserId, Widget> overlays;

  /// A seat to ring in gold, e.g. the player saying their last word.
  final UserId? highlight;

  /// A short dimmed label on a seat, e.g. "Not back" in the
  /// waiting room after a match.
  final Map<UserId, String> notes;

  @override
  Widget build(BuildContext context) {
    final tally = <UserId, int>{};
    for (final target in votes.values) {
      if (target != null) tally[target] = (tally[target] ?? 0) + 1;
    }
    final seats = [...players]..sort((a, b) => a.seat.compareTo(b.seat));
    // With nobody to pick, a tap opens the camera full screen; while
    // picking, a tap picks and holding still opens it.
    final picking = selectable.isNotEmpty && onSelect != null;
    final byId = {for (final p in seats) p.userId: p};
    final voters = <UserId, List<int>>{};
    for (final p in seats) {
      final target = votes[p.userId];
      if (target != null) (voters[target] ??= []).add(p.seat + 1);
    }
    void view(UserId id) => showSeatCameras(
      context,
      seats: seats,
      start: id,
      me: me,
      face: face!,
      votes: votes,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final columns = columnsFor(c.maxWidth, seats.length);
        return GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: seats.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.8,
          ),
          itemBuilder: (context, i) {
            final p = seats[i];
            return SeatTile(
              key: ValueKey('seat-${p.userId}'),
              player: p,
              isMe: p.userId == me,
              isTeammate: private?.teammates.contains(p.userId) ?? false,
              checked: private?.checks[p.userId],
              detective: private?.detectiveChecks[p.userId],
              votes: tally[p.userId] ?? 0,
              myVote: me != null && votes[me] == p.userId,
              vote: !votes.containsKey(p.userId)
                  ? null
                  : SeatVote(
                      target: byId[votes[p.userId]],
                      targetIsMe: votes[p.userId] == me,
                    ),
              votesSettled: votesSettled,
              voterSeats: voters[p.userId] ?? const [],
              selectable: selectable.contains(p.userId),
              selected: selected == p.userId,
              face: face,
              outFace: outFace,
              overlay: overlays[p.userId],
              highlighted: highlight == p.userId,
              note: notes[p.userId],
              onTap: picking
                  ? (selectable.contains(p.userId)
                        ? () => onSelect!(p.userId)
                        : null)
                  : face != null
                  ? () => view(p.userId)
                  : null,
              onLongPress: face != null ? () => view(p.userId) : null,
            );
          },
        );
      },
    );
  }

  /// Cameras across the table. A phone fits 2 across up to 4 players and
  /// 3 across after that, so each camera is as big as the screen allows
  /// (4 across left them about 84 points wide); wide screens keep 6.
  static int columnsFor(double width, int players) {
    if (width > 560) return 6;
    return players <= 4 ? 2 : 3;
  }
}

class SeatTile extends StatelessWidget {
  const SeatTile({
    super.key,
    required this.player,
    this.isMe = false,
    this.isTeammate = false,
    this.checked,
    this.detective,
    this.votes = 0,
    this.myVote = false,
    this.vote,
    this.votesSettled = false,
    this.voterSeats = const [],
    this.selectable = false,
    this.selected = false,
    this.face,
    this.outFace,
    this.onTap,
    this.onLongPress,
    this.overlay,
    this.highlighted = false,
    this.note,
  });

  final Player player;
  final bool isMe;
  final bool isTeammate;
  final Team? checked;

  /// The Don's check of this player: true if they are the Detective.
  final bool? detective;
  final int votes;
  final bool myVote;

  /// Who this player voted for, if they voted.
  final SeatVote? vote;

  /// The votes are how the last vote ended: shown quieter.
  final bool votesSettled;

  /// Seat numbers of who voted for this player, under the vote count.
  final List<int> voterSeats;
  final bool selectable;
  final bool selected;
  final SeatFace? face;
  final OutFace? outFace;
  final VoidCallback? onTap;

  /// Opens the camera full screen.
  final VoidCallback? onLongPress;
  final Widget? overlay;

  /// Gold ring and live camera even when out (their last word).
  final bool highlighted;

  /// A short label, and the seat dimmed (e.g. not back from the results).
  final String? note;

  static const _radius = 18.0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final dead = !player.isAlive;
    final name = isMe ? t.gameYou : player.displayName;

    final placeholder = SeatPlaceholder(player: player);

    final out = dead && !highlighted
        ? outFace?.call(player.userId, placeholder)
        : null;

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
        : detective != null
        ? _Tag(
            text: detective! ? t.roleName(Role.detective) : t.gameNotDetective,
            color: detective! ? GameStyle.town : Palette.surfaceHigh,
          )
        : isTeammate
        ? _Tag(text: t.gameTeamMafia, color: Palette.accent)
        : note != null
        ? _Tag(text: note!, color: Palette.surfaceHigh)
        : !player.isConnected
        ? _Tag(text: t.gameOffline, color: Palette.surfaceHigh)
        : null;

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: player.displayName,
      onLongPressHint: onLongPress != null ? t.gameSeatFullScreen : null,
      child: AnimatedScale(
        scale: selected ? 1.04 : 1,
        duration: const Duration(milliseconds: 150),
        child: Material(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(_radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Opacity(
              opacity: note != null
                  ? 0.55
                  : out != null
                  ? 0.9
                  : dead && !highlighted
                  ? 0.55
                  : 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (out != null)
                    out
                  else if (face != null && (!dead || highlighted))
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
                  if (dead && !highlighted && out == null)
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
                      child: Column(
                        spacing: 3,
                        children: [
                          Tooltip(
                            message: t.gameVotes(votes),
                            child: Container(
                              key: ValueKey('vote-count-${player.userId}'),
                              constraints: const BoxConstraints(minWidth: 24),
                              height: 24,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: votesSettled
                                    ? Palette.surfaceHigh
                                    : myVote
                                    ? Palette.gold
                                    : Palette.accent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$votes',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: myVote && !votesSettled
                                      ? Palette.background
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ),
                          for (final n in voterSeats.take(
                            voterSeats.length > 4 ? 3 : 4,
                          ))
                            _VoterDot(text: '$n', settled: votesSettled),
                          if (voterSeats.length > 4)
                            _VoterDot(
                              text: '+${voterSeats.length - 3}',
                              settled: votesSettled,
                            ),
                        ],
                      ),
                    ),
                  Positioned(
                    left: 5,
                    right: 5,
                    bottom: 7,
                    child: Column(
                      spacing: 4,
                      children: [
                        if (vote != null)
                          _VotePill(
                            key: ValueKey('vote-pill-${player.userId}'),
                            text: vote!.target == null
                                ? t.gameVoteBoardSkipped
                                : '${vote!.target!.seat + 1} · '
                                      '${vote!.targetIsMe ? t.gameYou : vote!.target!.displayName}',
                            skipped: vote!.target == null,
                            mine: isMe,
                            settled: votesSettled,
                          ),
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

/// What a seat shows without video: the player's colour and initial,
/// sized to the seat.
class SeatPlaceholder extends StatelessWidget {
  const SeatPlaceholder({super.key, required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final dead = !player.isAlive;
    final tint = playerColor(player.displayName);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dead
              ? const [Palette.surfaceHigh, Palette.surface]
              : [tint, Color.lerp(tint, Palette.background, 0.55)!],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) => Align(
          alignment: const Alignment(0, -0.25),
          child: Text(
            player.displayName.isEmpty
                ? '?'
                : player.displayName.characters.first.toUpperCase(),
            style: GameStyle.display(
              c.maxWidth.isFinite
                  ? (c.maxWidth * 0.3).clamp(24, 96).toDouble()
                  : 30,
              color: Colors.white.withValues(alpha: dead ? 0.25 : 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens [start]'s camera full screen. Swipe, or tap a seat number at
/// the bottom, to see someone else.
Future<void> showSeatCameras(
  BuildContext context, {
  required List<Player> seats,
  required UserId start,
  required UserId? me,
  required SeatFace face,
  Map<UserId, UserId?> votes = const {},
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, _, _) => SeatCameraViewer(
        seats: seats,
        start: start,
        me: me,
        face: face,
        votes: votes,
      ),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// One player's camera filling the screen, with every seat along the
/// bottom to switch between them.
class SeatCameraViewer extends StatefulWidget {
  const SeatCameraViewer({
    super.key,
    required this.seats,
    required this.start,
    required this.me,
    required this.face,
    this.votes = const {},
  });

  final List<Player> seats;
  final UserId start;
  final UserId? me;
  final SeatFace face;

  /// Open votes (voter -> target), to say who this player voted for and
  /// who voted for them.
  final Map<UserId, UserId?> votes;

  @override
  State<SeatCameraViewer> createState() => _SeatCameraViewerState();
}

class _SeatCameraViewerState extends State<SeatCameraViewer> {
  late int _index = widget.seats
      .indexWhere((p) => p.userId == widget.start)
      .clamp(0, widget.seats.length - 1);
  late final _pages = PageController(initialPage: _index);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int i) {
    setState(() => _index = i);
    _pages.animateToPage(
      i,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = widget.seats[_index];
    String nameOf(Player q) =>
        q.userId == widget.me ? t.gameYou : q.displayName;
    final name = nameOf(p);
    final byId = {for (final q in widget.seats) q.userId: q};
    final voted = widget.votes.containsKey(p.userId);
    final target = byId[widget.votes[p.userId]];
    final from = [
      for (final q in widget.seats)
        if (widget.votes[q.userId] == p.userId) q,
    ];
    final voteLines = [
      if (voted)
        target == null
            ? t.gameVoteBoardSkipped
            : t.gameVotedFor('${target.seat + 1} · ${nameOf(target)}'),
      if (from.isNotEmpty)
        t.gameVotesFrom(
          [for (final q in from) '${q.seat + 1} · ${nameOf(q)}'].join(', '),
        ),
    ];
    return Material(
      key: const ValueKey('seat-camera-viewer'),
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.seats.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final seat = widget.seats[i];
              final placeholder = SeatPlaceholder(player: seat);
              return seat.isAlive
                  ? widget.face(seat.userId, placeholder)
                  : placeholder;
            },
          ),
          // Darkens the bottom so the name and seats read over any video.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.6, 1],
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton.filled(
                    key: const ValueKey('close-seat-camera'),
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                const Spacer(),
                Text(
                  '${p.seat + 1} · $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GameStyle.display(26),
                ),
                for (final line in voteLines)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      spacing: 6,
                      children: [
                        const Icon(
                          Icons.how_to_vote_rounded,
                          size: 16,
                          color: GameStyle.crimson,
                        ),
                        Expanded(
                          child: Text(
                            line,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 60,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.seats.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final seat = widget.seats[i];
                      final on = i == _index;
                      return GestureDetector(
                        key: ValueKey('seat-camera-${seat.userId}'),
                        onTap: () => _go(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 48,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: on ? Palette.gold : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Opacity(
                            opacity: seat.isAlive ? 1 : 0.45,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                SeatPlaceholder(player: seat),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: ColoredBox(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    child: Text(
                                      '${seat.seat + 1}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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

/// A voter's seat number under a target's vote count.
class _VoterDot extends StatelessWidget {
  const _VoterDot({required this.text, required this.settled});

  final String text;
  final bool settled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: settled
              ? Colors.white.withValues(alpha: 0.25)
              : GameStyle.crimson.withValues(alpha: 0.8),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Who a seat's player voted for: the target, or none for a skip.
class SeatVote {
  const SeatVote({required this.target, this.targetIsMe = false});

  final Player? target;
  final bool targetIsMe;
}

/// "→ 4 · Jasur" on the voter's own seat.
class _VotePill extends StatelessWidget {
  const _VotePill({
    super.key,
    required this.text,
    required this.skipped,
    required this.mine,
    required this.settled,
  });

  final String text;
  final bool skipped;
  final bool mine;
  final bool settled;

  @override
  Widget build(BuildContext context) {
    final color = settled || skipped
        ? Colors.black.withValues(alpha: 0.55)
        : mine
        ? Palette.gold
        : GameStyle.crimson;
    final ink = !settled && !skipped && mine
        ? Palette.background
        : Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 2, 8, 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
        border: settled
            ? Border.all(color: Colors.white.withValues(alpha: 0.25))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          Icon(
            skipped ? Icons.block_rounded : Icons.arrow_forward_rounded,
            size: 12,
            color: ink,
          ),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
          ),
        ],
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
