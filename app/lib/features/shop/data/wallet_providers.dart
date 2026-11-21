import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/providers.dart';
import 'http_wallet_repository.dart';
import 'store_billing.dart';

/// The phone's store. Null with fakes, and on Android until Google Play
/// purchases land on the server.
final storeBillingProvider = Provider<StoreBilling?>((ref) {
  if (AppConfig.useFakes || defaultTargetPlatform != TargetPlatform.iOS) {
    return null;
  }
  return InAppPurchaseBilling(
    applicationUserName: ref
        .read(authRepositoryProvider)
        .currentSession
        ?.userId,
  );
});

/// The real wallet; `core/providers.dart` uses it when fakes are off.
WalletRepository createWalletRepository(Ref ref) {
  final auth = ref.watch(authRepositoryProvider);
  final repo = HttpWalletRepository(
    baseUrl: AppConfig.apiBaseUrl,
    accessToken: () => auth.currentSession?.accessToken,
    billing: ref.watch(storeBillingProvider) ?? const NoStoreBilling(),
  );
  ref.onDispose(repo.dispose);
  return repo;
}

/// Store prices for the shop, by product id. The key is the product ids
/// joined with commas. Empty without a store.
final storePricesProvider = FutureProvider.family<Map<String, String>, String>((
  ref,
  ids,
) async {
  final billing = ref.watch(storeBillingProvider);
  if (ids.isEmpty || billing == null || !await billing.isAvailable()) {
    return const {};
  }
  return billing.prices(ids.split(','));
});

/// Whether the shop can sell on this device.
final canBuyProvider = FutureProvider<bool>((ref) async {
  if (AppConfig.useFakes) return true; // fake wallet "buys" instantly
  final billing = ref.watch(storeBillingProvider);
  return billing != null && await billing.isAvailable();
});
