import 'dart:convert';

import 'package:contracts/contracts.dart';

import 'app_store.dart';
import 'postgres_wallet.dart';
import 'wallet_config.dart';

/// A purchase the server will not credit. [code] is the `ApiError` code.
class PurchaseRejected implements Exception {
  const PurchaseRejected(this.code, {this.status = 400, this.message});
  final String code;
  final int status;
  final String? message;
  @override
  String toString() => 'PurchaseRejected($code)';
}

/// Turns store purchases into coins, and store refunds into clawbacks.
class Purchases {
  Purchases({required this.wallet, required this.config, this.appStore});

  final PostgresWallet wallet;
  final WalletConfig config;

  /// Null until the Apple credentials are configured.
  final AppStoreVerifier? appStore;

  /// Checks the purchase with the store, then credits it once.
  Future<WalletBalance> verifyAndCredit(
    UserId userId,
    PurchaseRequest req,
  ) async {
    return await switch (req.store) {
      Store.appStore => _appStore(userId, req),
      Store.playStore => throw const PurchaseRejected(
        'store_not_supported',
        status: 501,
        message: 'Google Play purchases are coming later',
      ),
    };
  }

  Future<WalletBalance> _appStore(UserId userId, PurchaseRequest req) async {
    final apple = config.apple;
    final verifier = appStore;
    if (apple == null || verifier == null) {
      throw const PurchaseRejected('store_not_configured', status: 503);
    }
    final AppStoreTransaction? tx;
    try {
      tx = await verifier.transaction(req.transactionId);
    } on AppStoreUnavailable {
      throw const PurchaseRejected('store_unavailable', status: 503);
    }
    if (tx == null) throw const PurchaseRejected('purchase_not_found');
    if (tx.bundleId != apple.bundleId ||
        tx.productId != req.productId ||
        tx.type != 'Consumable') {
      throw const PurchaseRejected('purchase_invalid');
    }
    if (tx.isSandbox && apple.sandbox == SandboxPolicy.deny) {
      throw const PurchaseRejected('purchase_invalid', message: 'sandbox');
    }
    if (tx.isRevoked) throw const PurchaseRejected('purchase_refunded');
    final pack = config.packFor(tx.productId);
    if (pack == null) throw const PurchaseRejected('unknown_product');

    try {
      return await wallet.creditPurchase(
        userId,
        VerifiedPurchase(
          store: Store.appStore,
          transactionId: tx.transactionId,
          originalTransactionId: tx.originalTransactionId,
          productId: tx.productId,
          coins: pack.coins + pack.bonusCoins,
          environment: tx.environment,
          purchasedAt: tx.purchaseDate,
        ),
      );
    } on PurchaseBelongsToAnotherUser {
      throw const PurchaseRejected('purchase_other_account', status: 409);
    }
  }

  /// App Store Server Notifications V2. We only act on refunds and
  /// revocations, and only after Apple confirms them through the API, so a
  /// forged notification can do nothing.
  ///
  /// Returns what happened, for logs and tests.
  Future<String> handleAppStoreNotification(String body) async {
    final String signedPayload;
    final Map<String, Object?> payload;
    try {
      signedPayload =
          (jsonDecode(body) as Map<String, Object?>)['signedPayload']!
              as String;
      payload = unverifiedJwsPayload(signedPayload);
    } on Object {
      throw const PurchaseRejected('bad_notification');
    }
    final type = payload['notificationType'] as String?;
    if (type != 'REFUND' && type != 'REVOKE') return 'ignored:$type';

    final data = payload['data'] as Map<String, Object?>?;
    final signedTx = data?['signedTransactionInfo'] as String?;
    if (signedTx == null) return 'ignored:no-transaction';
    final hintedId = unverifiedJwsPayload(signedTx)['transactionId'] as String?;
    if (hintedId == null) return 'ignored:no-transaction';

    final verifier = appStore;
    if (verifier == null) {
      throw const PurchaseRejected('store_not_configured', status: 503);
    }
    final AppStoreTransaction? tx;
    try {
      tx = await verifier.transaction(hintedId);
    } on AppStoreUnavailable {
      // 5xx makes Apple retry the notification later.
      throw const PurchaseRejected('store_unavailable', status: 503);
    }
    if (tx == null || !tx.isRevoked) return 'ignored:not-revoked';
    final known = await wallet.clawBackPurchase(
      Store.appStore,
      tx.transactionId,
    );
    return known ? 'clawed-back' : 'ignored:unknown-purchase';
  }
}
