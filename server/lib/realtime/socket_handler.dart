import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

import '../rooms/ports.dart';
import '../rooms/room_error.dart';
import 'socket_hub.dart';

/// What the socket asks of the rooms code. Each call may throw a
/// `RoomError`; its code goes back to that socket as a `SocketError`.
abstract interface class RealtimeRooms {
  Future<void> watch(ClientConnection c, RoomId roomId);
  void unwatch(ClientConnection c, RoomId roomId);
  Future<void> act(UserId userId, RoomId roomId, GameAction action);

  /// A chat message from [userId]; the rooms code decides who reads it.
  Future<void> chat(UserId userId, RoomId roomId, String text);

  /// An emoji popped on [userId]'s seat, seen by the same players as chat.
  Future<void> react(UserId userId, RoomId roomId, String emoji);

  /// The host picks the roles for the next match (null: standard deal).
  Future<void> setRoles(UserId userId, RoomId roomId, Map<Role, int>? counts);

  /// [userId] tapped Play again after a match and is back for the next one.
  Future<void> comeBack(UserId userId, RoomId roomId);

  /// The host makes [to] the host instead.
  Future<void> setHost(UserId userId, RoomId roomId, UserId to);
}

/// Close codes the app can act on.
abstract final class SocketClose {
  static const unauthorized = 4401;
  static const tooBig = 4413;
}

/// The realtime socket at `ApiRoutes.socket`. Connect with
/// `?token=<accessToken>`; then send `watchRoom` for each room to follow.
///
/// The server never trusts `actorId` from the app: actions are re-stamped
/// with the socket's signed-in user before the room sees them.
Handler socketHandler({
  required SocketHub hub,
  required TokenVerifier tokens,
  required RealtimeRooms rooms,
  Duration pingInterval = const Duration(seconds: 20),
  int maxFrameBytes = 16 * 1024,
}) => (Request req) {
  final token = req.url.queryParameters['token'] ?? _bearer(req);
  final userId = token == null ? null : tokens.verify(token);
  return webSocketHandler((channel, _) {
    if (userId == null) {
      channel.sink.add(jsonEncode(const SocketError('unauthorized').toJson()));
      channel.sink.close(SocketClose.unauthorized, 'unauthorized');
      return;
    }
    final conn = ClientConnection(userId, channel.sink.add);
    hub.add(conn);

    void fail(String code, [String? message]) =>
        conn.send(SocketError(code, message));

    channel.stream.listen(
      (frame) async {
        if (frame is! String) return fail('bad_message');
        if (frame.length > maxFrameBytes) {
          fail('bad_message', 'frame too big');
          return channel.sink.close(SocketClose.tooBig, 'frame too big');
        }
        final ClientMessage msg;
        try {
          msg = ClientMessage.fromJson(jsonDecode(frame) as Json);
        } on Object {
          return fail('bad_message');
        }
        try {
          switch (msg) {
            case Ping():
              conn.send(const Pong());
            case WatchRoom(:final roomId):
              await rooms.watch(conn, roomId);
            case UnwatchRoom(:final roomId):
              rooms.unwatch(conn, roomId);
            case SendAction(:final roomId, :final action):
              final stamped = stampActor(action, userId);
              if (stamped == null) return fail('invalid_action');
              await rooms.act(userId, roomId, stamped);
            case SendChat(:final roomId, :final text):
              await rooms.chat(userId, roomId, text);
            case SendReaction(:final roomId, :final emoji):
              await rooms.react(userId, roomId, emoji);
            case SetRoomRoles(:final roomId, :final roleCounts):
              await rooms.setRoles(userId, roomId, roleCounts);
            case ComeBack(:final roomId):
              await rooms.comeBack(userId, roomId);
            case SetHost(:final roomId, userId: final to):
              await rooms.setHost(userId, roomId, to);
          }
        } on RoomError catch (e) {
          fail(e.code, e.message);
        } on Object catch (e, st) {
          stderr.writeln('socket: ${msg.toJson()['t']} failed: $e\n$st');
          fail('server_error');
        }
      },
      onDone: () => hub.remove(conn),
      onError: (_) => hub.remove(conn),
      cancelOnError: true,
    );
  }, pingInterval: pingInterval)(req);
};

String? _bearer(Request req) {
  final h = req.headers['authorization'];
  return h != null && h.startsWith('Bearer ') ? h.substring(7) : null;
}

/// The same action, as done by [userId]. Null for actions only the server
/// may make (timeouts, players leaving, last words, which come in as chat).
GameAction? stampActor(GameAction a, UserId userId) => switch (a) {
  StartMatch() => StartMatch(actorId: userId),
  NightKill(:final targetId) => NightKill(actorId: userId, targetId: targetId),
  NightHeal(:final targetId) => NightHeal(actorId: userId, targetId: targetId),
  NightCheck(:final targetId) => NightCheck(
    actorId: userId,
    targetId: targetId,
  ),
  NightGuard(:final targetId) => NightGuard(
    actorId: userId,
    targetId: targetId,
  ),
  NightSleep(:final targetId) => NightSleep(
    actorId: userId,
    targetId: targetId,
  ),
  CastVote(:final targetId) => CastVote(actorId: userId, targetId: targetId),
  SkipPhase(:final skip) => SkipPhase(actorId: userId, skip: skip),
  PhaseTimeout() || PlayerLeft() || SayLastWord() => null,
};
