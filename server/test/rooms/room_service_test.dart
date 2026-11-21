import 'package:contracts/contracts.dart';
import 'package:fake_async/fake_async.dart';
import 'package:server/rooms/match_recorder.dart';
import 'package:server/rooms/room_error.dart';
import 'package:server/rooms/room_service.dart';
import 'package:test/test.dart';

import 'support.dart';

Matcher roomError(String code) =>
    isA<RoomError>().having((e) => e.code, 'code', code);

/// Runs [body] in fake time, flushing microtasks between steps.
void fake(void Function(FakeAsync a) body) => fakeAsync((a) {
  body(a);
  a.flushMicrotasks();
});

void main() {
  const users = ['u0', 'u1', 'u2', 'u3', 'u4', 'u5', 'u6'];

  /// Host u0 creates a room and u1..u(n-1) join; all have sockets watching.
  Room fill(Rig rig, FakeAsync a, {int n = 4, RoomSettings? settings}) {
    late Room room;
    rig.service.create('u0', settings ?? fastSettings).then((r) => room = r);
    a.flushMicrotasks();
    for (final u in users.sublist(1, n)) {
      rig.service.join(u, room.inviteCode);
      a.flushMicrotasks();
    }
    for (final u in users.sublist(0, n)) {
      rig.service.watch(rig.socket(u).conn, room.id);
    }
    a.flushMicrotasks();
    return rig.service.room(room.id)!;
  }

  void start(Rig rig, FakeAsync a, Room room) {
    rig.service.act('u0', room.id, const StartMatch(actorId: 'u0'));
    a.flushMicrotasks();
  }

  group('lobby', () {
    test('create, join by code in any case, get, leave', () {
      fake((a) {
        final rig = Rig();
        final room = fill(rig, a, n: 2);
        expect(room.hostId, 'u0');
        expect(room.memberIds, ['u0', 'u1']);
        expect(room.inviteCode, hasLength(5));
        expect(room.status, RoomStatus.open);

        rig.service.join('u2', ' ${room.inviteCode.toLowerCase()} ');
        a.flushMicrotasks();
        expect(rig.service.room(room.id)!.memberIds, ['u0', 'u1', 'u2']);

        // Members were told.
        expect(
          rig.sockets['u1']!.last<RoomUpdated>()!.room.memberIds,
          hasLength(3),
        );

        expect(
          () => rig.service.get('u9', room.id),
          throwsA(roomError('room_not_found')),
        );

        rig.service.leave('u0', room.id);
        a.flushMicrotasks();
        final after = rig.service.room(room.id)!;
        expect(after.memberIds, ['u1', 'u2']);
        expect(after.hostId, 'u1', reason: 'host passes on');
        rig.service.dispose();
      });
    });

    test('unknown code, full room and bad settings are refused', () {
      fake((a) {
        final rig = Rig();
        Object? err;
        rig.service
            .join('u1', 'ZZZZZ')
            .then(
              (_) {},
              onError: (Object e) {
                err = e;
              },
            );
        a.flushMicrotasks();
        expect(err, roomError('room_not_found'));

        final room = fill(rig, a, n: 6); // maxPlayers 6
        rig.service
            .join('u6', room.inviteCode)
            .then(
              (_) {},
              onError: (Object e) {
                err = e;
              },
            );
        a.flushMicrotasks();
        expect(err, roomError('room_full'));

        for (final s in [
          const RoomSettings(minPlayers: 2),
          const RoomSettings(maxPlayers: 30),
          const RoomSettings(stake: -1),
          const RoomSettings(
            durations: PhaseDurations(night: Duration(seconds: 1)),
          ),
        ]) {
          err = null;
          rig.service
              .create('u6', s)
              .then(
                (_) {},
                onError: (Object e) {
                  err = e;
                },
              );
          a.flushMicrotasks();
          expect(err, roomError('invalid_settings'));
        }
        rig.service.dispose();
      });
    });

    test('joining another lobby leaves the first one', () {
      fake((a) {
        final rig = Rig();
        final first = fill(rig, a, n: 2);
        late Room second;
        rig.service.create('u5', fastSettings).then((r) => second = r);
        a.flushMicrotasks();
        rig.service.join('u1', second.inviteCode);
        a.flushMicrotasks();
        expect(rig.service.room(first.id)!.memberIds, ['u0']);
        expect(rig.service.room(second.id)!.memberIds, ['u5', 'u1']);
        rig.service.dispose();
      });
    });
  });

  group('match', () {
    test('only the host starts, and only with enough players', () {
      fake((a) {
        final rig = Rig();
        final room = fill(rig, a, n: 3);
        Object? err;
        rig.service
            .act('u0', room.id, const StartMatch(actorId: 'u0'))
            .then(
              (_) {},
              onError: (Object e) {
                err = e;
              },
            );
        a.flushMicrotasks();
        expect(err, roomError('not_enough_players'));

        rig.service.join('u3', room.inviteCode);
        a.flushMicrotasks();
        rig.service
            .act('u1', room.id, const StartMatch(actorId: 'u1'))
            .then(
              (_) {},
              onError: (Object e) {
                err = e;
              },
            );
        a.flushMicrotasks();
        expect(err, roomError('not_host'));
        rig.service.dispose();
      });
    });

    test('each player sees public state and only their own role', () {
      fake((a) {
        final rig = Rig();
        final room = fill(rig, a);
        start(rig, a, room);

        expect(rig.service.room(room.id)!.status, RoomStatus.inMatch);
        for (final u in users.take(4)) {
          final s = rig.sockets[u]!;
          final pub = s.last<PublicStateUpdated>()!.state;
          expect(pub.phase, GamePhase.roleReveal);
          expect(pub.players.map((p) => p.displayName), contains('Name of u1'));
          final privates = s.messages.whereType<PrivateStateUpdated>();
          expect(privates, isNotEmpty);
          expect(
            privates.every((m) => m.state.userId == u),
            isTrue,
            reason: 'roles never leak to other sockets',
          );
        }
        expect(
          rig.sockets['u0']!.last<PrivateStateUpdated>()!.state.role,
          Role.mafia,
        );
        expect(
          () => rig.service.join('u5', room.inviteCode),
          throwsA(anything),
        );
        rig.service.dispose();
      });
    });

    test('the phase clock advances the match', () {
      fake((a) {
        final rig = Rig();
        final room = fill(rig, a);
        start(rig, a, room);
        GamePhase phase() => rig.service.publicState(room.id)!.phase;

        a.elapse(const Duration(seconds: 2));
        expect(phase(), GamePhase.roleReveal);
        a.elapse(const Duration(seconds: 1));
        expect(phase(), GamePhase.night);
        a.elapse(const Duration(seconds: 10));
        expect(phase(), GamePhase.day);
        a.elapse(const Duration(seconds: 20));
        expect(phase(), GamePhase.voting);
        rig.service.dispose();
      });
    });

    test('engine rejections go back to the sender only', () {
      fake((a) {
        final rig = Rig();
        final room = fill(rig, a);
        start(rig, a, room);
        a.elapse(const Duration(seconds: 3)); // night
        Object? err;
        rig.service
            .act('u1', room.id, const NightKill(actorId: 'u1', targetId: 'u2'))
            .then(
              (_) {},
              onError: (Object e) {
                err = e;
              },
            );
        a.flushMicrotasks();
        expect(err, roomError('not_allowed'));

        err = null;
        rig.service
            .act('u0', room.id, const NightKill(actorId: 'u0', targetId: 'u2'))
            .then(
              (_) {},
              onError: (Object e) {
                err = e;
              },
            );
        a.flushMicrotasks();
        expect(err, isNull);

        rig.service
            .act('u9', room.id, const CastVote(actorId: 'u9', targetId: null))
            .then(
              (_) {},
              onError: (Object e) {
                err = e;
              },
            );
        a.flushMicrotasks();
        expect(err, roomError('not_in_room'));
        rig.service.dispose();
      });
    });

    test('stakes are held at start and paid out at the end', () {
      fake((a) {
        final rig = Rig(coins: {for (final u in users) u: 500});
        final room = fill(rig, a, settings: staked(100));
        start(rig, a, room);
        expect(rig.wallet.availableOf('u1'), 400);
        expect(rig.sockets['u1']!.last<WalletUpdated>()!.wallet.inEscrow, 100);

        // The Mafia (u0) walks out: forfeits, town wins.
        rig.service.leave('u0', room.id);
        a.flushMicrotasks();

        final end = rig.sockets['u1']!.last<MatchEnded>()!.result;
        expect(end.winningTeam, Team.town);
        // Pot 400, house 10% = 40, 360 / 3 winners = 120 each.
        expect(rig.wallet.availableOf('u1'), 520);
        expect(rig.wallet.availableOf('u0'), 400);
        expect(rig.sockets['u1']!.last<WalletUpdated>()!.wallet.available, 520);
        expect(rig.service.room(room.id)!.status, RoomStatus.open);
        rig.service.dispose();
      });
    });

    test('nobody is charged if someone cannot cover the stake', () {
      fake((a) {
        final rig = Rig(coins: {for (final u in users) u: 500});
        final room = fill(rig, a, settings: staked(100));
        rig.wallet.holdStakes(matchId: 'other', players: ['u2'], stake: 450);
        a.flushMicrotasks();
        Object? err;
        rig.service
            .act('u0', room.id, const StartMatch(actorId: 'u0'))
            .then(
              (_) {},
              onError: (Object e) {
                err = e;
              },
            );
        a.flushMicrotasks();
        expect(err, roomError('insufficient_coins'));
        expect((err! as RoomError).message, 'u2');
        expect(rig.wallet.availableOf('u0'), 500);
        expect(rig.service.room(room.id)!.status, RoomStatus.open);
        rig.service.dispose();
      });
    });

    test('staked rooms need an adult in a stake country with coins', () {
      fake((a) {
        final rig = Rig(
          coins: {'u0': 500, 'u1': 500, 'u2': 10},
          players: TestPlayers(minors: {'u1'}),
        );
        late Room room;
        rig.service.create('u0', staked(100)).then((r) => room = r);
        a.flushMicrotasks();
        Object? err;
        rig.service
            .join('u1', room.inviteCode)
            .then(
              (_) {},
              onError: (Object e) {
                err = e;
              },
            );
        a.flushMicrotasks();
        expect(err, roomError('stakes_not_allowed'));
        rig.service
            .join('u2', room.inviteCode)
            .then(
              (_) {},
              onError: (Object e) {
                err = e;
              },
            );
        a.flushMicrotasks();
        expect(err, roomError('insufficient_coins'));
        rig.service.dispose();
      });
    });

    test('a player offline past the grace period forfeits', () {
      fake((a) {
        final rig = Rig(coins: {for (final u in users) u: 500});
        final room = fill(rig, a, settings: staked(100));
        start(rig, a, room);

        rig.sockets['u0']!.close();
        a.flushMicrotasks();
        final pub = rig.service.publicState(room.id)!;
        expect(
          pub.players.firstWhere((p) => p.userId == 'u0').isConnected,
          isFalse,
        );

        a.elapse(const Duration(seconds: 59));
        expect(rig.service.room(room.id)!.status, RoomStatus.inMatch);
        a.elapse(const Duration(seconds: 2));
        expect(rig.sockets['u1']!.last<MatchEnded>(), isNotNull);
        expect(rig.wallet.availableOf('u0'), 400);
        expect(rig.service.room(room.id)!.memberIds, isNot(contains('u0')));
        rig.service.dispose();
      });
    });

    test('coming back within the grace period keeps the seat', () {
      fake((a) {
        final rig = Rig();
        final room = fill(rig, a);
        start(rig, a, room);
        rig.sockets['u1']!.close();
        a.elapse(const Duration(seconds: 30));
        final again = rig.socket('u1');
        rig.service.watch(again.conn, room.id);
        a.elapse(const Duration(seconds: 60));
        final me = rig.service
            .publicState(room.id)!
            .players
            .firstWhere((p) => p.userId == 'u1');
        expect(me.isAlive, isTrue);
        expect(me.isConnected, isTrue);
        expect(again.last<PrivateStateUpdated>()!.state.userId, 'u1');
        rig.service.dispose();
      });
    });

    test('a match that runs too long is cancelled and refunded', () {
      fake((a) {
        final rig = Rig(
          coins: {for (final u in users) u: 500},
          config: const RoomsConfig(maxMatchLength: Duration(minutes: 5)),
        );
        final room = fill(rig, a, settings: staked(100));
        start(rig, a, room);
        a.elapse(const Duration(minutes: 5, seconds: 1));
        final end = rig.sockets['u2']!.last<MatchEnded>()!.result;
        expect(end.cancelled, isTrue);
        expect(rig.wallet.availableOf('u2'), 500);
        rig.service.dispose();
      });
    });
  });

  group('quick match', () {
    test('fills the fullest public room, else opens one, then auto-starts', () {
      fake((a) {
        final rig = Rig(
          config: const RoomsConfig(
            quickMatchSettings: RoomSettings(
              minPlayers: 4,
              maxPlayers: 5,
              visibility: RoomVisibility.public,
            ),
          ),
        );
        final rooms = <Room>[];
        for (final u in users.take(4)) {
          rig.service.quickMatch(u).then(rooms.add);
          a.flushMicrotasks();
        }
        expect(rooms.map((r) => r.id).toSet(), hasLength(1));
        final id = rooms.first.id;
        expect(rig.service.room(id)!.memberIds, hasLength(4));

        // Private rooms are never matched.
        rig.service.create('u6', fastSettings);
        a.flushMicrotasks();

        a.elapse(const Duration(seconds: 19));
        expect(rig.service.room(id)!.status, RoomStatus.open);
        a.elapse(const Duration(seconds: 2));
        expect(rig.service.room(id)!.status, RoomStatus.inMatch);

        // A newcomer gets a fresh public room.
        late Room fresh;
        rig.service.quickMatch('u5').then((r) => fresh = r);
        a.flushMicrotasks();
        expect(fresh.id, isNot(id));
        expect(fresh.settings.visibility, RoomVisibility.public);
        rig.service.dispose();
      });
    });

    test('players who can stake get 100-coin games, others free ones', () {
      fake((a) {
        final rig = Rig(
          coins: {'u0': 500, 'u1': 500, 'u2': 50, 'u3': 500},
          players: TestPlayers(minors: {'u3'}),
        );
        final got = <UserId, Room>{};
        for (final u in ['u0', 'u1', 'u2', 'u3']) {
          rig.service.quickMatch(u).then((r) => got[u] = r);
          a.flushMicrotasks();
        }
        expect(got['u0']!.settings.stake, 100);
        expect(got['u1']!.id, got['u0']!.id);
        expect(got['u2']!.settings.stake, 0, reason: 'cannot cover 100');
        expect(got['u3']!.settings.stake, 0, reason: 'under 18');
        expect(got['u3']!.id, got['u2']!.id);
        expect(got['u2']!.id, isNot(got['u0']!.id));
        rig.service.dispose();
      });
    });

    test('a full public room starts at once', () {
      fake((a) {
        final rig = Rig(
          config: const RoomsConfig(
            quickMatchSettings: RoomSettings(
              minPlayers: 4,
              maxPlayers: 4,
              visibility: RoomVisibility.public,
            ),
          ),
        );
        late Room room;
        for (final u in users.take(4)) {
          rig.service.quickMatch(u).then((r) => room = r);
          a.flushMicrotasks();
        }
        expect(rig.service.room(room.id)!.status, RoomStatus.inMatch);
        rig.service.dispose();
      });
    });
  });

  group('recovery', () {
    test('settles what a previous run left in escrow', () {
      fake((a) {
        final recorder = InMemoryMatchRecorder();
        final rig = Rig(coins: {'a': 100, 'b': 100}, recorder: recorder);
        // A previous process held stakes for two matches, then died.
        rig.wallet.holdStakes(
          matchId: 'm_dead',
          players: ['a', 'b'],
          stake: 50,
        );
        rig.wallet.holdStakes(
          matchId: 'm_done',
          players: ['a', 'b'],
          stake: 10,
        );
        for (final m in ['m_dead', 'm_done']) {
          recorder.started(
            roomId: 'r',
            matchId: m,
            stake: m == 'm_dead' ? 50 : 10,
            players: ['a', 'b'],
            seed: 1,
            at: DateTime.utc(2026),
          );
        }
        recorder.ended(
          MatchResult(
            roomId: 'r',
            matchId: 'm_done',
            stake: 10,
            winningTeam: Team.town,
            winners: ['a'],
            losers: ['b'],
            endedAt: DateTime.utc(2026),
          ),
        );
        a.flushMicrotasks();
        expect(rig.wallet.availableOf('a'), 40);

        int? n;
        rig.service.recoverUnsettled().then((v) => n = v);
        a.flushMicrotasks();
        expect(n, 2);
        // m_dead refunded (+50), m_done paid: pot 20, fee 2, a gets 18.
        expect(rig.wallet.availableOf('a'), 108);
        expect(rig.wallet.availableOf('b'), 90);

        rig.service.recoverUnsettled().then((v) => n = v);
        a.flushMicrotasks();
        expect(n, 0, reason: 'nothing left to settle');
        rig.service.dispose();
      });
    });
  });
}
