import 'dart:io';

import 'package:contracts/contracts.dart';

/// The coin packs the shop sells. The product ids must match the
/// consumable products created in App Store Connect (and later Google Play).
/// Prices are set in the stores, never here.
const defaultCoinPacks = [
  CoinPack(productId: 'coins_100', coins: 100),
  CoinPack(productId: 'coins_500', coins: 500, bonusCoins: 50),
  CoinPack(productId: 'coins_1200', coins: 1200, bonusCoins: 200),
  CoinPack(productId: 'coins_3000', coins: 3000, bonusCoins: 750),
];

/// The stake the welcome gift is sized for. Rooms choose their own stake;
/// this is only the planning number.
const typicalStake = 100;

/// Free coins for a new player: enough for 5 games at [typicalStake]
/// (Behruz, 2026-11-21).
const defaultWelcomeCoins = 5 * typicalStake;

/// Whether purchases made with Apple's sandbox (TestFlight, App Review,
/// Xcode builds) credit coins on this server. Sandbox purchases cost
/// nothing, so a production server should only accept them while the app
/// is in review or for test accounts.
enum SandboxPolicy { allow, deny }

/// App Store Server API credentials, from App Store Connect → Users and
/// Access → Integrations → In-App Purchase. Never committed.
class AppleConfig {
  const AppleConfig({
    required this.bundleId,
    required this.issuerId,
    required this.keyId,
    required this.privateKeyPem,
    this.sandbox = SandboxPolicy.allow,
  });

  final String bundleId;
  final String issuerId;
  final String keyId;

  /// Contents of the downloaded `SubscriptionKey_<keyId>.p8` file.
  final String privateKeyPem;
  final SandboxPolicy sandbox;
}

/// Wallet settings, read from environment variables:
///
/// - `DATABASE_URL` (shared with the rest of the server)
/// - `HOUSE_CUT_PERCENT` (shared, default 10)
/// - `WELCOME_COINS`: free coins every new player gets once (default
///   [defaultWelcomeCoins]; 0 turns it off)
/// - `COIN_PACKS`, optional: `coins_100:100:0,coins_500:500:50`
///   (product id : coins : bonus coins)
/// - `APPLE_BUNDLE_ID`, `APPLE_ISSUER_ID`, `APPLE_KEY_ID` and
///   `APPLE_PRIVATE_KEY_PATH` (path to the .p8 file); purchases answer
///   `store_not_configured` until all four are set
/// - `APPLE_SANDBOX`: `allow` (default) or `deny`
class WalletConfig {
  const WalletConfig({
    required this.databaseUrl,
    this.houseCutPercent = 10,
    this.welcomeCoins = defaultWelcomeCoins,
    this.packs = defaultCoinPacks,
    this.apple,
  });

  final String databaseUrl;
  final int houseCutPercent;
  final int welcomeCoins;
  final List<CoinPack> packs;
  final AppleConfig? apple;

  CoinPack? packFor(String productId) {
    for (final p in packs) {
      if (p.productId == productId) return p;
    }
    return null;
  }

  /// Null when there is no `DATABASE_URL`, which keeps the wallet routes
  /// answering "not implemented" in local runs and tests without a database.
  static WalletConfig? fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    final db = e['DATABASE_URL'];
    if (db == null || db.isEmpty) return null;
    final cut = int.parse(e['HOUSE_CUT_PERCENT'] ?? '10');
    if (cut < 0 || cut > 100) {
      throw StateError('HOUSE_CUT_PERCENT must be between 0 and 100');
    }
    final welcome = int.parse(e['WELCOME_COINS'] ?? '$defaultWelcomeCoins');
    if (welcome < 0) throw StateError('WELCOME_COINS must not be negative');
    return WalletConfig(
      databaseUrl: db,
      houseCutPercent: cut,
      welcomeCoins: welcome,
      packs: parsePacks(e['COIN_PACKS']) ?? defaultCoinPacks,
      apple: _apple(e),
    );
  }

  static AppleConfig? _apple(Map<String, String> e) {
    final bundle = e['APPLE_BUNDLE_ID'];
    final issuer = e['APPLE_ISSUER_ID'];
    final keyId = e['APPLE_KEY_ID'];
    final keyPath = e['APPLE_PRIVATE_KEY_PATH'];
    if ([bundle, issuer, keyId, keyPath].any((v) => v == null || v.isEmpty)) {
      return null;
    }
    return AppleConfig(
      bundleId: bundle!,
      issuerId: issuer!,
      keyId: keyId!,
      privateKeyPem: File(keyPath!).readAsStringSync(),
      sandbox: e['APPLE_SANDBOX'] == 'deny'
          ? SandboxPolicy.deny
          : SandboxPolicy.allow,
    );
  }

  /// Parses `id:coins:bonus,id:coins:bonus`. Returns null for null/empty.
  static List<CoinPack>? parsePacks(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return [
      for (final item in raw.split(','))
        if (item.trim().isNotEmpty) _pack(item.trim()),
    ];
  }

  static CoinPack _pack(String item) {
    final parts = item.split(':');
    if (parts.length < 2 || parts.length > 3) {
      throw FormatException('Bad COIN_PACKS entry "$item"');
    }
    final coins = int.parse(parts[1]);
    final bonus = parts.length == 3 ? int.parse(parts[2]) : 0;
    if (coins <= 0 || bonus < 0) {
      throw FormatException('Bad coin amounts in COIN_PACKS entry "$item"');
    }
    return CoinPack(productId: parts[0], coins: coins, bonusCoins: bonus);
  }
}
