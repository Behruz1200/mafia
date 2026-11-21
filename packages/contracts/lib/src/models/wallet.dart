import '../json.dart';
import 'ids.dart';

/// Every kind of coin movement the ledger can hold.
///
/// Coin model (decided 2026-11-21): players buy coins and win or lose them
/// in matches, but coins never leave the app. So there is deliberately no
/// withdrawal, cash-out or player-to-player transfer kind. Adding one is a
/// product and legal decision, not a code change.
enum LedgerKind {
  /// Coins bought with a verified store purchase.
  purchase,

  /// A store refund took purchased coins back. Can drive a balance negative.
  refundClawback,

  /// Free coins (daily reward, welcome bonus).
  reward,

  /// Stake moved from the balance into escrow at match start.
  stakeHold,

  /// Stake returned from escrow (match cancelled before it ended).
  stakeReturn,

  /// Winnings paid from the match pot at match end.
  matchPayout,

  /// The house cut taken from the pot. Booked on [houseAccount].
  houseFee,

  /// Manual correction by support. Always has a note.
  adjustment,
}

/// The account that collects [LedgerKind.houseFee] entries.
const houseAccount = '_house';

/// One row of the append-only ledger. Rows are never updated or deleted;
/// a balance is the sum of a user's [delta]s.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.userId,
    required this.kind,
    required this.delta,
    required this.balanceAfter,
    required this.createdAt,
    this.reference,
    this.note,
  });

  final String id;
  final UserId userId;
  final LedgerKind kind;

  /// Signed coin change. Negative for holds and clawbacks.
  final int delta;
  final int balanceAfter;

  /// Match id, store transaction id, etc. Together with [kind] and
  /// [userId] it is unique, which makes settlement safe to retry.
  final String? reference;
  final String? note;
  final DateTime createdAt;

  Json toJson() => {
    'id': id,
    'userId': userId,
    'kind': kind.name,
    'delta': delta,
    'balanceAfter': balanceAfter,
    'reference': reference,
    'note': note,
    'createdAt': encodeTime(createdAt),
  };

  factory LedgerEntry.fromJson(Json j) => LedgerEntry(
    id: j['id']! as String,
    userId: j['userId']! as String,
    kind: decodeEnum(LedgerKind.values, j['kind']),
    delta: j['delta']! as int,
    balanceAfter: j['balanceAfter']! as int,
    reference: j['reference'] as String?,
    note: j['note'] as String?,
    createdAt: decodeTime(j['createdAt']),
  );
}

/// A player's coins as the app shows them.
class WalletBalance {
  const WalletBalance({
    required this.userId,
    required this.available,
    this.inEscrow = 0,
  });

  final UserId userId;

  /// Coins the player can stake or spend now.
  final int available;

  /// Coins locked in matches that have not ended yet.
  final int inEscrow;

  bool canAfford(int stake) => available >= stake;

  Json toJson() => {
    'userId': userId,
    'available': available,
    'inEscrow': inEscrow,
  };

  factory WalletBalance.fromJson(Json j) => WalletBalance(
    userId: j['userId']! as String,
    available: j['available']! as int,
    inEscrow: j['inEscrow'] as int? ?? 0,
  );
}

/// Which app store a purchase came from.
enum Store { appStore, playStore }

/// A coin pack the shop sells. Prices come from the store, not from us.
class CoinPack {
  const CoinPack({
    required this.productId,
    required this.coins,
    this.bonusCoins = 0,
  });

  /// Store product id, the same on both stores, e.g. `coins_500`.
  final String productId;
  final int coins;
  final int bonusCoins;

  Json toJson() => {
    'productId': productId,
    'coins': coins,
    'bonusCoins': bonusCoins,
  };

  factory CoinPack.fromJson(Json j) => CoinPack(
    productId: j['productId']! as String,
    coins: j['coins']! as int,
    bonusCoins: j['bonusCoins'] as int? ?? 0,
  );
}
