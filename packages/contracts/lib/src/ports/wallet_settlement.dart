import '../models/ids.dart';
import '../models/match_result.dart';
import '../models/wallet.dart';

/// Server-side wallet, implemented by stream 4 in `server/lib/wallet` and
/// called by the room code (stream 2). Every method must be idempotent on
/// its match or transaction id, so a retry never pays twice.
abstract interface class WalletSettlement {
  Future<WalletBalance> balance(UserId userId);

  /// Move [stake] from every player into escrow. All or nothing: if anyone
  /// cannot afford it, nobody is charged and the error lists who.
  Future<void> holdStakes({
    required MatchId matchId,
    required List<UserId> players,
    required int stake,
  });

  /// Pay out the pot (minus the house cut) or return stakes if cancelled.
  Future<void> settle(MatchResult result);
}

class InsufficientCoins implements Exception {
  const InsufficientCoins(this.userIds);
  final List<UserId> userIds;
  @override
  String toString() => 'InsufficientCoins($userIds)';
}
