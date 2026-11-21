import '../models/ids.dart';
import '../models/match_result.dart';
import '../models/wallet.dart';
import '../ports/wallet_settlement.dart';

/// A simple in-memory [WalletSettlement] for server tests (stream 2) until
/// the real PostgreSQL wallet (stream 4) lands. Follows the same rules:
/// all-or-nothing holds, idempotent per match, house cut on payouts.
class InMemoryWalletSettlement implements WalletSettlement {
  InMemoryWalletSettlement({
    Map<UserId, int> balances = const {},
    this.houseCutPercent = 10,
  }) : _available = {...balances};

  final int houseCutPercent;
  final Map<UserId, int> _available;
  final _escrow = <MatchId, Map<UserId, int>>{};
  final _settled = <MatchId>{};
  final ledger = <LedgerEntry>[];

  int availableOf(UserId u) => _available[u] ?? 0;

  void _book(UserId u, LedgerKind kind, int delta, String ref) {
    _available[u] = availableOf(u) + delta;
    ledger.add(
      LedgerEntry(
        id: 'l${ledger.length}',
        userId: u,
        kind: kind,
        delta: delta,
        balanceAfter: availableOf(u),
        reference: ref,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<WalletBalance> balance(UserId userId) async {
    final held = _escrow.values.fold(0, (s, m) => s + (m[userId] ?? 0));
    return WalletBalance(
      userId: userId,
      available: availableOf(userId),
      inEscrow: held,
    );
  }

  @override
  Future<void> holdStakes({
    required MatchId matchId,
    required List<UserId> players,
    required int stake,
  }) async {
    if (_escrow.containsKey(matchId) || stake == 0) return;
    final short = [
      for (final p in players)
        if (availableOf(p) < stake) p,
    ];
    if (short.isNotEmpty) throw InsufficientCoins(short);
    _escrow[matchId] = {for (final p in players) p: stake};
    for (final p in players) {
      _book(p, LedgerKind.stakeHold, -stake, matchId);
    }
  }

  @override
  Future<void> settle(MatchResult r) async {
    if (!_settled.add(r.matchId)) return;
    final held = _escrow.remove(r.matchId) ?? const {};
    if (held.isEmpty) return;
    if (r.cancelled || r.winners.isEmpty) {
      held.forEach((u, s) => _book(u, LedgerKind.stakeReturn, s, r.matchId));
      return;
    }
    final pot = held.values.fold(0, (a, b) => a + b);
    final fee = pot * houseCutPercent ~/ 100;
    final share = (pot - fee) ~/ r.winners.length;
    final dust = pot - fee - share * r.winners.length;
    _book(houseAccount, LedgerKind.houseFee, fee + dust, r.matchId);
    for (final w in r.winners) {
      _book(w, LedgerKind.matchPayout, share, r.matchId);
    }
  }
}
