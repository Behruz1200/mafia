import '../json.dart';
import '../models/call.dart';
import '../models/chat.dart';
import '../models/game_action.dart';
import '../models/game_state.dart';
import '../models/match_result.dart';
import '../models/role.dart';
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
    'chat' => SendChat(j['roomId']! as String, j['text']! as String),
    'react' => SendReaction(j['roomId']! as String, j['emoji']! as String),
    'setRoles' => SetRoomRoles(
      j['roomId']! as String,
      (j['roleCounts'] as Json?)?.map(
        (k, v) => MapEntry(Role.values.byName(k), v! as int),
      ),
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

/// A chat message. The server decides who can read it (`ChatRules`) and
/// refuses it when the player may not write right now (`chat_closed`).
/// During their last word, the speaker's messages become that last word.
final class SendChat extends ClientMessage {
  const SendChat(this.roomId, this.text);
  final String roomId;
  final String text;
  @override
  Json toJson() => {'t': 'chat', 'roomId': roomId, 'text': text};
}

/// Pop an emoji (one of `ChatRules.reactions`) on the player's own seat.
/// Same rules as [SendChat]: refused with `chat_closed` when the player
/// may not write right now.
final class SendReaction extends ClientMessage {
  const SendReaction(this.roomId, this.emoji);
  final String roomId;
  final String emoji;
  @override
  Json toJson() => {'t': 'react', 'roomId': roomId, 'emoji': emoji};
}

/// The host picks the roles for the next match, in the waiting room.
/// [roleCounts] holds every role but Civilian (Civilians fill the other
/// seats); null goes back to the standard deal. The server checks the setup
/// is fair for the seats it could have (`RoleSetup.check`), then sends
/// everyone the room with the new `RoomSettings.roleCounts`. Refused with
/// `not_host`, `room_in_match`, `roles_locked` (quick-match rooms keep the
/// standard deal) or a `RoleSetupProblem.code`.
final class SetRoomRoles extends ClientMessage {
  const SetRoomRoles(this.roomId, this.roleCounts);
  final String roomId;
  final Map<Role, int>? roleCounts;
  @override
  Json toJson() => {
    't': 'setRoles',
    'roomId': roomId,
    'roleCounts': roleCounts?.map((k, v) => MapEntry(k.name, v)),
  };
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
    'chat' => ChatPosted(ChatMessage.fromJson(j['message']! as Json)),
    'chatHistory' => ChatHistory(
      j['roomId']! as String,
      decodeList(j['messages'], ChatMessage.fromJson),
    ),
    'reaction' => ReactionShown(ChatReaction.fromJson(j['reaction']! as Json)),
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

/// A new chat message this player may read.
final class ChatPosted extends ServerMessage {
  const ChatPosted(this.message);
  final ChatMessage message;
  @override
  Json toJson() => {'t': 'chat', 'message': message.toJson()};
}

/// Every recent message this player may read, oldest first. Sent on
/// `watchRoom`, at match start and when the player is eliminated (they can
/// now read the dead players' chat). Replaces what the app had.
final class ChatHistory extends ServerMessage {
  const ChatHistory(this.roomId, this.messages);
  final String roomId;
  final List<ChatMessage> messages;
  @override
  Json toJson() => {
    't': 'chatHistory',
    'roomId': roomId,
    'messages': [for (final m in messages) m.toJson()],
  };
}

/// Someone popped an emoji on their seat; sent only to who may see it.
final class ReactionShown extends ServerMessage {
  const ReactionShown(this.reaction);
  final ChatReaction reaction;
  @override
  Json toJson() => {'t': 'reaction', 'reaction': reaction.toJson()};
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
