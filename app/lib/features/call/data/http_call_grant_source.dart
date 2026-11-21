import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;

import '../call_session.dart';

/// Asks the game server for a call grant (`POST /v1/rooms/<id>/call`).
class HttpCallGrantSource implements CallGrantSource {
  HttpCallGrantSource({
    required this.baseUrl,
    required this.accessToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String? Function() accessToken;
  final http.Client _client;

  @override
  Future<CallGrant> fetch(RoomId roomId, CallChannel channel) async {
    final token = accessToken();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiRoutes.callGrant(roomId)}'),
      headers: {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
      body: jsonEncode(CallGrantRequest(channel: channel).toJson()),
    );
    final body = jsonDecode(res.body) as Map<String, Object?>;
    if (res.statusCode != 200) throw CallGrantRefused(ApiError.fromJson(body));
    return CallGrant.fromJson(body);
  }
}

class CallGrantRefused implements Exception {
  const CallGrantRefused(this.error);
  final ApiError error;
  @override
  String toString() => 'CallGrantRefused(${error.code})';
}

/// For `USE_FAKES=true`: a grant that lets everyone talk, so the call view
/// works with no server.
class FakeCallGrantSource implements CallGrantSource {
  @override
  Future<CallGrant> fetch(RoomId roomId, CallChannel channel) async =>
      CallGrant(
        serverUrl: 'wss://fake',
        token: 'fake',
        livekitRoom: 'fake_${roomId}_${channel.name}',
        channel: channel,
        canPublish: true,
        expiresAt: DateTime.utc(2100),
      );
}
