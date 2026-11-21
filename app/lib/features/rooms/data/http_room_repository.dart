import 'dart:async';
import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// A refused room request, e.g. `room_full` or `insufficient_coins`.
/// [error.code] is the stable code the UI localises.
class RoomRequestFailed implements Exception {
  const RoomRequestFailed(this.status, this.error);
  final int status;
  final ApiError error;
  @override
  String toString() => 'RoomRequestFailed($status, ${error.code})';
}

/// The real [RoomRepository] (stream 2): REST for joining and leaving,
/// one realtime socket for everything live.
///
/// The socket reconnects on its own (1 s, 2 s, 4 s ... up to 30 s) and
/// re-watches every room, and the server re-sends the room, public and
/// private state on each watch, so a dropped connection heals itself. The
/// server keeps a seat for 60 seconds.
class HttpRoomRepository implements RoomRepository {
  HttpRoomRepository({
    required this.baseUrl,
    required this.accessToken,
    http.Client? client,
    WebSocketChannel Function(Uri)? connect,
  }) : _http = client ?? http.Client(),
       _connect = connect ?? WebSocketChannel.connect;

  /// e.g. `https://api.example.uz`.
  final Uri baseUrl;

  /// The current access token, or null when signed out.
  final String? Function() accessToken;

  final http.Client _http;
  final WebSocketChannel Function(Uri) _connect;

  final _messages = StreamController<ServerMessage>.broadcast();
  final _watched = <RoomId>{};
  WebSocketChannel? _socket;
  StreamSubscription<Object?>? _sub;
  Timer? _retry;
  var _attempt = 0;
  var _closed = false;

  /// Every message from the server, for other features that share this
  /// socket (wallet updates, call grants).
  Stream<ServerMessage> get messages => _messages.stream;

  /// Errors the server sent back for actions, e.g. `not_your_turn`.
  Stream<SocketError> get errors => messages.whereType<SocketError>();

  // ---------------------------------------------------------------- REST

  @override
  Future<Room> createRoom(RoomSettings settings) => _postRoom(
    ApiRoutes.rooms,
    CreateRoomRequest(settings: settings).toJson(),
  );

  @override
  Future<Room> joinByCode(InviteCode code) =>
      _postRoom(ApiRoutes.joinRoom, JoinRoomRequest(inviteCode: code).toJson());

  @override
  Future<Room> quickMatch() => _postRoom(ApiRoutes.quickMatch, const {});

  @override
  Future<void> leave(RoomId roomId) async {
    _watched.remove(roomId);
    _sendFrame(UnwatchRoom(roomId));
    await _request('POST', ApiRoutes.leaveRoom(roomId), const {});
  }

  /// Re-reads a room, e.g. after the app was in the background.
  Future<Room> fetchRoom(RoomId roomId) async =>
      Room.fromJson(await _request('GET', ApiRoutes.room(roomId), null));

  Future<Room> _postRoom(String path, Json body) async =>
      Room.fromJson(await _request('POST', path, body));

  Future<Json> _request(String method, String path, Json? body) async {
    final token = accessToken();
    final req = http.Request(method, baseUrl.resolve(path))
      ..headers['content-type'] = 'application/json'
      ..headers['accept'] = 'application/json';
    if (token != null) req.headers['authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req));
    final Object? decoded;
    try {
      decoded = res.body.isEmpty
          ? const <String, Object?>{}
          : jsonDecode(res.body);
    } on FormatException {
      throw RoomRequestFailed(
        res.statusCode,
        const ApiError(code: 'bad_response'),
      );
    }
    if (res.statusCode >= 400) {
      throw RoomRequestFailed(
        res.statusCode,
        decoded is Json && decoded['error'] is String
            ? ApiError.fromJson(decoded)
            : const ApiError(code: 'server_error'),
      );
    }
    return decoded! as Json;
  }

  // ------------------------------------------------------------- socket

  @override
  Stream<Room> watchRoom(RoomId roomId) =>
      _follow(roomId)
          .whereType<RoomUpdated>()
          .map((m) => m.room)
          .where((r) => r.id == roomId);

  @override
  Stream<PublicGameState> watchPublicState(RoomId roomId) =>
      _follow(roomId)
          .whereType<PublicStateUpdated>()
          .map((m) => m.state)
          .where((s) => s.roomId == roomId);

  @override
  Stream<PrivatePlayerState> watchMyState(RoomId roomId) =>
      _follow(roomId)
          .whereType<PrivateStateUpdated>()
          .where((m) => m.roomId == roomId)
          .map((m) => m.state);

  @override
  Stream<MatchResult> watchMatchEnd(RoomId roomId) =>
      _follow(roomId)
          .whereType<MatchEnded>()
          .map((m) => m.result)
          .where((r) => r.roomId == roomId);

  @override
  Future<void> send(RoomId roomId, GameAction action) async {
    _ensureSocket();
    _sendFrame(SendAction(roomId, action));
  }

  /// Messages for [roomId]. Subscribing (re-)sends `watchRoom`, so each new
  /// listener gets the current room and state straight away.
  Stream<ServerMessage> _follow(RoomId roomId) {
    late final StreamController<ServerMessage> c;
    StreamSubscription<ServerMessage>? sub;
    c = StreamController<ServerMessage>(
      onListen: () {
        sub = _messages.stream.listen(c.add, onError: c.addError);
        _watched.add(roomId);
        _ensureSocket();
        _sendFrame(WatchRoom(roomId));
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  void _ensureSocket() {
    if (_socket != null || _closed) return;
    final token = accessToken();
    if (token == null) return;
    final http = baseUrl.resolve(ApiRoutes.socket);
    final uri = http.replace(
      scheme: http.scheme == 'https' ? 'wss' : 'ws',
      queryParameters: {'token': token},
    );
    final ch = _connect(uri);
    _socket = ch;
    _sub = ch.stream.listen(
      (frame) {
        _attempt = 0;
        try {
          _messages.add(
            ServerMessage.fromJson(jsonDecode(frame as String) as Json),
          );
        } on Object {
          // A message type this app version does not know yet: skip it.
        }
      },
      onDone: _dropped,
      onError: (Object _) => _dropped(),
      cancelOnError: true,
    );
    ch.ready.then((_) {
      for (final id in _watched) {
        _sendFrame(WatchRoom(id));
      }
    }, onError: (Object _) {});
  }

  void _dropped() {
    _sub?.cancel();
    _socket = null;
    if (_closed) return;
    final secs = 1 << _attempt.clamp(0, 5);
    _attempt++;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: secs > 30 ? 30 : secs), () {
      if (_watched.isNotEmpty) _ensureSocket();
    });
  }

  void _sendFrame(ClientMessage m) {
    final s = _socket;
    if (s == null) return; // sent again on (re)connect for watches
    try {
      s.sink.add(jsonEncode(m.toJson()));
    } on Object {
      // The socket is closing; _dropped will reconnect.
    }
  }

  /// Closes the socket for good, e.g. on sign-out.
  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    await _sub?.cancel();
    await _socket?.sink.close();
    _socket = null;
    await _messages.close();
    _http.close();
  }
}

extension on Stream<ServerMessage> {
  Stream<T> whereType<T>() => where((m) => m is T).cast<T>();
}
