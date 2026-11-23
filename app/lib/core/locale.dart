import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';

import 'config.dart';

/// The languages the app speaks, Uzbek first (it is also the fallback when
/// the phone's language is not one of ours).
const supportedAppLocales = [Locale('uz'), Locale('ru'), Locale('en')];

/// Each language's name in itself, for the language picker.
const appLanguageNames = {'uz': 'Oʻzbekcha', 'ru': 'Русский', 'en': 'English'};

/// Where the player's chosen language is kept across launches.
abstract interface class LocaleStore {
  Future<String?> read();
  Future<void> write(String? languageCode);
}

class SecureLocaleStore implements LocaleStore {
  const SecureLocaleStore([this._storage = const FlutterSecureStorage()]);

  static const _key = 'mafia.locale';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String? languageCode) async {
    try {
      languageCode == null
          ? await _storage.delete(key: _key)
          : await _storage.write(key: _key, value: languageCode);
    } on Object {
      // Only a convenience: the app still works in the phone's language.
    }
  }
}

/// For fakes and tests.
class MemoryLocaleStore implements LocaleStore {
  MemoryLocaleStore([this.languageCode]);
  String? languageCode;

  @override
  Future<String?> read() async => languageCode;

  @override
  Future<void> write(String? languageCode) async =>
      this.languageCode = languageCode;
}

final localeStoreProvider = Provider<LocaleStore>(
  (ref) => AppConfig.useFakes ? MemoryLocaleStore() : const SecureLocaleStore(),
);

/// The language the player picked, or null to follow the phone.
final appLocaleProvider = NotifierProvider<AppLocale, Locale?>(AppLocale.new);

class AppLocale extends Notifier<Locale?> {
  var _picked = false;

  @override
  Locale? build() {
    unawaited(_load());
    return null;
  }

  Future<void> _load() async {
    final code = await ref.read(localeStoreProvider).read();
    // A pick made while loading wins over the saved one.
    if (_picked || code == null) return;
    if (supportedAppLocales.any((l) => l.languageCode == code)) {
      state = Locale(code);
    }
  }

  /// Switches the whole app to [locale] at once and remembers it.
  Future<void> set(Locale locale) async {
    _picked = true;
    state = locale;
    await ref.read(localeStoreProvider).write(locale.languageCode);
  }
}
