import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

/// Stream 2 (rooms). The realtime socket at `ApiRoutes.socket`.
///
/// For now it only answers pings, so the app and load tests can connect.
/// Stream 2 adds token checks, room subscriptions and state fan-out.
Handler socketHandler() => webSocketHandler((channel, _) {
  channel.stream.listen((frame) {
    final ServerMessage reply;
    try {
      final msg = ClientMessage.fromJson(jsonDecode(frame as String) as Json);
      reply = msg is Ping ? const Pong() : const SocketError('not_implemented');
    } on Object {
      channel.sink.add(jsonEncode(const SocketError('bad_message').toJson()));
      return;
    }
    channel.sink.add(jsonEncode(reply.toJson()));
  });
});
