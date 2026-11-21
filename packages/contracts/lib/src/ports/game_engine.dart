import '../models/game_action.dart';
import '../models/game_state.dart';
import '../models/ids.dart';
import '../models/match_result.dart';
import '../models/player.dart';
import '../models/room.dart';

/// The result of feeding one action to the engine.
sealed class ApplyResult {
  const ApplyResult();
}

final class Accepted extends ApplyResult {
  const Accepted(this.state, {this.matchResult});
  final GameState state;

  /// Set exactly once, on the action that ends the match.
  final MatchResult? matchResult;
}

final class Rejected extends ApplyResult {
  const Rejected(this.code);

  /// Stable code such as `not_your_turn`, `wrong_phase`, `target_dead`.
  final String code;
}

/// The rules of Mafia, implemented by `mafia_engine` (stream 1) and run by
/// the game server (stream 2). Pure and deterministic: no clock, no
/// network, no randomness except the given seed.
abstract interface class GameEngine {
  /// Deal roles and move to [GamePhase.roleReveal].
  GameState newMatch({
    required RoomId roomId,
    required MatchId matchId,
    required List<Player> players,
    required RoomSettings settings,
    required int seed,
    required DateTime now,
  });

  /// Apply one action. [now] is passed in so timers stay testable.
  ApplyResult apply(
    GameState state,
    GameAction action, {
    required DateTime now,
  });

  /// What [userId] is allowed to know.
  PrivatePlayerState privateView(GameState state, UserId userId);
}
