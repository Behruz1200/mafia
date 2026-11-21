import 'package:contracts/contracts.dart';

/// What one player may do in one LiveKit room right now.
class CallAccess {
  const CallAccess({
    required this.canJoin,
    required this.canPublish,
    required this.canSubscribe,
  });

  static const denied = CallAccess(
    canJoin: false,
    canPublish: false,
    canSubscribe: false,
  );

  final bool canJoin;

  /// May turn on camera and mic.
  final bool canPublish;

  /// May see and hear the others.
  final bool canSubscribe;

  @override
  bool operator ==(Object other) =>
      other is CallAccess &&
      other.canJoin == canJoin &&
      other.canPublish == canPublish &&
      other.canSubscribe == canSubscribe;

  @override
  int get hashCode => Object.hash(canJoin, canPublish, canSubscribe);

  @override
  String toString() =>
      'CallAccess(join: $canJoin, publish: $canPublish, '
      'subscribe: $canSubscribe)';
}

/// The rules for who may talk, and where. The server is the only place
/// these are decided; the app just follows `CallGrant.canPublish`.
///
/// Table call (everyone in the room):
/// - Before a match, during role reveal and after it ends: everyone talks.
/// - Night: nobody talks at the table, not even the Mafia. Everyone stays
///   connected, so the town cannot tell who slipped away.
/// - Day and voting: alive players talk, dead players only watch.
///
/// Mafia call (private, at night only):
/// - Only alive Mafia and Don, and only while it is night.
abstract final class CallPolicy {
  static CallAccess access({
    required CallChannel channel,
    required UserId userId,
    required PublicGameState? game,
    required Role? role,
  }) => switch (channel) {
    CallChannel.table => _table(userId, game),
    CallChannel.mafia => _mafia(userId, game, role),
  };

  static CallAccess _table(UserId userId, PublicGameState? game) {
    const talk = CallAccess(
      canJoin: true,
      canPublish: true,
      canSubscribe: true,
    );
    const watch = CallAccess(
      canJoin: true,
      canPublish: false,
      canSubscribe: true,
    );
    if (game == null) return talk; // Room open, no match yet.
    return switch (game.phase) {
      GamePhase.lobby || GamePhase.roleReveal || GamePhase.ended => talk,
      GamePhase.night => watch,
      GamePhase.day ||
      GamePhase.voting => _isAlive(game, userId) ? talk : watch,
    };
  }

  static CallAccess _mafia(UserId userId, PublicGameState? game, Role? role) {
    if (game == null ||
        role == null ||
        role.team != Team.mafia ||
        game.phase != GamePhase.night ||
        !_isAlive(game, userId)) {
      return CallAccess.denied;
    }
    return const CallAccess(
      canJoin: true,
      canPublish: true,
      canSubscribe: true,
    );
  }

  /// The channels [userId] should be connected to right now.
  static List<CallChannel> channelsFor({
    required UserId userId,
    required PublicGameState? game,
    required Role? role,
  }) => [
    for (final c in CallChannel.values)
      if (access(channel: c, userId: userId, game: game, role: role).canJoin) c,
  ];

  static bool _isAlive(PublicGameState game, UserId userId) {
    for (final p in game.players) {
      if (p.userId == userId) return p.isAlive;
    }
    return false;
  }
}
