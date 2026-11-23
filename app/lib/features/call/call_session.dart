import 'dart:async';

import 'package:contracts/contracts.dart';

import 'call_state.dart';

/// Gets a `CallGrant` from the game server.
abstract interface class CallGrantSource {
  Future<CallGrant> fetch(RoomId roomId, CallChannel channel);
}

/// Keeps one player's call in step with the game: joins the table when the
/// room opens, asks for fresh grants at every phase change (the server
/// mutes the town at night), and joins or leaves the Mafia call for Mafia.
///
/// The server decides; a refused grant is ignored and tried again at the
/// next phase change.
class CallSession {
  CallSession({
    required this.roomId,
    required this.rooms,
    required this.grants,
    required this.call,
  });

  final RoomId roomId;
  final RoomRepository rooms;
  final CallGrantSource grants;
  final CallController call;

  final _subs = <StreamSubscription<Object?>>[];
  PublicGameState? _game;
  PrivatePlayerState? _me;
  String? _lastKey;
  bool _inMafia = false;
  bool _disposed = false;
  Future<void> _queue = Future.value();

  /// Completes when the latest sync has finished. For tests.
  Future<void> get idle => _queue;

  void start() {
    _subs
      ..add(
        rooms.watchPublicState(roomId).listen((s) {
          _game = s;
          _schedule();
        }),
      )
      ..add(
        rooms.watchMyState(roomId).listen((s) {
          _me = s;
          _schedule();
        }),
      );
    _schedule();
  }

  bool get _wantsMafia {
    final game = _game;
    final me = _me;
    if (game == null || me == null) return false;
    if (me.role.team != Team.mafia || game.phase != GamePhase.night) {
      return false;
    }
    return game.players.any((p) => p.userId == me.userId && p.isAlive);
  }

  /// Anything that changes call permissions: match, phase, round, and who
  /// is alive.
  String get _key {
    final g = _game;
    if (g == null) return 'open';
    final alive = [
      for (final p in g.players)
        if (p.isAlive) p.userId,
    ];
    return '${g.matchId}|${g.phase.name}|${g.round}|${alive.join(',')}|'
        '${_me?.role.name}';
  }

  /// Asks for fresh grants and reconnects whatever dropped, e.g. from the
  /// refresh button when a camera looks frozen.
  void resync() {
    _lastKey = null;
    _schedule();
  }

  void _schedule() {
    final key = _key;
    if (key == _lastKey || _disposed) return;
    _lastKey = key;
    _queue = _queue.then((_) => _sync()).catchError((Object _) {});
  }

  Future<void> _sync() async {
    if (_disposed) return;
    await _join(CallChannel.table);
    if (_wantsMafia) {
      _inMafia = await _join(CallChannel.mafia) || _inMafia;
    } else if (_inMafia) {
      _inMafia = false;
      final c = call;
      if (c is TableCallController) await c.leaveChannel(CallChannel.mafia);
    }
  }

  Future<bool> _join(CallChannel channel) async {
    try {
      final grant = await grants.fetch(roomId, channel);
      if (_disposed) return false;
      await call.join(grant);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    await _queue;
    await call.leave();
  }
}
