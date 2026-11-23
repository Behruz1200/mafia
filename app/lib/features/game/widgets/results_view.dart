import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../ui/game_style.dart';

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
  });

  final PublicGameState state;
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
            child: Icon(
              cancelled
                  ? Icons.block_rounded
                  : winner == Team.mafia
                  ? Icons.theater_comedy
                  : Icons.location_city_rounded,
              size: 68,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          cancelled
              ? t.gamePhaseEnded
              : winner == Team.mafia
              ? t.gameResultMafiaWins
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
        if (winnerNames.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            t.gameResultWinners.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GameStyle.muted,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
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
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: GameStyle.glow(GameStyle.crimson),
          ),
          child: FilledButton.icon(
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
}
