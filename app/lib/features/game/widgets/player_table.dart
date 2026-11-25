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
    this.notes = const {},
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
    void view(UserId id) =>
        showSeatCameras(context, seats: seats, start: id, me: me, face: face!);
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
              selectable: selectable.contains(p.userId),
              selected: selected == p.userId,
              face: face,
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
    this.selectable = false,
    this.selected = false,
    this.face,
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
  final bool selectable;
  final bool selected;
  final SeatFace? face;
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
              opacity: (dead && !highlighted) || note != null ? 0.55 : 1,
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
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, _, _) =>
          SeatCameraViewer(seats: seats, start: start, me: me, face: face),
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
  });

  final List<Player> seats;
  final UserId start;
  final UserId? me;
  final SeatFace face;

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
    final name = p.userId == widget.me ? t.gameYou : p.displayName;
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
