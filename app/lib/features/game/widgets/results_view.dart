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
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        Icon(
          cancelled
              ? Icons.block
              : winner == Team.mafia
              ? Icons.theater_comedy
              : Icons.location_city,
          size: 96,
          color: color,
        ),
        const SizedBox(height: 16),
        Text(
          cancelled
              ? t.gamePhaseEnded
              : winner == Team.mafia
              ? t.gameResultMafiaWins
              : t.gameResultTownWins,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800, color: color),
        ),
        const SizedBox(height: 24),
        if (result != null)
          GamePanel(
            borderColor: cancelled
                ? null
                : (iWon ? GameStyle.gold : GameStyle.crimson).withValues(
                    alpha: 0.5,
                  ),
            child: Column(
              spacing: 8,
              children: [
                if (!cancelled)
                  Text(
                    iWon ? t.gameResultYouWon : t.gameResultYouLost,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: iWon ? GameStyle.gold : null,
                    ),
                  ),
                if (cancelled)
                  Text(t.gameResultCancelled, textAlign: TextAlign.center)
                else if (stake == 0)
                  Text(t.gameResultFreeGame, textAlign: TextAlign.center)
                else if (iWon)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 8,
                    children: [
                      const Icon(Icons.toll, color: GameStyle.gold),
                      Flexible(
                        child: Text(
                          t.gameResultWonCoins,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    t.gameResultLostCoins(t.coins(stake)),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        if (winnerNames.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            t.gameResultWinners,
            textAlign: TextAlign.center,
            style: const TextStyle(color: GameStyle.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in winnerNames)
                Chip(
                  avatar: PlayerAvatar(name: n, size: 24),
                  label: Text(n),
                ),
            ],
          ),
        ],
        const SizedBox(height: 32),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: GameStyle.crimson,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
          ),
          icon: const Icon(Icons.replay),
          label: Text(t.gamePlayAgain),
          onPressed: onPlayAgain,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: onBackToLobby,
          child: Text(t.gameBackToLobby),
        ),
      ],
    );
  }
}
