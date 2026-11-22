import 'dart:async';
import 'dart:io';

import 'package:contracts/contracts.dart';

import '../call/call_service.dart';
import '../realtime/socket_hub.dart';
import 'room_service.dart';

/// Connects rooms to the video module (stream 3):
///
/// - answers [CallRoomDirectory.seat] for `POST /v1/rooms/<id>/call`,
/// - after every phase change or death, mutes and unmutes the table and
///   closes the Mafia call ([CallService.syncPhase]), and pushes each
///   player's new grants on their own sockets only,
/// - closes the LiveKit rooms when a room closes.
///
/// With no [call] service (LiveKit not configured) it only answers seats.
class RoomsCallLink implements CallRoomDirectory {
  RoomsCallLink({
    required this.rooms,
    required this.hub,
    this.call,
    void Function(String)? log,
  }) : _log = log ?? ((m) => stderr.writeln('call link: $m')) {
    if (call == null) return;
    _subs
      ..add(rooms.matchStates.listen(_onState))
      ..add(rooms.roomChanges.listen(_onRoom));
  }

  final RoomService rooms;
  final SocketHub hub;
  final CallService? call;
  final void Function(String) _log;
  final _subs = <StreamSubscription<Object?>>[];
  final _lastMatch = <RoomId, MatchId>{};

  /// Calls to LiveKit, one after another, so mutes land in phase order.
  Future<void> _queue = Future.value();

  @override
  Future<CallSeat?> seat(RoomId roomId, UserId userId) async {
    final name = rooms.displayNameOf(roomId, userId);
    if (name == null) return null;
    return CallSeat(
      roomId: roomId,
      userId: userId,
      displayName: name,
      game: rooms.publicState(roomId),
      role: rooms.roleOf(roomId, userId),
    );
  }

  /// True when the change matters to the call: a new match, a new phase or
  /// round, or someone died. Connection flickers and votes do not.
  static bool matters(GameState next, GameState? prev) {
    final n = next.public;
    final p = prev?.public;
    if (p == null || p.matchId != n.matchId) return true;
    if (p.phase != n.phase || p.round != n.round) return true;
    Set<UserId> alive(PublicGameState s) => {
      for (final x in s.players)
        if (x.isAlive) x.userId,
    };
    return alive(p).length != alive(n).length ||
        !alive(p).containsAll(alive(n));
  }

  void _onState(MatchStateChange c) {
    final call = this.call!;
    final game = c.next.public;
    _lastMatch[game.roomId] = game.matchId;
    if (!matters(c.next, c.previous)) return;
    try {
      call.grantsFor(c.next).forEach((u, grants) {
        for (final g in grants) {
          hub.sendToUser(u, CallGrantIssued(game.roomId, g), room: game.roomId);
        }
      });
    } on Object catch (e) {
      _log('grants for ${game.matchId} failed: $e');
    }
    _enqueue(
      'sync ${game.matchId} ${game.phase.name}',
      () => call.syncPhase(c.next, previous: c.previous),
    );
  }

  void _onRoom(Room r) {
    if (r.status != RoomStatus.closed) return;
    final last = _lastMatch.remove(r.id);
    _enqueue('close ${r.id}', () => call!.closeRoom(r.id, lastMatchId: last));
  }

  void _enqueue(String what, Future<void> Function() f) {
    _queue = _queue.then((_) async {
      try {
        await f();
      } on Object catch (e) {
        // Video trouble must never stop the game.
        _log('$what failed: $e');
      }
    });
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _queue;
  }
}
