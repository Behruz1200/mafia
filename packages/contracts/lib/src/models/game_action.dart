import '../json.dart';
import 'ids.dart';

/// Something a player (or the server clock) does in a match.
///
/// The app sends player actions to the server (`ClientMessage.action`);
/// the server checks who sent it, sets [actorId] from the auth token and
/// feeds it to the engine. The app never applies actions itself.
sealed class GameAction {
  const GameAction({required this.actorId});

  /// Who did it. [systemActor] for actions the server makes on its own.
  final UserId actorId;

  static const systemActor = '_system';

  String get type;

  Json toJson() => {'type': type, 'actorId': actorId, ..._fields()};
  Json _fields() => const {};

  factory GameAction.fromJson(Json j) {
    final actor = j['actorId']! as String;
    final target = j['targetId'] as String?;
    return switch (j['type']) {
      'startMatch' => StartMatch(actorId: actor),
      'nightKill' => NightKill(actorId: actor, targetId: target!),
      'nightHeal' => NightHeal(actorId: actor, targetId: target!),
      'nightCheck' => NightCheck(actorId: actor, targetId: target!),
      'castVote' => CastVote(actorId: actor, targetId: target),
      'phaseTimeout' => const PhaseTimeout(),
      'playerLeft' => PlayerLeft(userId: j['userId']! as String),
      final t => throw FormatException('Unknown GameAction type: $t'),
    };
  }
}

/// Host starts the match from the lobby.
final class StartMatch extends GameAction {
  const StartMatch({required super.actorId});
  @override
  String get type => 'startMatch';
}

/// Mafia team's pick for the night (the Don's pick wins on a split).
final class NightKill extends GameAction {
  const NightKill({required super.actorId, required this.targetId});
  final UserId targetId;
  @override
  String get type => 'nightKill';
  @override
  Json _fields() => {'targetId': targetId};
}

/// Doctor protects one player for the night.
final class NightHeal extends GameAction {
  const NightHeal({required super.actorId, required this.targetId});
  final UserId targetId;
  @override
  String get type => 'nightHeal';
  @override
  Json _fields() => {'targetId': targetId};
}

/// Detective (or Don) checks one player's team.
final class NightCheck extends GameAction {
  const NightCheck({required super.actorId, required this.targetId});
  final UserId targetId;
  @override
  String get type => 'nightCheck';
  @override
  Json _fields() => {'targetId': targetId};
}

/// A vote during the voting phase. `targetId == null` means "skip".
final class CastVote extends GameAction {
  const CastVote({required super.actorId, required this.targetId});
  final UserId? targetId;
  @override
  String get type => 'castVote';
  @override
  Json _fields() => {'targetId': targetId};
}

/// Sent by the server when the current phase's timer runs out.
final class PhaseTimeout extends GameAction {
  const PhaseTimeout() : super(actorId: GameAction.systemActor);
  @override
  String get type => 'phaseTimeout';
}

/// Sent by the server when a player leaves or their reconnect window ends.
final class PlayerLeft extends GameAction {
  const PlayerLeft({required this.userId})
    : super(actorId: GameAction.systemActor);
  final UserId userId;
  @override
  String get type => 'playerLeft';
  @override
  Json _fields() => {'userId': userId};
}
