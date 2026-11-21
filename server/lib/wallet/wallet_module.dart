import 'package:contracts/contracts.dart';
import 'package:shelf_router/shelf_router.dart';

import '../src/module.dart';

/// Stream 4 (coins). Append-only ledger in PostgreSQL, the real
/// `WalletSettlement`, coin packs, App Store purchase verification first
/// (Google Play later), refund clawback from store notifications.
class WalletModule extends ServerModule {
  @override
  void mount(Router r) {
    r.get(ApiRoutes.wallet, notImplemented);
    r.get(ApiRoutes.ledger, notImplemented);
    r.get(ApiRoutes.coinPacks, notImplemented);
    r.post(ApiRoutes.purchases, notImplemented);
    r.post(ApiRoutes.appStoreNotifications, notImplemented);
    r.post(ApiRoutes.playNotifications, notImplemented);
  }
}
