import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// A purchase the store says went through. The server still has to verify
/// it before any coins appear.
class StorePurchase {
  const StorePurchase({
    required this.store,
    required this.productId,
    required this.transactionId,
    required this.verificationData,
    this.raw,
  });

  final Store store;
  final String productId;
  final String transactionId;
  final String verificationData;

  /// The plugin's own object, needed to finish the transaction.
  final Object? raw;

  PurchaseRequest toRequest() => PurchaseRequest(
    store: store,
    productId: productId,
    transactionId: transactionId,
    verificationData: verificationData,
  );
}

/// The player closed the store sheet.
class PurchaseCancelled implements Exception {
  const PurchaseCancelled();
}

/// The store refused or failed.
class StoreError implements Exception {
  const StoreError(this.message);
  final String message;
  @override
  String toString() => 'StoreError($message)';
}

/// The phone's app store, behind an interface so the wallet code can be
/// tested without one.
abstract interface class StoreBilling {
  /// Whether this device can buy at all (signed in to the store, not
  /// restricted by parental controls, a supported platform).
  Future<bool> isAvailable();

  /// Localised prices by product id, e.g. `{'coins_500': '25 000 so'm'}`.
  Future<Map<String, String>> prices(List<String> productIds);

  /// Shows the store sheet. Completes when the store reports the purchase.
  Future<StorePurchase> buy(String productId);

  /// Tells the store we delivered the coins. Until then it redelivers the
  /// purchase on every launch, so coins are never lost to a crash.
  Future<void> finish(StorePurchase purchase);

  /// Purchases that went through earlier but were never finished.
  Stream<StorePurchase> get unfinished;

  void dispose();
}

/// [StoreBilling] over the `in_app_purchase` plugin. Apple first; Google
/// Play purchases are sent too, but the server turns them down until Play
/// support lands.
class InAppPurchaseBilling implements StoreBilling {
  InAppPurchaseBilling({InAppPurchase? iap, this.applicationUserName})
    : _iap = iap ?? InAppPurchase.instance {
    _sub = _iap.purchaseStream.listen(_onUpdates);
  }

  final InAppPurchase _iap;

  /// Sent to the store with each purchase so it can spot fraud.
  final String? applicationUserName;
  late final StreamSubscription<List<PurchaseDetails>> _sub;
  final _waiting = <String, Completer<StorePurchase>>{};
  final _unfinished = StreamController<StorePurchase>.broadcast();
  final _products = <String, ProductDetails>{};

  @override
  Stream<StorePurchase> get unfinished => _unfinished.stream;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  Future<void> _load(List<String> ids) async {
    final missing = ids.where((id) => !_products.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    final res = await _iap.queryProductDetails(missing);
    for (final p in res.productDetails) {
      _products[p.id] = p;
    }
  }

  @override
  Future<Map<String, String>> prices(List<String> productIds) async {
    await _load(productIds);
    return {
      for (final id in productIds)
        if (_products[id] case final p?) id: p.price,
    };
  }

  @override
  Future<StorePurchase> buy(String productId) async {
    await _load([productId]);
    final product = _products[productId];
    if (product == null) throw StoreError('Unknown product $productId');
    if (_waiting.containsKey(productId)) {
      return _waiting[productId]!.future;
    }
    final done = _waiting[productId] = Completer<StorePurchase>();
    try {
      final started = await _iap.buyConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product,
          applicationUserName: applicationUserName,
        ),
      );
      if (!started) throw const StoreError('Purchase did not start');
    } on Object catch (e) {
      _waiting.remove(productId);
      if (e is StoreError) rethrow;
      throw StoreError('$e');
    }
    return done.future;
  }

  void _onUpdates(List<PurchaseDetails> updates) {
    for (final d in updates) {
      final waiter = _waiting[d.productID];
      switch (d.status) {
        case PurchaseStatus.pending:
          break; // e.g. Ask to Buy; the store reports again later
        case PurchaseStatus.canceled:
          _waiting.remove(d.productID);
          waiter?.completeError(const PurchaseCancelled());
          if (d.pendingCompletePurchase) _iap.completePurchase(d);
        case PurchaseStatus.error:
          _waiting.remove(d.productID);
          waiter?.completeError(StoreError(d.error?.message ?? 'error'));
          if (d.pendingCompletePurchase) _iap.completePurchase(d);
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          final p = _toPurchase(d);
          if (p == null) continue;
          if (waiter != null) {
            _waiting.remove(d.productID);
            waiter.complete(p);
          } else {
            _unfinished.add(p);
          }
      }
    }
  }

  StorePurchase? _toPurchase(PurchaseDetails d) {
    final id = d.purchaseID;
    if (id == null) return null;
    return StorePurchase(
      store: d.verificationData.source == 'google_play'
          ? Store.playStore
          : Store.appStore,
      productId: d.productID,
      transactionId: id,
      verificationData: d.verificationData.serverVerificationData,
      raw: d,
    );
  }

  @override
  Future<void> finish(StorePurchase purchase) async {
    final raw = purchase.raw;
    if (raw is PurchaseDetails && raw.pendingCompletePurchase) {
      await _iap.completePurchase(raw);
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    _unfinished.close();
  }
}

/// No store on this device (Android until Play support, or fakes).
class NoStoreBilling implements StoreBilling {
  const NoStoreBilling();
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<Map<String, String>> prices(List<String> productIds) async => const {};
  @override
  Future<StorePurchase> buy(String productId) =>
      Future.error(const StoreError('No store on this device'));
  @override
  Future<void> finish(StorePurchase purchase) async {}
  @override
  Stream<StorePurchase> get unfinished => const Stream.empty();
  @override
  void dispose() {}
}
