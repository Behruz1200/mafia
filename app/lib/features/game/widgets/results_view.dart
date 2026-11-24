import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../ui/game_style.dart';
import '../ui/game_text.dart';
import '../ui/noir_art.dart';
import '../story/story_view.dart';

/// After the match: who won, what it meant for my coins, and what next.
///
/// Coin amounts come from the server's [MatchResult]; the app never
/// computes a payout itself (the house cut and rounding are the server's).
class ResultsView extends StatelessWidget {
  const ResultsView({
    super.key,
    required this.state,
    required this.result,
    required this.me,
    required this.onPlayAgain,
    required this.onBackToLobby,
    this.room,
    this.startedWithoutMe = false,
  });

  final PublicGameState state;

  /// The room now: who is back in the waiting room, who is the host.
  final Room? room;

  /// The others started the next match while I was still here.
  final bool startedWithoutMe;
  final MatchResult? result;
  final UserId? me;
  final VoidCallback onPlayAgain;
  final VoidCallback onBackToLobby;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final winner = result?.winningTeam ?? state.winner;
    final cancelled = result != null ? result!.cancelled : winner == null;
    final iWon = result?.winners.contains(me) ?? false;
    final stake = result?.stake ?? 0;
    final color = winner == null
        ? GameStyle.muted
        : GameStyle.teamColor(winner);
    final winnerNames = [
      for (final p in state.players)
        if (result?.winners.contains(p.userId) ?? false) p.displayName,
    ];
    // Every card is face up once the match is over. Players are listed in
    // seat order, Mafia first within each group so the answer stands out.
    final roles = result?.roles ?? const <UserId, Role>{};
    final seated =
        [
          for (final p in state.players)
            if (roles.containsKey(p.userId)) p,
        ]..sort(
          (a, b) => _rank(roles[a.userId]!).compareTo(_rank(roles[b.userId]!)),
        );
    final winnersList = [
      for (final p in seated)
        if (result!.winners.contains(p.userId)) p,
    ];
    final losersList = [
      for (final p in seated)
        if (!result!.winners.contains(p.userId)) p,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 60),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: cancelled
                ? Icon(Icons.block_rounded, size: 68, color: color)
                // The winning side's character.
                : Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: RolePortrait(
                      role: switch (winner) {
                        Team.mafia => Role.mafia,
                        Team.maniac => Role.maniac,
                        _ => Role.detective,
                      },
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          cancelled
              ? t.gamePhaseEnded
              : winner == Team.mafia
              ? t.gameResultMafiaWins
              : winner == Team.maniac
              ? t.gameResultManiacWins
              : t.gameResultTownWins,
          textAlign: TextAlign.center,
          style: GameStyle.display(28, color: color),
        ),
        const SizedBox(height: 22),
        if (result != null)
          GamePanel(
            padding: const EdgeInsets.all(20),
            color: cancelled
                ? null
                : (iWon ? GameStyle.gold : GameStyle.crimson).withValues(
                    alpha: 0.14,
                  ),
            child: Row(
              spacing: 14,
              children: [
                if (!cancelled)
                  iWon
                      ? const CoinIcon(size: 44)
                      : const IconBlob(
                          icon: Icons.trending_down_rounded,
                          color: GameStyle.crimson,
                        ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      if (!cancelled)
                        Text(
                          iWon ? t.gameResultYouWon : t.gameResultYouLost,
                          style: GameStyle.display(
                            19,
                            color: iWon ? GameStyle.gold : Colors.white,
                          ),
                        ),
                      Text(
                        cancelled
                            ? t.gameResultCancelled
                            : stake == 0
                            ? t.gameResultFreeGame
                            : iWon
                            ? t.gameResultWonCoins
                            : t.gameResultLostCoins(t.coins(stake)),
                        style: const TextStyle(
                          color: GameStyle.muted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (result?.story != null && !cancelled) ...[
          const SizedBox(height: 16),
          MatchStoryButton(state: state, result: result!, me: me),
        ],
        if (roles.isNotEmpty) ...[
          for (final (title, group) in [
            (t.gameResultWinners, winnersList),
            (t.gameResultLosers, losersList),
          ])
            if (group.isNotEmpty) ...[
              const SizedBox(height: 22),
              _SectionTitle(title),
              const SizedBox(height: 10),
              GamePanel(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final p in group)
                      _RoleRow(
                        name: p.displayName,
                        role: roles[p.userId]!,
                        isMe: p.userId == me,
                        left: result!.forfeited.contains(p.userId),
                      ),
                  ],
                ),
              ),
            ],
        ] else if (winnerNames.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionTitle(t.gameResultWinners),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in winnerNames)
                Container(
                  padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
                  decoration: BoxDecoration(
                    color: GameStyle.card,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      PlayerAvatar(name: n, size: 28),
                      Text(
                        n,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 30),
        ?_status(t),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: GameStyle.glow(GameStyle.crimson),
          ),
          child: FilledButton.icon(
            key: const ValueKey('play-again'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            icon: const Icon(Icons.replay_rounded),
            label: Text(t.gamePlayAgain),
            onPressed: onPlayAgain,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          onPressed: onBackToLobby,
          child: Text(t.gameBackToLobby),
        ),
      ],
    );
  }

  /// What Play again leads to: who is already back, and for the host,
  /// that the next game waits on them.
  Widget? _status(AppLocalizations t) {
    final r = room;
    final String? text;
    final IconData icon;
    if (startedWithoutMe) {
      text = t.gameStartedWithoutYou;
      icon = Icons.play_circle_outline_rounded;
    } else if (r == null) {
      return null;
    } else {
      final back = r.readyIds.length;
      final lines = [
        if (back > 0) t.gameBackCount(back, r.memberIds.length),
        if (r.hostId == me) t.gameResultsHostHint,
      ];
      if (lines.isEmpty) return null;
      text = lines.join('\n');
      icon = r.hostId == me ? Icons.star_rounded : Icons.groups_rounded;
    }
    return Padding(
      key: const ValueKey('results-status'),
      padding: const EdgeInsets.only(bottom: 14),
      child: GamePanel(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          spacing: 10,
          children: [
            Icon(icon, color: GameStyle.gold, size: 22),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mafia team first (Don, then Mafia), then the Maniac, then the town's
/// roles, Civilians last.
int _rank(Role r) => switch (r) {
  Role.don => 0,
  Role.mafia => 1,
  Role.maniac => 2,
  Role.detective => 3,
  Role.doctor => 4,
  Role.bodyguard => 5,
  Role.hypnotist => 6,
  Role.immortal => 7,
  Role.civilian => 8,
};

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    textAlign: TextAlign.center,
    style: const TextStyle(
      color: GameStyle.muted,
      fontWeight: FontWeight.w800,
      fontSize: 11,
      letterSpacing: 1.2,
    ),
  );
}

/// One player with their card turned face up.
class _RoleRow extends StatelessWidget {
  const _RoleRow({
    required this.name,
    required this.role,
    required this.isMe,
    required this.left,
  });

  final String name;
  final Role role;
  final bool isMe;
  final bool left;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final color = GameStyle.teamColor(role.team);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        spacing: 12,
        children: [
          PlayerAvatar(name: name, size: 36),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  isMe ? '$name (${t.gameYou})' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (left)
                  Text(
                    t.gameResultLeft,
                    style: const TextStyle(
                      color: GameStyle.muted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.5)),
              boxShadow: role.team != Team.town
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                RoleBadge(role: role, size: 22),
                Text(
                  t.roleName(role),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
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
