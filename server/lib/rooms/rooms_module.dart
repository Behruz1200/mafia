import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../realtime/socket_handler.dart';
import '../realtime/socket_hub.dart';
import '../src/module.dart';
import 'jwt.dart';
import 'match_recorder.dart';
import 'ports.dart';
import 'room_error.dart';
import 'room_service.dart';

/// Stream 2 (rooms and game server): the room REST routes and the realtime
/// socket, both backed by one [RoomService].
class RoomsModule extends ServerModule {
  RoomsModule({required this.service, required this.hub, required this.tokens});

  /// Wires everything from environment variables:
  ///
  /// - `JWT_SECRET`: checks access tokens. Without it nobody can sign in.
  /// - `DEV_AUTH=true`: also accept `dev:<userId>` tokens (local only).
  /// - `DATABASE_URL`: keep match records in PostgreSQL; else in memory.
  /// - `QUICK_MATCH_STAKE`: coins per quick-match game for players who can
  ///   stake (default 100; 0 makes quick match free for everyone).
  ///
  /// Other streams pass their real [engine], [wallet] and [players] here.
  factory RoomsModule.fromEnvironment({
    Map<String, String>? env,
    GameEngine engine = const MafiaEngine(),
    WalletSettlement wallet = const FreeMatchesOnlyWallet(),
    PlayerDirectory players = const AnonymousPlayers(),
    RegionPolicy? regions,
    TokenVerifier? tokens,
  }) {
    final e = env ?? Platform.environment;
    final secret = e['JWT_SECRET'];
    final jwt = secret == null || secret.isEmpty
        ? const DenyAllTokens()
        : JwtTokenVerifier(secret);
    final verifier =
        tokens ??
        (e['DEV_AUTH'] == 'true'
            ? _Either(jwt, const DevTokenVerifier())
            : jwt);
    final db = e['DATABASE_URL'];
    final hub = SocketHub();
    return RoomsModule(
      hub: hub,
      tokens: verifier,
      service: RoomService(
        engine: engine,
        wallet: wallet,
        hub: hub,
        players: players,
        regions: regions,
        config: RoomsConfig(
          quickMatchStake: int.tryParse(e['QUICK_MATCH_STAKE'] ?? '') ?? 100,
        ),
        recorder: db == null || db.isEmpty
            ? InMemoryMatchRecorder()
            : PostgresMatchRecorder(Pool.withUrl(db)),
      ),
    );
  }

  final RoomService service;
  final SocketHub hub;
  final TokenVerifier tokens;

  /// The realtime socket handler for `ApiRoutes.socket`.
  Handler get socket => socketHandler(hub: hub, tokens: tokens, rooms: service);

  @override
  void mount(Router r) {
    r.post(
      ApiRoutes.rooms,
      _guard((u, req) async {
        final body = CreateRoomRequest.fromJson(await _body(req));
        return service.create(u, body.settings);
      }),
    );
    r.post(
      ApiRoutes.joinRoom,
      _guard((u, req) async {
        final body = JoinRoomRequest.fromJson(await _body(req));
        return service.join(u, body.inviteCode);
      }),
    );
    r.post(ApiRoutes.quickMatch, _guard((u, _) => service.quickMatch(u)));
    r.get(
      '/v1/rooms/<roomId>',
      (Request req, String roomId) =>
          _guard((u, _) async => service.get(u, roomId))(req),
    );
    r.post(
      '/v1/rooms/<roomId>/leave',
      (Request req, String roomId) => _guard((u, _) async {
        await service.leave(u, roomId);
        return null;
      })(req),
    );
  }

  /// Signed-in user from the accounts middleware (`context['userId']`) if
  /// it ran, else from the bearer token.
  UserId? _user(Request req) {
    final fromContext = req.context['userId'];
    if (fromContext is String && fromContext.isNotEmpty) return fromContext;
    final h = req.headers['authorization'];
    if (h == null || !h.startsWith('Bearer ')) return null;
    return tokens.verify(h.substring(7));
  }

  Handler _guard(Future<Room?> Function(UserId u, Request req) f) =>
      (Request req) async {
        final u = _user(req);
        if (u == null) return _error(RoomError.unauthorized);
        try {
          final room = await f(u, req);
          return room == null ? json({'ok': true}) : json(room.toJson());
        } on RoomError catch (e) {
          return _error(e);
        } on FormatException {
          return _error(RoomError.badRequest);
        } on TypeError {
          return _error(RoomError.badRequest);
        }
      };

  static Future<Json> _body(Request req) async {
    final text = await req.readAsString();
    if (text.length > 16 * 1024) throw const FormatException('too big');
    final v = jsonDecode(text);
    if (v is! Map<String, Object?>) throw const FormatException('not object');
    return v;
  }

  static Response _error(RoomError e) => json(
    ApiError(code: e.code, message: e.message).toJson(),
    status: e.status,
  );
}

class _Either implements TokenVerifier {
  const _Either(this.a, this.b);
  final TokenVerifier a;
  final TokenVerifier b;
  @override
  UserId? verify(String token) => a.verify(token) ?? b.verify(token);
}
