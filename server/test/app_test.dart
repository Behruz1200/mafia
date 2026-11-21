import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:server/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final app = buildApp();
  Future<Response> get(String path) =>
      Future.value(app(Request('GET', Uri.parse('http://localhost$path'))));

  test('health check', () async {
    final res = await get(ApiRoutes.health);
    expect(res.statusCode, 200);
    expect(jsonDecode(await res.readAsString()), {'ok': true});
  });

  test('stream routes exist and say not implemented yet', () async {
    final res = await get(ApiRoutes.wallet);
    expect(res.statusCode, 501);
  });

  test('config reads Uzbekistan as the default market', () {
    final c = ServerConfig.fromEnvironment({
      'DATABASE_URL': 'postgres://x',
      'JWT_SECRET': 's',
      'LIVEKIT_URL': 'wss://v',
      'LIVEKIT_API_KEY': 'k',
      'LIVEKIT_API_SECRET': 's',
    });
    expect(c.regions.allowsApp('UZ'), isTrue);
    expect(c.regions.allowsStakes(country: 'UZ', isAdult: true), isTrue);
  });
}
