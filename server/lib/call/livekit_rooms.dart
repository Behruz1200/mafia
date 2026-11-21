import 'dart:convert';

import 'package:http/http.dart' as http;

import 'livekit_token.dart';

/// The few LiveKit room admin calls the game needs. An interface so tests
/// and the phase sync can run without a LiveKit server.
abstract interface class LiveKitRooms {
  /// Identities currently connected to [room]. Empty if the room is gone.
  Future<List<String>> participants(String room);

  /// Changes what [identity] may do without them reconnecting. Revoking
  /// publish makes LiveKit unpublish their camera and mic at once.
  Future<void> setPermission(
    String room,
    String identity, {
    required bool canPublish,
    required bool canSubscribe,
  });

  /// Closes [room] and disconnects everyone in it.
  Future<void> deleteRoom(String room);
}

/// Thrown when LiveKit answers with an error we did not expect.
class LiveKitException implements Exception {
  LiveKitException(this.method, this.status, this.body);
  final String method;
  final int status;
  final String body;
  @override
  String toString() => 'LiveKit $method failed ($status): $body';
}

/// Talks to LiveKit's `RoomService` over its Twirp JSON API.
class TwirpLiveKitRooms implements LiveKitRooms {
  TwirpLiveKitRooms(this.signer, {http.Client? client})
    : _client = client ?? http.Client();

  final LiveKitTokenSigner signer;
  final http.Client _client;

  Future<Map<String, Object?>?> _call(
    String method,
    String room,
    Map<String, Object?> body,
  ) async {
    final base = signer.credentials.apiUrl;
    final uri = base.replace(
      path: '${base.path}/twirp/livekit.RoomService/$method'.replaceAll(
        '//',
        '/',
      ),
    );
    final res = await _client.post(
      uri,
      headers: {
        'authorization': 'Bearer ${signer.adminToken(room)}',
        'content-type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (res.statusCode == 404) return null; // room or participant not there
    if (res.statusCode >= 300) {
      throw LiveKitException(method, res.statusCode, res.body);
    }
    if (res.body.isEmpty) return const {};
    return jsonDecode(res.body) as Map<String, Object?>;
  }

  @override
  Future<List<String>> participants(String room) async {
    final res = await _call('ListParticipants', room, {'room': room});
    final list = (res?['participants'] as List?) ?? const [];
    return [for (final p in list) (p as Map)['identity'] as String];
  }

  @override
  Future<void> setPermission(
    String room,
    String identity, {
    required bool canPublish,
    required bool canSubscribe,
  }) async {
    await _call('UpdateParticipant', room, {
      'room': room,
      'identity': identity,
      'permission': {
        'canPublish': canPublish,
        'canSubscribe': canSubscribe,
        'canPublishData': false,
        'canPublishSources': ['CAMERA', 'MICROPHONE'],
      },
    });
  }

  @override
  Future<void> deleteRoom(String room) async {
    await _call('DeleteRoom', room, {'room': room});
  }

  void close() => _client.close();
}
