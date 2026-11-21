import 'dart:io';

import 'package:contracts/contracts.dart';

/// Server settings, read from environment variables (see `.env.example`).
/// Nothing secret is ever hard-coded or committed.
class ServerConfig {
  const ServerConfig({
    required this.port,
    required this.databaseUrl,
    required this.jwtSecret,
    required this.livekitUrl,
    required this.livekitApiKey,
    required this.livekitApiSecret,
    required this.regions,
    this.houseCutPercent = 10,
  });

  final int port;

  /// `postgres://user:pass@host:5432/db`
  final String databaseUrl;
  final String jwtSecret;

  /// Public URL the app connects to, e.g. `wss://video.example.uz`.
  final String livekitUrl;
  final String livekitApiKey;
  final String livekitApiSecret;
  final RegionPolicy regions;
  final int houseCutPercent;

  factory ServerConfig.fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    String need(String k) =>
        e[k] ?? (throw StateError('Missing environment variable $k'));
    List<String> list(String k, String fallback) =>
        (e[k] ?? fallback).split(',').map((s) => s.trim()).toList();

    return ServerConfig(
      port: int.parse(e['PORT'] ?? '8080'),
      databaseUrl: need('DATABASE_URL'),
      jwtSecret: need('JWT_SECRET'),
      livekitUrl: need('LIVEKIT_URL'),
      livekitApiKey: need('LIVEKIT_API_KEY'),
      livekitApiSecret: need('LIVEKIT_API_SECRET'),
      houseCutPercent: int.parse(e['HOUSE_CUT_PERCENT'] ?? '10'),
      regions: RegionPolicy.fromJson({
        'launchCountries': list('LAUNCH_COUNTRIES', 'UZ'),
        'stakeCountries': list('STAKE_COUNTRIES', 'UZ'),
      }),
    );
  }
}
