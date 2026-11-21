import 'dart:io';

import 'package:contracts/contracts.dart';

/// Accounts settings, from environment variables. See `lib/auth/README.md`.
class AuthConfig {
  const AuthConfig({
    required this.jwtSecret,
    required this.regions,
    this.databaseUrl,
    this.useMemoryStore = false,
    this.smsProvider = 'console',
    this.smsText = 'Mafia: tasdiqlash kodi {code}',
    this.eskizEmail,
    this.eskizPassword,
    this.eskizFrom = '4546',
    this.appleAudiences = const {},
    this.testPhones = const {},
    this.accessTtl = const Duration(minutes: 15),
    this.refreshTtl = const Duration(days: 60),
  });

  final String jwtSecret;
  final RegionPolicy regions;
  final String? databaseUrl;

  /// `AUTH_STORE=memory`: no database, for local runs only.
  final bool useMemoryStore;

  /// `console` (prints codes to the log, development) or `eskiz`.
  final String smsProvider;

  /// SMS text; `{code}` is replaced. Must match the Eskiz template.
  final String smsText;
  final String? eskizEmail;
  final String? eskizPassword;
  final String eskizFrom;

  /// Bundle ids allowed as the `aud` of Apple identity tokens.
  final Set<String> appleAudiences;

  /// Fixed codes for store reviewers, `+998900000001=123456,...`. No SMS
  /// is sent to these numbers.
  final Map<String, String> testPhones;
  final Duration accessTtl;
  final Duration refreshTtl;

  factory AuthConfig.fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    List<String> list(String k, [String fallback = '']) => (e[k] ?? fallback)
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final secret = e['JWT_SECRET'] ?? '';
    if (secret.length < 32) {
      throw StateError('JWT_SECRET must be set to at least 32 characters');
    }
    return AuthConfig(
      jwtSecret: secret,
      databaseUrl: e['DATABASE_URL'],
      useMemoryStore: e['AUTH_STORE'] == 'memory',
      regions: RegionPolicy.fromJson({
        'launchCountries': list('LAUNCH_COUNTRIES', 'UZ'),
        'stakeCountries': list('STAKE_COUNTRIES', 'UZ'),
      }),
      smsProvider: e['SMS_PROVIDER'] ?? 'console',
      smsText: e['SMS_TEXT'] ?? 'Mafia: tasdiqlash kodi {code}',
      eskizEmail: e['ESKIZ_EMAIL'],
      eskizPassword: e['ESKIZ_PASSWORD'],
      eskizFrom: e['ESKIZ_FROM'] ?? '4546',
      appleAudiences: list('APPLE_BUNDLE_IDS').toSet(),
      testPhones: {
        for (final pair in list('AUTH_TEST_PHONES'))
          if (pair.contains('='))
            pair.split('=').first.trim(): pair.split('=').last.trim(),
      },
    );
  }
}
