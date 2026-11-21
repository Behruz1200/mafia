import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../src/module.dart';
import 'call_service.dart';
import 'livekit_rooms.dart';
import 'livekit_token.dart';

export 'call_policy.dart';
export 'call_service.dart';
export 'livekit_rooms.dart';
export 'livekit_token.dart';

/// Where the auth middleware (stream 5) puts the signed-in user's id in
/// `Request.context`.
const authUserIdContextKey = 'userId';

UserId? _userIdFromContext(Request r) =>
    r.context[authUserIdContextKey] as String?;

/// Stream 3 (video). Mints LiveKit tokens (`CallGrant`) for the self-hosted
/// LiveKit server. [CallService.syncPhase] mutes and unmutes players when
/// the phase changes; stream 2 calls it from the match loop.
///
/// `POST /v1/rooms/<roomId>/call` with a `CallGrantRequest` returns a
/// `CallGrant`. Until LiveKit is configured and stream 2 provides a
/// [CallRoomDirectory], it answers 501.
class CallModule extends ServerModule {
  CallModule({
    CallService? service,
    this.directory,
    UserId? Function(Request)? userIdOf,
    Map<String, String>? environment,
  }) : service = service ?? _fromEnvironment(environment),
       _userIdOf = userIdOf ?? _userIdFromContext;

  final CallService? service;
  final CallRoomDirectory? directory;
  final UserId? Function(Request) _userIdOf;

  static CallService? _fromEnvironment(Map<String, String>? env) {
    final creds = LiveKitCredentials.fromEnvironment(
      env ?? Platform.environment,
    );
    if (creds == null) return null;
    final signer = LiveKitTokenSigner(creds);
    return CallService(signer: signer, rooms: TwirpLiveKitRooms(signer));
  }

  @override
  void mount(Router r) {
    r.post('/v1/rooms/<roomId>/call', _grant);
  }

  Future<Response> _grant(Request req, String roomId) async {
    final service = this.service;
    final directory = this.directory;
    if (service == null || directory == null) return notImplemented(req);

    final userId = _userIdOf(req);
    if (userId == null) return _error(401, 'unauthorized');

    final CallChannel channel;
    try {
      final body = await req.readAsString();
      channel = body.trim().isEmpty
          ? CallChannel.table
          : CallGrantRequest.fromJson(jsonDecode(body) as Map<String, Object?>)
                .channel;
    } on Object {
      return _error(400, 'bad_request');
    }

    final seat = await directory.seat(roomId, userId);
    if (seat == null) return _error(403, 'not_in_room');
    try {
      return json(service.grant(seat, channel).toJson());
    } on CallDenied catch (e) {
      return _error(403, e.code);
    }
  }

  static Response _error(int status, String code) =>
      json(ApiError(code: code).toJson(), status: status);
}
