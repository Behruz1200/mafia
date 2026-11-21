import 'dart:async';
import 'dart:convert';

import 'package:contracts/contracts.dart';

/// One open realtime socket of one signed-in user.
class ClientConnection {
  ClientConnection(this.userId, this._sink);

  final UserId userId;
  final void Function(String frame) _sink;

  /// Rooms this socket asked to follow with `watchRoom`.
  final watching = <RoomId>{};

  void send(ServerMessage m) => _sink(jsonEncode(m.toJson()));
}

/// Online or offline, for reconnect handling.
typedef Presence = ({UserId userId, bool online});

/// Every open socket, by user. A user may have more than one at a time
/// (a phone reconnecting before the old socket has timed out).
class SocketHub {
  final _byUser = <UserId, Set<ClientConnection>>{};
  final _presence = StreamController<Presence>.broadcast(sync: true);

  /// Fires when a user's first socket opens and when their last one closes.
  Stream<Presence> get presence => _presence.stream;

  bool isOnline(UserId u) => _byUser[u]?.isNotEmpty ?? false;

  void add(ClientConnection c) {
    final set = _byUser.putIfAbsent(c.userId, () => {});
    set.add(c);
    if (set.length == 1) _presence.add((userId: c.userId, online: true));
  }

  void remove(ClientConnection c) {
    final set = _byUser[c.userId];
    if (set == null || !set.remove(c)) return;
    if (set.isEmpty) {
      _byUser.remove(c.userId);
      _presence.add((userId: c.userId, online: false));
    }
  }

  /// To every socket of [userId]; with [room], only sockets watching it.
  void sendToUser(UserId userId, ServerMessage m, {RoomId? room}) {
    for (final c in [...?_byUser[userId]]) {
      if (room == null || c.watching.contains(room)) c.send(m);
    }
  }

  /// To every socket of [members] that is watching [room].
  void sendToRoom(RoomId room, Iterable<UserId> members, ServerMessage m) {
    for (final u in members) {
      sendToUser(u, m, room: room);
    }
  }
}
