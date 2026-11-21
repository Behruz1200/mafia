import 'dart:convert';

import 'package:crypto/crypto.dart';

/// API key and secret for our self-hosted LiveKit, plus where to reach it.
class LiveKitCredentials {
  const LiveKitCredentials({
    required this.publicUrl,
    required this.apiUrl,
    required this.apiKey,
    required this.apiSecret,
  });

  /// What the app connects to, e.g. `wss://video.example.uz`.
  final String publicUrl;

  /// What this server calls for room admin, e.g. `http://127.0.0.1:7880`
  /// when LiveKit runs on the same machine.
  final Uri apiUrl;
  final String apiKey;
  final String apiSecret;

  /// Reads `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` and the
  /// optional `LIVEKIT_API_URL`. Returns null when any required one is
  /// missing, so the server still starts without video set up.
  static LiveKitCredentials? fromEnvironment(Map<String, String> env) {
    final url = env['LIVEKIT_URL'];
    final key = env['LIVEKIT_API_KEY'];
    final secret = env['LIVEKIT_API_SECRET'];
    if (url == null || key == null || secret == null) return null;
    if (url.isEmpty || key.isEmpty || secret.isEmpty) return null;
    return LiveKitCredentials(
      publicUrl: url,
      apiUrl: Uri.parse(env['LIVEKIT_API_URL'] ?? httpUrlFor(url)),
      apiKey: key,
      apiSecret: secret,
    );
  }

  /// `wss://x` -> `https://x`, `ws://x` -> `http://x`.
  static String httpUrlFor(String wsUrl) {
    if (wsUrl.startsWith('wss://')) return 'https://${wsUrl.substring(6)}';
    if (wsUrl.startsWith('ws://')) return 'http://${wsUrl.substring(5)}';
    return wsUrl;
  }
}

/// The `video` grant inside a LiveKit access token.
/// See https://docs.livekit.io/home/get-started/authentication/
class VideoGrant {
  const VideoGrant({
    this.room,
    this.roomJoin = false,
    this.roomAdmin = false,
    this.roomCreate = false,
    this.roomList = false,
    this.canPublish = false,
    this.canSubscribe = false,
    this.canPublishData = false,
    this.canPublishSources = const [],
  });

  final String? room;
  final bool roomJoin;
  final bool roomAdmin;
  final bool roomCreate;
  final bool roomList;
  final bool canPublish;
  final bool canSubscribe;
  final bool canPublishData;

  /// e.g. `['camera', 'microphone']`. Empty means any source.
  final List<String> canPublishSources;

  Map<String, Object?> toJson() => {
    if (room != null) 'room': room,
    if (roomJoin) 'roomJoin': true,
    if (roomAdmin) 'roomAdmin': true,
    if (roomCreate) 'roomCreate': true,
    if (roomList) 'roomList': true,
    // Publish and subscribe are always written out: a missing value means
    // "allowed" to LiveKit, and we want explicit denials.
    if (roomJoin) 'canPublish': canPublish,
    if (roomJoin) 'canSubscribe': canSubscribe,
    if (roomJoin) 'canPublishData': canPublishData,
    if (canPublishSources.isNotEmpty) 'canPublishSources': canPublishSources,
  };
}

/// Signs LiveKit access tokens (HS256 JWTs) with our API secret.
class LiveKitTokenSigner {
  LiveKitTokenSigner(this.credentials, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LiveKitCredentials credentials;
  final DateTime Function() _clock;

  /// A token for [identity]. [ttl] only limits how long the token can be
  /// used to connect; LiveKit refreshes it for clients already connected.
  String sign({
    required VideoGrant grant,
    required Duration ttl,
    String? identity,
    String? name,
    String? metadata,
  }) {
    final now = _clock().toUtc().millisecondsSinceEpoch ~/ 1000;
    final claims = <String, Object?>{
      'iss': credentials.apiKey,
      'sub': ?identity,
      'name': ?name,
      'metadata': ?metadata,
      'nbf': now - 10, // small allowance for clock skew
      'exp': now + ttl.inSeconds,
      'video': grant.toJson(),
    };
    return encodeHs256(claims, credentials.apiSecret);
  }

  /// A short-lived token for this server's own room admin calls.
  String adminToken(String room) => sign(
    grant: VideoGrant(room: room, roomAdmin: true, roomCreate: true),
    ttl: const Duration(minutes: 1),
  );
}

String encodeHs256(Map<String, Object?> claims, String secret) {
  String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
  final header = b64(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
  final payload = b64(utf8.encode(jsonEncode(claims)));
  final input = '$header.$payload';
  final sig = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(input));
  return '$input.${b64(sig.bytes)}';
}
