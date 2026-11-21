import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:server/call/call_module.dart';
import 'package:server/rooms/call_link.dart';
import 'package:test/test.dart';

import 'support.dart';

class FakeLiveKit implements LiveKitRooms {
  final connected = <String, List<String>>{};
  final perms = <String, ({bool pub, bool sub})>{};
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
  }) async => perms['$room/$identity'] = (pub: canPublish, sub: canSubscribe);

  @override
  Future<void> deleteRoom(String room) async => deleted.add(room);
}

void main() {
  test('video follows the game, and grants stay private', () {
    fakeAsync((a) {
      final rig = Rig();
      final lk = FakeLiveKit();
      final call = CallService(
        signer: LiveKitTokenSigner(
          LiveKitCredentials(
            publicUrl: 'wss://video.test',
            apiUrl: Uri.parse('http://127.0.0.1:7880'),
            apiKey: 'key',
            apiSecret: 'a-livekit-secret-of-32-characters!!',
          ),
        ),
        rooms: lk,
      );
      final link = RoomsCallLink(
        rooms: rig.service,
        hub: rig.hub,
        call: call,
        log: (_) {},
      );
      const users = ['u0', 'u1', 'u2', 'u3'];

      late Room room;
      rig.service.create('u0', fastSettings).then((r) => room = r);
      a.flushMicrotasks();
      for (final u in users.skip(1)) {
        rig.service.join(u, room.inviteCode);
        a.flushMicrotasks();
      }
      for (final u in users) {
        rig.service.watch(rig.socket(u).conn, room.id);
      }
      a.flushMicrotasks();

      // Seats for members only.
      CallSeat? seat;
      link.seat(room.id, 'u1').then((s) => seat = s);
      a.flushMicrotasks();
      expect(seat!.displayName, 'Name of u1');
      link.seat(room.id, 'stranger').then((s) => seat = s);
      a.flushMicrotasks();
      expect(seat, isNull);

      lk.connected[CallRoomNames.table(room.id)] = users;
      rig.service.act('u0', room.id, const StartMatch(actorId: 'u0'));
      a.flushMicrotasks();
      a.elapse(const Duration(seconds: 3)); // night (round 1)

      final table = CallRoomNames.table(room.id);
      expect(lk.perms['$table/u1']!.pub, isFalse, reason: 'town muted');
      final matchId = rig.service.publicState(room.id)!.matchId;
      final mafiaRoom = CallRoomNames.mafia(room.id, matchId);

      List<CallGrant> grantsOf(String u) => [
        for (final m in rig.sockets[u]!.messages.whereType<CallGrantIssued>())
          m.grant,
      ];
      expect(grantsOf('u0').map((g) => g.livekitRoom), contains(mafiaRoom));
      for (final u in users.skip(1)) {
        expect(grantsOf(u), isNotEmpty);
        expect(
          grantsOf(u).map((g) => g.livekitRoom),
          isNot(contains(mafiaRoom)),
          reason: 'the town never gets the Mafia call',
        );
      }

      a.elapse(const Duration(seconds: 10)); // day
      expect(lk.perms['$table/u1']!.pub, isTrue);
      expect(
        lk.deleted,
        contains(mafiaRoom),
        reason: 'Mafia call closes at dawn',
      );

      // Everyone leaves: the room closes and so do its calls.
      for (final u in users) {
        rig.service.leave(u, room.id);
        a.flushMicrotasks();
      }
      a.flushMicrotasks();
      expect(lk.deleted, contains(table));

      link.dispose();
      rig.service.dispose();
      a.flushMicrotasks();
    });
  });

  test('only real changes reach the video service', () {
    final players = samplePlayers(4);
    GameState s(GamePhase phase, {int dead = -1, String match = 'm1'}) =>
        GameState(
          settings: fastSettings,
          roles: const {},
          public: PublicGameState(
            roomId: 'r',
            matchId: match,
            phase: phase,
            round: 1,
            players: [
              for (final p in players)
                p.seat == dead ? p.copyWith(isAlive: false) : p,
            ],
          ),
        );
    expect(RoomsCallLink.matters(s(GamePhase.day), null), isTrue);
    expect(RoomsCallLink.matters(s(GamePhase.day), s(GamePhase.day)), isFalse);
    expect(
      RoomsCallLink.matters(s(GamePhase.voting), s(GamePhase.day)),
      isTrue,
    );
    expect(
      RoomsCallLink.matters(s(GamePhase.day, dead: 2), s(GamePhase.day)),
      isTrue,
    );
    expect(
      RoomsCallLink.matters(s(GamePhase.day, match: 'm2'), s(GamePhase.day)),
      isTrue,
    );
  });
}
