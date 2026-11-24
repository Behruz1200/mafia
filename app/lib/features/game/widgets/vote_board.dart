import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../ui/game_style.dart';

/// Who voted for whom, open to the whole table: live while the vote runs
/// ([live] true, with who has not voted yet), then how it ended until the
/// next vote starts.
class VoteBoard extends StatelessWidget {
  const VoteBoard({
    super.key,
    required this.votes,
    required this.players,
    required this.me,
    this.live = false,
  });

  /// Voter -> target; null means they skipped.
  final Map<UserId, UserId?> votes;
  final List<Player> players;
  final UserId? me;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final byId = {for (final p in players) p.userId: p};
    String name(UserId u) =>
        u == me ? t.gameYou : (byId[u]?.displayName ?? '…');
    int seat(UserId u) => byId[u]?.seat ?? 999;

    final groups = <UserId, List<UserId>>{};
    final skipped = <UserId>[];
    for (final MapEntry(key: voter, value: target) in votes.entries) {
      if (target == null) {
        skipped.add(voter);
      } else {
        (groups[target] ??= []).add(voter);
      }
    }
    for (final g in groups.values) {
      g.sort((a, b) => seat(a).compareTo(seat(b)));
    }
    skipped.sort((a, b) => seat(a).compareTo(seat(b)));
    final targets = groups.keys.toList()
      ..sort((a, b) {
        final c = groups[b]!.length.compareTo(groups[a]!.length);
        return c != 0 ? c : seat(a).compareTo(seat(b));
      });
    final alive = [
      for (final p in players)
        if (p.isAlive) p.userId,
    ];
    final waiting = live
        ? [
            for (final u in alive)
              if (!votes.containsKey(u)) u,
          ]
        : const <UserId>[];
    final top = targets.isEmpty ? 0 : groups[targets.first]!.length;

    return GamePanel(
      key: const ValueKey('vote-board'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      borderColor: GameStyle.crimson.withValues(alpha: live ? 0.55 : 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 8,
            children: [
              const Icon(
                Icons.how_to_vote_rounded,
                size: 18,
                color: GameStyle.crimson,
              ),
              Expanded(
                child: Text(
                  (live ? t.gameVoteBoardLive : t.gameVoteBoardResult)
                      .toUpperCase(),
                  style: const TextStyle(
                    color: GameStyle.muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (live)
                Text(
                  t.gameVoteBoardCount(votes.length, alive.length),
                  style: const TextStyle(
                    color: GameStyle.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          if (votes.isEmpty)
            Text(
              t.gameVoteBoardEmpty,
              style: const TextStyle(color: GameStyle.muted),
            ),
          for (final target in targets)
            _Row(
              key: ValueKey('vote-row-$target'),
              lead: _Who(
                name: name(target),
                initial: byId[target]?.displayName ?? '',
                color: _tint(byId[target]),
              ),
              count: groups[target]!.length,
              hot: groups[target]!.length == top,
              voters: [for (final v in groups[target]!) name(v)],
            ),
          if (skipped.isNotEmpty)
            _Row(
              key: const ValueKey('vote-row-skip'),
              lead: _Label(text: t.gameVoteBoardSkipped),
              count: skipped.length,
              voters: [for (final v in skipped) name(v)],
            ),
          if (waiting.isNotEmpty)
            _Row(
              key: const ValueKey('vote-row-waiting'),
              lead: _Label(text: t.gameVoteBoardWaiting),
              voters: [for (final v in waiting) name(v)],
              faint: true,
            ),
        ],
      ),
    );
  }

  static Color _tint(Player? p) =>
      p == null ? Palette.surfaceHigh : playerColor(p.displayName);
}

/// One target (or Skipped / Not voted yet) and the names behind it.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.lead,
    required this.voters,
    this.count,
    this.hot = false,
    this.faint = false,
  });

  final Widget lead;
  final List<String> voters;
  final int? count;
  final bool hot;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Row(
          spacing: 8,
          children: [
            Expanded(child: lead),
            if (count != null)
              Container(
                constraints: const BoxConstraints(minWidth: 26),
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hot ? GameStyle.crimson : Palette.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final v in voters)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: faint
                      ? Colors.transparent
                      : Palette.surfaceHigh.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(10),
                  border: faint
                      ? Border.all(color: Palette.surfaceHigh, width: 1.2)
                      : null,
                ),
                child: Text(
                  v,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: faint ? GameStyle.muted : Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A target: their initial on their colour and their name.
class _Who extends StatelessWidget {
  const _Who({required this.name, required this.initial, required this.color});

  final String name;

  /// Their own name, for the initial (even when [name] is "You").
  final String initial;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: color,
          child: Text(
            initial.isEmpty ? '?' : initial.characters.first.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: GameStyle.muted,
      fontWeight: FontWeight.w700,
      fontSize: 14,
    ),
  );
}
