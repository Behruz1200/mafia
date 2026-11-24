import '../json.dart';
import 'ids.dart';
import 'phase.dart';

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
      'skipPhase' => SkipPhase(
        actorId: actor,
        skip: j['skip'] as bool? ?? true,
      ),
      'lastWord' => SayLastWord(actorId: actor, text: j['text']! as String),
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

/// A living player agrees to end the current timer early (the day's
/// discussion, or the role reveal). The phase ends once
/// [SkipPhase.needed] of the living players agree (two thirds), so one or
/// two slow players can't hold everyone up, and nobody can skip alone.
/// During
/// [GamePhase.lastWord] only the speaker may send it, and it ends their
/// last word at once ("I'm done").
/// [skip] false takes the player's agreement back.
final class SkipPhase extends GameAction {
  const SkipPhase({required super.actorId, this.skip = true});
  final bool skip;

  /// Share of the living players who must agree to end the timer early.
  /// Change it here: the engine and the app both read it.
  static const share = 2 / 3;

  /// How many of [alive] living players must agree, rounded up, at least 1.
  static int needed(int alive) =>
      alive <= 0 ? 0 : (alive * share - 1e-9).ceil().clamp(1, alive);
  @override
  String get type => 'skipPhase';
  @override
  Json _fields() => {'skip': skip};
}

/// A typed line of the eliminated player's last word, during
/// [GamePhase.lastWord]. The app does not send this itself: the server
/// makes it from the speaker's chat message, so the last word is kept in
/// the match's record and log. [text] is cleaned by `ChatRules.clean`.
final class SayLastWord extends GameAction {
  const SayLastWord({required super.actorId, required this.text});
  final String text;
  @override
  String get type => 'lastWord';
  @override
  Json _fields() => {'text': text};
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
