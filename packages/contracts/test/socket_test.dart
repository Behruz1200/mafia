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
      Ping(),
    ];
    for (final m in msgs) {
      final back = ClientMessage.fromJson(wire(m.toJson()));
      expect(back.runtimeType, m.runtimeType);
      expect(back.toJson(), m.toJson());
    }
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
