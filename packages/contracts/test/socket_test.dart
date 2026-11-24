import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:test/test.dart';

Json wire(Json j) => jsonDecode(jsonEncode(j)) as Json;

void main() {
  test('client messages round-trip', () {
    const msgs = <ClientMessage>[
      WatchRoom('r'),
      UnwatchRoom('r'),
      SendAction('r', CastVote(actorId: 'a', targetId: 'b')),
      ComeBack('r'),
      SetHost('r', 'u'),
      Ping(),
    ];
    for (final m in msgs) {
      final back = ClientMessage.fromJson(wire(m.toJson()));
      expect(back.runtimeType, m.runtimeType);
      expect(back.toJson(), m.toJson());
    }
  });

  test('a room says who is back and who is offline', () {
    final r = sampleRoom(players: 4);
    final room = Room.fromJson(
      wire({
        ...r.toJson(),
        'notBackIds': ['user_1'],
        'offlineIds': ['user_2'],
      }),
    );
    expect(room.notBackIds, ['user_1']);
    expect(room.offlineIds, ['user_2']);
    expect(room.readyIds, ['user_0', 'user_3']);
    // Older servers send neither: everyone counts as here.
    expect(Room.fromJson(wire(r.toJson()..remove('notBackIds'))).readyIds, [
      'user_0',
      'user_1',
      'user_2',
      'user_3',
    ]);
  });

  test('the last vote travels with the public state', () {
    final s = samplePublicState();
    final back = PublicGameState.fromJson(
      wire({
        ...s.toJson(),
        'lastVotes': {'user_1': 'user_2', 'user_3': null},
      }),
    );
    expect(back.lastVotes, {'user_1': 'user_2', 'user_3': null});
    expect(PublicGameState.fromJson(wire(s.toJson())).lastVotes, isEmpty);
  });

  test('server messages round-trip', () {
    final msgs = <ServerMessage>[
      RoomUpdated(sampleRoom()),
      PublicStateUpdated(samplePublicState()),
      PrivateStateUpdated('room_1', samplePrivateState(role: Role.mafia)),
      CallGrantIssued(
        'room_1',
        CallGrant(
          serverUrl: 'wss://v',
          token: 't',
          livekitRoom: 'room_1-mafia',
          channel: CallChannel.mafia,
          canPublish: true,
          expiresAt: fixtureNow,
        ),
      ),
      MatchEnded(
        MatchResult(
          roomId: 'r',
          matchId: 'm',
          stake: 0,
          winners: const [],
          losers: const [],
          endedAt: fixtureNow,
        ),
      ),
      const WalletUpdated(WalletBalance(userId: 'a', available: 5)),
      const SocketError('invalid_action', 'nope'),
      const Pong(),
    ];
    for (final m in msgs) {
      final back = ServerMessage.fromJson(wire(m.toJson()));
      expect(back.runtimeType, m.runtimeType);
      expect(back.toJson(), m.toJson());
    }
  });
}
