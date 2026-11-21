import '../json.dart';
import '../models/call.dart';
import '../models/game_action.dart';
import '../models/game_state.dart';
import '../models/match_result.dart';
import '../models/room.dart';
import '../models/wallet.dart';

/// Messages the app sends on the realtime socket (`ApiRoutes.socket`).
/// Every frame is one JSON object with a `t` (type) field.
sealed class ClientMessage {
  const ClientMessage();
  Json toJson();

  factory ClientMessage.fromJson(Json j) => switch (j['t']) {
    'watchRoom' => WatchRoom(j['roomId']! as String),
    'unwatchRoom' => UnwatchRoom(j['roomId']! as String),
    'action' => SendAction(
      j['roomId']! as String,
      GameAction.fromJson(j['action']! as Json),
    ),
    'ping' => const Ping(),
    final t => throw FormatException('Unknown ClientMessage: $t'),
  };
}

/// Start receiving a room's updates. Only room members are accepted.
final class WatchRoom extends ClientMessage {
  const WatchRoom(this.roomId);
  final String roomId;
  @override
  Json toJson() => {'t': 'watchRoom', 'roomId': roomId};
}

final class UnwatchRoom extends ClientMessage {
  const UnwatchRoom(this.roomId);
  final String roomId;
  @override
  Json toJson() => {'t': 'unwatchRoom', 'roomId': roomId};
}

/// A player action. The server ignores [GameAction.actorId] and uses the
/// socket's authenticated user.
final class SendAction extends ClientMessage {
  const SendAction(this.roomId, this.action);
  final String roomId;
  final GameAction action;
  @override
  Json toJson() => {'t': 'action', 'roomId': roomId, 'action': action.toJson()};
}

final class Ping extends ClientMessage {
  const Ping();
  @override
  Json toJson() => {'t': 'ping'};
}

/// Messages the server pushes on the realtime socket.
sealed class ServerMessage {
  const ServerMessage();
  Json toJson();

  factory ServerMessage.fromJson(Json j) => switch (j['t']) {
    'room' => RoomUpdated(Room.fromJson(j['room']! as Json)),
    'public' => PublicStateUpdated(
      PublicGameState.fromJson(j['state']! as Json),
    ),
    'private' => PrivateStateUpdated(
      j['roomId']! as String,
      PrivatePlayerState.fromJson(j['state']! as Json),
    ),
    'call' => CallGrantIssued(
      j['roomId']! as String,
      CallGrant.fromJson(j['grant']! as Json),
    ),
    'matchEnded' => MatchEnded(MatchResult.fromJson(j['result']! as Json)),
    'wallet' => WalletUpdated(WalletBalance.fromJson(j['wallet']! as Json)),
    'error' => SocketError(j['code']! as String, j['message'] as String?),
    'pong' => const Pong(),
    final t => throw FormatException('Unknown ServerMessage: $t'),
  };
}

final class RoomUpdated extends ServerMessage {
  const RoomUpdated(this.room);
  final Room room;
  @override
  Json toJson() => {'t': 'room', 'room': room.toJson()};
}

/// Sent to every member whenever public state changes.
final class PublicStateUpdated extends ServerMessage {
  const PublicStateUpdated(this.state);
  final PublicGameState state;
  @override
  Json toJson() => {'t': 'public', 'state': state.toJson()};
}

/// Sent only on that player's own socket.
final class PrivateStateUpdated extends ServerMessage {
  const PrivateStateUpdated(this.roomId, this.state);
  final String roomId;
  final PrivatePlayerState state;
  @override
  Json toJson() => {'t': 'private', 'roomId': roomId, 'state': state.toJson()};
}

/// A new call grant, e.g. when night starts and Mafia get the private call,
/// or a player dies and loses publish rights.
final class CallGrantIssued extends ServerMessage {
  const CallGrantIssued(this.roomId, this.grant);
  final String roomId;
  final CallGrant grant;
  @override
  Json toJson() => {'t': 'call', 'roomId': roomId, 'grant': grant.toJson()};
}

final class MatchEnded extends ServerMessage {
  const MatchEnded(this.result);
  final MatchResult result;
  @override
  Json toJson() => {'t': 'matchEnded', 'result': result.toJson()};
}

final class WalletUpdated extends ServerMessage {
  const WalletUpdated(this.wallet);
  final WalletBalance wallet;
  @override
  Json toJson() => {'t': 'wallet', 'wallet': wallet.toJson()};
}

final class SocketError extends ServerMessage {
  const SocketError(this.code, [this.message]);
  final String code;
  final String? message;
  @override
  Json toJson() => {'t': 'error', 'code': code, 'message': message};
}

final class Pong extends ServerMessage {
  const Pong();
  @override
  Json toJson() => {'t': 'pong'};
}
