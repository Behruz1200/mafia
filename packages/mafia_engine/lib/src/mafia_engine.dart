import 'package:contracts/contracts.dart';

/// Stream 1 fills this in: dealing roles, night/day/vote phases, win checks.
///
/// Keep it pure: everything it needs comes in through the arguments, so the
/// server and tests can replay any match from its seed and action list.
class MafiaEngine implements GameEngine {
  const MafiaEngine();

  @override
  GameState newMatch({
    required RoomId roomId,
    required MatchId matchId,
    required List<Player> players,
    required RoomSettings settings,
    required int seed,
    required DateTime now,
  }) => throw UnimplementedError('Stream 1: deal roles');

  @override
  ApplyResult apply(
    GameState state,
    GameAction action, {
    required DateTime now,
  }) => throw UnimplementedError('Stream 1: apply actions');

  @override
  PrivatePlayerState privateView(GameState state, UserId userId) =>
      throw UnimplementedError('Stream 1: private view');
}
