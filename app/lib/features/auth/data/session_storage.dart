import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the app keeps the session between launches.
abstract interface class SessionStorage {
  Future<AuthSession?> read();
  Future<void> write(AuthSession? session);
}

/// Keychain on iOS, encrypted storage on Android.
class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'mafia.session';
  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null ? null : AuthSession.fromJson(jsonDecode(raw) as Json);
    } on Object {
      return null; // unreadable (e.g. restored backup): sign in again
    }
  }

  @override
  Future<void> write(AuthSession? session) => session == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: jsonEncode(session.toJson()));
}

/// For tests.
class MemorySessionStorage implements SessionStorage {
  MemorySessionStorage([this.session]);
  AuthSession? session;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession? s) async => session = s;
}
