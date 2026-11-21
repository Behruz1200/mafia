import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:server/rooms/ports.dart';
import 'package:server/rooms/rooms_module.dart';
import 'package:server/rooms/room_service.dart';
import 'package:server/realtime/socket_hub.dart';
import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support.dart';

/// The whole server on a real port, with dev tokens (`dev:<userId>`).
void main() {
  late HttpServer server;
  late RoomsModule rooms;
  late String base;
  final client = HttpClient();

  setUp(() async {
    final hub = SocketHub();
    rooms = RoomsModule(
      hub: hub,
      tokens: const DevTokenVerifier(),
      service: RoomService(
        engine: const ScriptEngine(),
        wallet: const FreeMatchesOnlyWallet(),
        hub: hub,
        log: (_) {},
      ),
    );
    server = await io.serve(buildApp(rooms: rooms), 'localhost', 0);
    base = 'localhost:${server.port}';
  });

  tearDown(() async {
    await rooms.service.dispose();
    await server.close(force: true);
  });

  Future<(int, Json)> call(
    String method,
    String path, {
    String? user,
    Object? body,
  }) async {
    final req = await client.openUrl(method, Uri.parse('http://$base$path'));
    if (user != null) req.headers.set('authorization', 'Bearer dev:$user');
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, jsonDecode(text) as Json);
  }

  test('room routes need a signed-in user', () async {
    final (status, body) = await call('POST', ApiRoutes.quickMatch);
    expect(status, 401);
    expect(ApiError.fromJson(body).code, 'unauthorized');
  });

  test('create, join, get and leave over HTTP', () async {
    final settings = fastSettings.toJson();
    final (s1, created) = await call(
      'POST',
      ApiRoutes.rooms,
      user: 'alice',
      body: const CreateRoomRequest(settings: fastSettings).toJson(),
    );
    expect(s1, 200, reason: '$created');
    final room = Room.fromJson(created);
    expect(room.settings.toJson(), settings);

    final (s2, joined) = await call(
      'POST',
      ApiRoutes.joinRoom,
      user: 'bob',
      body: JoinRoomRequest(inviteCode: room.inviteCode).toJson(),
    );
    expect(s2, 200);
    expect(Room.fromJson(joined).memberIds, ['alice', 'bob']);

    final (s3, _) = await call('GET', ApiRoutes.room(room.id), user: 'carol');
    expect(s3, 404, reason: 'outsiders cannot look rooms up');

    final (s4, got) = await call('GET', ApiRoutes.room(room.id), user: 'bob');
    expect(s4, 200);
    expect(Room.fromJson(got).id, room.id);

    final (s5, _) = await call(
      'POST',
      ApiRoutes.leaveRoom(room.id),
      user: 'bob',
    );
    expect(s5, 200);
    expect(rooms.service.room(room.id)!.memberIds, ['alice']);

    final (s6, bad) = await call(
      'POST',
      ApiRoutes.joinRoom,
      user: 'bob',
      body: {'nope': 1},
    );
    expect(s6, 400);
    expect(bad['error'], 'bad_request');
  });

  test('the socket refuses a bad token', () async {
    final ws = IOWebSocketChannel.connect(
      Uri.parse('ws://$base${ApiRoutes.socket}?token=forged'),
    );
    final frames = await ws.stream.toList();
    expect(
      ServerMessage.fromJson(jsonDecode(frames.first as String) as Json),
      isA<SocketError>().having((e) => e.code, 'code', 'unauthorized'),
    );
    expect(ws.closeCode, 4401);
  });

  test('a match runs over the socket', () async {
    final users = ['p0', 'p1', 'p2', 'p3'];
    final (_, created) = await call(
      'POST',
      ApiRoutes.rooms,
      user: 'p0',
      body: const CreateRoomRequest(settings: fastSettings).toJson(),
    );
    final room = Room.fromJson(created);
    for (final u in users.skip(1)) {
      await call(
        'POST',
        ApiRoutes.joinRoom,
        user: u,
        body: JoinRoomRequest(inviteCode: room.inviteCode).toJson(),
      );
    }

    final inbox = <String, List<ServerMessage>>{};
    final sockets = <String, IOWebSocketChannel>{};
    for (final u in users) {
      final ws = IOWebSocketChannel.connect(
        Uri.parse('ws://$base${ApiRoutes.socket}?token=dev:$u'),
      );
      sockets[u] = ws;
      inbox[u] = [];
      ws.stream.listen(
        (f) => inbox[u]!.add(
          ServerMessage.fromJson(jsonDecode(f as String) as Json),
        ),
      );
      ws.sink.add(jsonEncode(const Ping().toJson()));
      ws.sink.add(jsonEncode(WatchRoom(room.id).toJson()));
    }

    Future<void> until(bool Function() ok) async {
      for (var i = 0; i < 100 && !ok(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(ok(), isTrue);
    }

    await until(
      () => users.every((u) => inbox[u]!.whereType<RoomUpdated>().isNotEmpty),
    );
    expect(inbox['p1']!.whereType<Pong>(), isNotEmpty);

    // A non-host cannot start; the host can. The actorId sent is ignored.
    sockets['p1']!.sink.add(
      jsonEncode(SendAction(room.id, const StartMatch(actorId: 'p0')).toJson()),
    );
    await until(() => inbox['p1']!.whereType<SocketError>().isNotEmpty);
    expect(inbox['p1']!.whereType<SocketError>().first.code, 'not_host');

    sockets['p0']!.sink.add(
      jsonEncode(SendAction(room.id, const StartMatch(actorId: 'x')).toJson()),
    );
    await until(
      () => users.every(
        (u) => inbox[u]!.whereType<PrivateStateUpdated>().isNotEmpty,
      ),
    );
    for (final u in users) {
      final mine = inbox[u]!.whereType<PrivateStateUpdated>();
      expect(mine.every((m) => m.state.userId == u), isTrue);
      expect(
        inbox[u]!.whereType<PublicStateUpdated>().last.state.phase,
        GamePhase.roleReveal,
      );
    }

    // Clients may not fake the clock.
    sockets['p2']!.sink.add(
      jsonEncode(SendAction(room.id, const PhaseTimeout()).toJson()),
    );
    await until(() => inbox['p2']!.whereType<SocketError>().isNotEmpty);
    expect(inbox['p2']!.whereType<SocketError>().first.code, 'invalid_action');

    // The Mafia (seat 0) leaves: town wins, everyone hears it.
    await call('POST', ApiRoutes.leaveRoom(room.id), user: 'p0');
    await until(
      () => users
          .skip(1)
          .every((u) => inbox[u]!.whereType<MatchEnded>().isNotEmpty),
    );
    expect(
      inbox['p1']!.whereType<MatchEnded>().first.result.winningTeam,
      Team.town,
    );

    for (final ws in sockets.values) {
      await ws.sink.close();
    }
  });
}
