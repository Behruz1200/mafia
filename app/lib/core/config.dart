import 'package:flutter/foundation.dart';

/// Build-time settings, passed with `--dart-define` (see docs/DEVELOPING.md).
///
/// Nothing here is secret: the app only knows public URLs. Each environment
/// (local, staging, production on the Uzbek server) is just a different set
/// of defines.
abstract final class AppConfig {
  /// e.g. `https://api.example.uz`. When not given: on the web, the site
  /// the app was loaded from (the web build is served next to the API, see
  /// deploy/production/nginx/mafia-web.conf), elsewhere a local server.
  static String get apiBaseUrl => _apiBaseUrl.isNotEmpty
      ? _apiBaseUrl
      : kIsWeb
      ? Uri.base.origin
      : 'http://localhost:8080';

  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// When true (the default until the server parts land), every repository
  /// is a fake from `package:contracts/testing.dart`, so the app runs with
  /// no backend at all.
  static const useFakes = bool.fromEnvironment('USE_FAKES', defaultValue: true);
}
