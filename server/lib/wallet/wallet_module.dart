import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../src/module.dart';
import 'app_store.dart';
import 'postgres_wallet.dart';
import 'purchases.dart';
import 'wallet_config.dart';

export 'app_store.dart' show AppStoreTransaction, AppStoreVerifier;
export 'postgres_wallet.dart';
export 'purchases.dart';
export 'wallet_config.dart';

/// The wallet's parts, built once per server process.
class WalletServices {
  WalletServices({
    required this.config,
    required this.wallet,
    required this.purchases,
  });

  factory WalletServices.connect(
    WalletConfig config, {
    SessionExecutor? db,
    AppStoreVerifier? appStore,
  }) {
    final wallet = PostgresWallet(
      db ?? Pool.withUrl(config.databaseUrl),
      houseCutPercent: config.houseCutPercent,
    );
    final apple = config.apple;
    return WalletServices(
      config: config,
      wallet: wallet,
      purchases: Purchases(
        wallet: wallet,
        config: config,
        appStore: appStore ?? (apple == null ? null : AppStoreServerApi(apple)),
      ),
    );
  }

  final WalletConfig config;

  /// Also the real [WalletSettlement] for the rooms code.
  final PostgresWallet wallet;
  final Purchases purchases;

  static WalletServices? _instance;
  static bool _loaded = false;

  /// The process-wide wallet, from environment variables. Null when there
  /// is no `DATABASE_URL` (local runs and tests). The rooms code can use
  /// `WalletServices.instance?.wallet ?? InMemoryWalletSettlement()`.
  static WalletServices? get instance {
    if (!_loaded) {
      _loaded = true;
      final config = WalletConfig.fromEnvironment();
      if (config != null) _instance = WalletServices.connect(config);
    }
    return _instance;
  }
}

/// The accounts stream's auth middleware puts the signed-in user id here
/// (`server/lib/auth/auth_guard.dart`, `userIdKey`).
const _userIdKey = 'userId';

/// Stream 4 (coins). Balance and history, coin packs, App Store purchase
/// verification (Google Play later), and refund clawbacks from App Store
/// notifications. The real `WalletSettlement` is [WalletServices.wallet].
class WalletModule extends ServerModule {
  WalletModule({WalletServices? services})
    : _services = services ?? WalletServices.instance;

  final WalletServices? _services;

  @override
  void mount(Router r) {
    final s = _services;
    if (s == null) {
      for (final path in [
        ApiRoutes.wallet,
        ApiRoutes.ledger,
        ApiRoutes.coinPacks,
      ]) {
        r.get(path, notImplemented);
      }
      r.post(ApiRoutes.purchases, notImplemented);
      r.post(ApiRoutes.appStoreNotifications, notImplemented);
      r.post(ApiRoutes.playNotifications, notImplemented);
      return;
    }

    r.get(
      ApiRoutes.wallet,
      _signedIn((req, user) async {
        return json((await s.wallet.balance(user)).toJson());
      }),
    );

    r.get(
      ApiRoutes.ledger,
      _signedIn((req, user) async {
        final limit =
            int.tryParse(req.url.queryParameters['limit'] ?? '') ?? 50;
        final rows = await s.wallet.history(user, limit: limit);
        return json([for (final e in rows) e.toJson()]);
      }),
    );

    r.get(
      ApiRoutes.coinPacks,
      _signedIn((req, user) async {
        return json([for (final p in s.config.packs) p.toJson()]);
      }),
    );

    r.post(
      ApiRoutes.purchases,
      _signedIn((req, user) async {
        final PurchaseRequest body;
        try {
          body = PurchaseRequest.fromJson(
            jsonDecode(await req.readAsString()) as Json,
          );
        } on Object {
          return _error('bad_request', 400);
        }
        try {
          final balance = await s.purchases.verifyAndCredit(user, body);
          return json(balance.toJson());
        } on PurchaseRejected catch (e) {
          return _error(e.code, e.status, e.message);
        }
      }),
    );

    // Called by Apple, not by the app: no user session.
    r.post(ApiRoutes.appStoreNotifications, (Request req) async {
      try {
        final outcome = await s.purchases.handleAppStoreNotification(
          await req.readAsString(),
        );
        return json({'ok': true, 'outcome': outcome});
      } on PurchaseRejected catch (e) {
        return _error(e.code, e.status, e.message);
      }
    });

    r.post(ApiRoutes.playNotifications, notImplemented);
  }

  static Handler _signedIn(
    Future<Response> Function(Request req, UserId user) handler,
  ) {
    return (Request req) {
      final user = req.context[_userIdKey];
      if (user is! String || user.isEmpty) {
        return _error('unauthorized', 401);
      }
      return handler(req, user);
    };
  }

  static Response _error(String code, int status, [String? message]) => json(
    ApiError(code: code, message: message).toJson(),
    status: status,
  );
}
