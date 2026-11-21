import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:crypto/crypto.dart';
import 'package:server/call/call_module.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

final creds = LiveKitCredentials(
  publicUrl: 'wss://video.test.uz',
  apiUrl: Uri.parse('http://127.0.0.1:7880'),
  apiKey: 'key1',
  apiSecret: 'secret-secret-secret',
);

Map<String, Object?> decodeJwt(String token, {String? secret}) {
  final parts = token.split('.');
  expect(parts, hasLength(3));
  if (secret != null) {
    final sig = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode('${parts[0]}.${parts[1]}'));
    expect(base64Url.encode(sig.bytes).replaceAll('=', ''), parts[2]);
  }
  return jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
  ) as Map<String, Object?>;
}

PublicGameState game(GamePhase phase, {Set<String> dead = const {}}) {
  final s = samplePublicState(phase: phase);
  return PublicGameState(
    roomId: s.roomId,
    matchId: s.matchId,
    phase: phase,
    round: s.round,
    players: [
      for (final p in s.players) p.copyWith(isAlive: !dead.contains(p.userId)),
    ],
  );
}

/// user_3 and user_5 are Mafia, everyone else town.
Map<UserId, Role> roles() => {
  for (var i = 0; i < 8; i++)
    'user_$i': switch (i) {
      3 => Role.don,
      5 => Role.mafia,
      1 => Role.doctor,
      _ => Role.civilian,
    },
};

class FakeRooms implements LiveKitRooms {
  final connected = <String, List<String>>{};
  final permissions = <String, bool>{}; // "room/identity" -> canPublish
  final deleted = <String>[];

  @override
  Future<List<String>> participants(String room) async =>
      connected[room] ?? const [];

  @override
  Future<void> setPermission(
    String room,
    String identity, {
    required bool canPublish,
    required bool canSubscribe,
  }) async => permissions['$room/$identity'] = canPublish;

  @override
  Future<void> deleteRoom(String room) async => deleted.add(room);
}

class FakeDirectory implements CallRoomDirectory {
  FakeDirectory(this.state);
  GameState state;
  @override
  Future<CallSeat?> seat(RoomId roomId, UserId userId) async {
    final p = state.public.players.where((p) => p.userId == userId);
    if (roomId != state.public.roomId || p.isEmpty) return null;
    return CallSeat(
      roomId: roomId,
      userId: userId,
      displayName: p.first.displayName,
      game: state.public,
      role: state.roles[userId],
    );
  }
}

GameState full(PublicGameState g) =>
    GameState(public: g, roles: roles(), settings: const RoomSettings());

void main() {
  final now = DateTime.utc(2026, 11, 21, 20);
  CallService service(FakeRooms rooms) => CallService(
    signer: LiveKitTokenSigner(creds, clock: () => now),
    rooms: rooms,
    clock: () => now,
  );

  group('CallPolicy', () {
    CallAccess table(
      GamePhase phase,
      String user, {
      Set<String> dead = const {},
    }) => CallPolicy.access(
      channel: CallChannel.table,
      userId: user,
      game: game(phase, dead: dead),
      role: roles()[user],
    );
    CallAccess mafia(
      GamePhase phase,
      String user, {
      Set<String> dead = const {},
    }) => CallPolicy.access(
      channel: CallChannel.mafia,
      userId: user,
      game: game(phase, dead: dead),
      role: roles()[user],
    );

    test('everyone talks before a match and after it ends', () {
      for (final phase in [
        GamePhase.lobby,
        GamePhase.roleReveal,
        GamePhase.ended,
      ]) {
        expect(table(phase, 'user_0').canPublish, isTrue, reason: '$phase');
        expect(table(phase, 'user_3', dead: {'user_3'}).canPublish, isTrue);
      }
      expect(
        CallPolicy.access(
          channel: CallChannel.table,
          userId: 'u',
          game: null,
          role: null,
        ).canPublish,
        isTrue,
      );
    });

    test('nobody talks at the table at night, Mafia included', () {
      for (final u in ['user_0', 'user_3', 'user_5']) {
        final a = table(GamePhase.night, u);
        expect(a.canJoin, isTrue, reason: 'stays connected, no leak');
        expect(a.canPublish, isFalse);
        expect(a.canSubscribe, isTrue);
      }
    });

    test('in the day only the living talk; the dead watch', () {
      for (final phase in [GamePhase.day, GamePhase.voting]) {
        expect(table(phase, 'user_0').canPublish, isTrue);
        final dead = table(phase, 'user_2', dead: {'user_2'});
        expect(dead.canJoin, isTrue);
        expect(dead.canPublish, isFalse);
        expect(dead.canSubscribe, isTrue);
      }
    });

    test('only living Mafia join the Mafia call, only at night', () {
      expect(mafia(GamePhase.night, 'user_3').canPublish, isTrue);
      expect(mafia(GamePhase.night, 'user_5').canJoin, isTrue);
      expect(mafia(GamePhase.night, 'user_0'), CallAccess.denied);
      expect(mafia(GamePhase.night, 'user_1'), CallAccess.denied);
      expect(mafia(GamePhase.day, 'user_3'), CallAccess.denied);
      expect(
        mafia(GamePhase.night, 'user_5', dead: {'user_5'}),
        CallAccess.denied,
      );
    });
  });

  group('tokens', () {
    test('LiveKit token carries identity, room and publish rights', () {
      final svc = service(FakeRooms());
      final g = svc.grant(
        CallSeat(
          roomId: 'room_1',
          userId: 'user_2',
          displayName: 'Dilnoza',
          game: game(GamePhase.night),
          role: Role.civilian,
        ),
        CallChannel.table,
      );
      expect(g.canPublish, isFalse);
      expect(g.serverUrl, 'wss://video.test.uz');
      expect(g.livekitRoom, 'mafia_room_1_table');
      expect(g.expiresAt, now.add(const Duration(minutes: 10)));

      final c = decodeJwt(g.token, secret: creds.apiSecret);
      expect(c['iss'], 'key1');
      expect(c['sub'], 'user_2');
      expect(c['name'], 'Dilnoza');
      expect(c['exp'], now.millisecondsSinceEpoch ~/ 1000 + 600);
      expect(c['video'], {
        'room': 'mafia_room_1_table',
        'roomJoin': true,
        'canPublish': false,
        'canSubscribe': true,
        'canPublishData': false,
        'canPublishSources': ['camera', 'microphone'],
      });
    });

    test('town players cannot get a Mafia grant', () {
      final svc = service(FakeRooms());
      expect(
        () => svc.grant(
          CallSeat(
            roomId: 'room_1',
            userId: 'user_0',
            displayName: 'Aziza',
            game: game(GamePhase.night),
            role: Role.civilian,
          ),
          CallChannel.mafia,
        ),
        throwsA(isA<CallDenied>()),
      );
    });

    test('Mafia grants exist only for Mafia players, at night', () {
      final svc = service(FakeRooms());
      final night = svc.grantsFor(full(game(GamePhase.night)));
      for (final MapEntry(:key, :value) in night.entries) {
        final channels = value.map((g) => g.channel).toList();
        final isMafia = key == 'user_3' || key == 'user_5';
        expect(channels, [
          CallChannel.table,
          if (isMafia) CallChannel.mafia,
        ], reason: key);
      }
      expect(night['user_3']!.last.livekitRoom, 'mafia_room_1_match_1_night');

      final day = svc.grantsFor(full(game(GamePhase.day)));
      expect(day.values.every((g) => g.length == 1), isTrue);
    });

    test('credentials come from the environment, or video is off', () {
      expect(LiveKitCredentials.fromEnvironment({}), isNull);
      final c = LiveKitCredentials.fromEnvironment({
        'LIVEKIT_URL': 'wss://video.x.uz',
        'LIVEKIT_API_KEY': 'k',
        'LIVEKIT_API_SECRET': 's',
      })!;
      expect(c.apiUrl.toString(), 'https://video.x.uz');
      final local = LiveKitCredentials.fromEnvironment({
        'LIVEKIT_URL': 'wss://video.x.uz',
        'LIVEKIT_API_URL': 'http://127.0.0.1:7880',
        'LIVEKIT_API_KEY': 'k',
        'LIVEKIT_API_SECRET': 's',
      })!;
      expect(local.apiUrl.toString(), 'http://127.0.0.1:7880');
    });
  });

  group('phase sync', () {
    test('night mutes the whole table; day unmutes only the living', () async {
      final rooms = FakeRooms()
        ..connected['mafia_room_1_table'] = [
          for (var i = 0; i < 8; i++) 'user_$i',
        ];
      final svc = service(rooms);

      await svc.syncPhase(full(game(GamePhase.night)));
      expect(rooms.permissions.values.every((p) => !p), isTrue);
      expect(rooms.deleted, isEmpty, reason: 'Mafia room stays open at night');

      await svc.syncPhase(
        full(game(GamePhase.day, dead: {'user_2'})),
        previous: full(game(GamePhase.night)),
      );
      expect(rooms.permissions['mafia_room_1_table/user_2'], isFalse);
      expect(rooms.permissions['mafia_room_1_table/user_0'], isTrue);
      expect(rooms.permissions['mafia_room_1_table/user_3'], isTrue);
      expect(rooms.deleted, ['mafia_room_1_match_1_night']);
    });
  });

  group('route', () {
    Future<Response> post(
      CallModule m, {
      String? user,
      String body = '{"channel":"table"}',
      String room = 'room_1',
    }) async {
      final r = Router();
      m.mount(r);
      return r.call(
        Request(
          'POST',
          Uri.parse('http://localhost${ApiRoutes.callGrant(room)}'),
          body: body,
          context: {'userId': ?user},
        ),
      );
    }

    final dir = FakeDirectory(full(game(GamePhase.night)));

    test('501 until LiveKit and rooms are wired in', () async {
      final res = await post(CallModule(environment: const {}), user: 'user_0');
      expect(res.statusCode, 501);
    });

    test('grants a table call to a member', () async {
      final m = CallModule(service: service(FakeRooms()), directory: dir);
      final res = await post(m, user: 'user_0');
      expect(res.statusCode, 200);
      final g = CallGrant.fromJson(
        jsonDecode(await res.readAsString()) as Map<String, Object?>,
      );
      expect(g.channel, CallChannel.table);
      expect(g.canPublish, isFalse);
    });

    test('refuses strangers, the signed out and nosy town players', () async {
      final m = CallModule(service: service(FakeRooms()), directory: dir);
      expect((await post(m)).statusCode, 401);
      expect((await post(m, user: 'stranger')).statusCode, 403);
      expect((await post(m, user: 'user_0', room: 'other')).statusCode, 403);
      final nosy = await post(m, user: 'user_0', body: '{"channel":"mafia"}');
      expect(nosy.statusCode, 403);
      expect(
        jsonDecode(await nosy.readAsString())['error'],
        'call_not_allowed',
      );
      expect(
        (await post(m, user: 'user_3', body: '{"channel":"mafia"}')).statusCode,
        200,
      );
      expect((await post(m, user: 'user_0', body: 'nope')).statusCode, 400);
    });
  });
}
