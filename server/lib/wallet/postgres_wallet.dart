import 'package:contracts/contracts.dart';
import 'package:postgres/postgres.dart';

/// A store purchase whose transaction the server has verified with the store.
class VerifiedPurchase {
  const VerifiedPurchase({
    required this.store,
    required this.transactionId,
    required this.productId,
    required this.coins,
    this.originalTransactionId,
    this.environment,
    this.purchasedAt,
  });

  final Store store;
  final String transactionId;
  final String? originalTransactionId;
  final String productId;

  /// Coins to credit: the pack's coins plus its bonus.
  final int coins;
  final String? environment;
  final DateTime? purchasedAt;

  String get reference => '${store.name}:$transactionId';
}

/// The store transaction was already credited to a different account.
class PurchaseBelongsToAnotherUser implements Exception {
  const PurchaseBelongsToAnotherUser(this.transactionId);
  final String transactionId;
  @override
  String toString() => 'PurchaseBelongsToAnotherUser($transactionId)';
}

/// The real coin wallet: PostgreSQL, append-only ledger, escrow per match.
///
/// Rules it keeps:
/// - Every change to a balance is a ledger row written in the same
///   transaction, so `wallets.available` always equals the sum of the
///   user's ledger deltas.
/// - Every operation is idempotent on its match or store transaction id
///   (unique `(user_id, kind, reference)`), so retries never pay twice.
/// - Coins only enter by purchase or reward and only move between players
///   through a match pot. There is no withdrawal or transfer, by design.
class PostgresWallet implements WalletSettlement {
  PostgresWallet(this._db, {this.houseCutPercent = 10})
    : assert(houseCutPercent >= 0 && houseCutPercent <= 100);

  final SessionExecutor _db;
  final int houseCutPercent;

  // ---------------------------------------------------------------- reads

  @override
  Future<WalletBalance> balance(UserId userId) =>
      _db.run((s) => _balance(s, userId));

  Future<WalletBalance> _balance(Session s, UserId userId) async {
    final rows = await s.execute(
      Sql.named('SELECT available, in_escrow FROM wallets WHERE user_id = @u'),
      parameters: {'u': userId},
    );
    if (rows.isEmpty) return WalletBalance(userId: userId, available: 0);
    final r = rows.first.toColumnMap();
    return WalletBalance(
      userId: userId,
      available: r['available'] as int,
      inEscrow: r['in_escrow'] as int,
    );
  }

  /// Newest first.
  Future<List<LedgerEntry>> history(UserId userId, {int limit = 50}) async {
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named(
          'SELECT id::text AS id, user_id, kind, delta, balance_after, '
          'reference, note, created_at FROM ledger WHERE user_id = @u '
          'ORDER BY created_at DESC, id DESC LIMIT @n',
        ),
        parameters: {'u': userId, 'n': limit.clamp(1, 200)},
      ),
    );
    return [
      for (final row in rows)
        () {
          final r = row.toColumnMap();
          return LedgerEntry(
            id: r['id'] as String,
            userId: r['user_id'] as String,
            kind: LedgerKind.values.byName(r['kind'] as String),
            delta: r['delta'] as int,
            balanceAfter: r['balance_after'] as int,
            reference: r['reference'] as String?,
            note: r['note'] as String?,
            createdAt: (r['created_at'] as DateTime).toUtc(),
          );
        }(),
    ];
  }

  // -------------------------------------------------------------- matches

  @override
  Future<void> holdStakes({
    required MatchId matchId,
    required List<UserId> players,
    required int stake,
  }) async {
    if (stake < 0) throw ArgumentError.value(stake, 'stake', 'is negative');
    if (stake == 0 || players.isEmpty) return; // free match
    final unique = {...players}.toList()..sort();
    await _db.runTx((tx) async {
      await _lockMatch(tx, matchId);
      if (await _isSettled(tx, matchId)) {
        throw StateError('Match $matchId is already settled');
      }
      final existing = await _escrowOf(tx, matchId);
      if (existing.isNotEmpty) {
        final same =
            existing.length == unique.length &&
            unique.every((p) => existing[p] == stake);
        if (same) return; // retry of the same hold
        throw StateError('Match $matchId already holds different stakes');
      }

      final wallets = await _lockWallets(tx, unique);
      final short = [
        for (final p in unique)
          if (wallets[p]! < stake) p,
      ];
      if (short.isNotEmpty) throw InsufficientCoins(short);

      for (final p in unique) {
        await tx.execute(
          Sql.named(
            'INSERT INTO match_escrow (match_id, user_id, stake) '
            'VALUES (@m, @u, @s)',
          ),
          parameters: {'m': matchId, 'u': p, 's': stake},
        );
        await _book(
          tx,
          userId: p,
          kind: LedgerKind.stakeHold,
          delta: -stake,
          escrowDelta: stake,
          reference: matchId,
        );
      }
    });
  }

  @override
  Future<void> settle(MatchResult result) async {
    final matchId = result.matchId;
    await _db.runTx((tx) async {
      await _lockMatch(tx, matchId);
      if (await _isSettled(tx, matchId)) return;
      final held = await _escrowOf(tx, matchId);
      if (held.isEmpty) {
        await _markSettled(tx, matchId, 'empty', 0, 0);
        return;
      }
      await _lockWallets(tx, [...held.keys, houseAccount]..sort());

      final pot = held.values.fold(0, (a, b) => a + b);
      final losers = {...result.losers, ...result.forfeited};
      final winners = {
        for (final w in result.winners)
          if (held.containsKey(w) && !losers.contains(w)) w,
      }.toList()..sort();

      if (result.cancelled || winners.isEmpty) {
        for (final MapEntry(key: u, value: s) in held.entries) {
          await _book(
            tx,
            userId: u,
            kind: LedgerKind.stakeReturn,
            delta: s,
            escrowDelta: -s,
            reference: matchId,
          );
        }
        await _markSettled(tx, matchId, 'returned', pot, 0);
        return;
      }

      final fee = pot * houseCutPercent ~/ 100;
      final share = (pot - fee) ~/ winners.length;
      final dust = pot - fee - share * winners.length;

      // Release everyone's escrow; winners also get their share of the pot
      // (which includes their own stake back).
      for (final MapEntry(key: u, value: s) in held.entries) {
        if (winners.contains(u)) {
          await _book(
            tx,
            userId: u,
            kind: LedgerKind.matchPayout,
            delta: share,
            escrowDelta: -s,
            reference: matchId,
          );
        } else {
          await _moveEscrow(tx, u, -s);
        }
      }
      if (fee + dust > 0) {
        await _book(
          tx,
          userId: houseAccount,
          kind: LedgerKind.houseFee,
          delta: fee + dust,
          reference: matchId,
        );
      }
      await _markSettled(tx, matchId, 'paid', pot, fee + dust);
    });
  }

  // ------------------------------------------------------------ purchases

  /// Credits a verified purchase once. A retry returns the current balance.
  Future<WalletBalance> creditPurchase(UserId userId, VerifiedPurchase p) {
    if (p.coins <= 0) throw ArgumentError.value(p.coins, 'coins');
    return _db.runTx((tx) async {
      final inserted = await tx.execute(
        Sql.named(
          'INSERT INTO purchases (store, transaction_id, '
          'original_transaction_id, user_id, product_id, coins, environment, '
          'purchased_at) VALUES (@st, @tx, @otx, @u, @p, @c, @env, @at) '
          'ON CONFLICT (store, transaction_id) DO NOTHING RETURNING user_id',
        ),
        parameters: {
          'st': p.store.name,
          'tx': p.transactionId,
          'otx': p.originalTransactionId,
          'u': userId,
          'p': p.productId,
          'c': p.coins,
          'env': p.environment,
          'at': TypedValue(Type.timestampTz, p.purchasedAt?.toUtc()),
        },
      );
      if (inserted.isEmpty) {
        final owner = await tx.execute(
          Sql.named(
            'SELECT user_id FROM purchases '
            'WHERE store = @st AND transaction_id = @tx',
          ),
          parameters: {'st': p.store.name, 'tx': p.transactionId},
        );
        if (owner.first[0] != userId) {
          throw PurchaseBelongsToAnotherUser(p.transactionId);
        }
        return _balance(tx, userId);
      }
      await _lockWallets(tx, [userId]);
      await _book(
        tx,
        userId: userId,
        kind: LedgerKind.purchase,
        delta: p.coins,
        reference: p.reference,
        note: p.productId,
      );
      return _balance(tx, userId);
    });
  }

  /// Takes back the coins of a refunded or revoked purchase. The balance can
  /// go negative if the coins were already spent; the player then has to buy
  /// or win coins before they can stake again. Returns false if we never
  /// credited that transaction.
  Future<bool> clawBackPurchase(Store store, String transactionId) {
    return _db.runTx((tx) async {
      final rows = await tx.execute(
        Sql.named(
          'UPDATE purchases SET refunded_at = now() '
          'WHERE store = @st AND transaction_id = @tx AND refunded_at IS NULL '
          'RETURNING user_id, coins',
        ),
        parameters: {'st': store.name, 'tx': transactionId},
      );
      if (rows.isEmpty) {
        final known = await tx.execute(
          Sql.named(
            'SELECT 1 FROM purchases WHERE store = @st AND transaction_id = @tx',
          ),
          parameters: {'st': store.name, 'tx': transactionId},
        );
        return known.isNotEmpty; // already clawed back, or unknown
      }
      final r = rows.first.toColumnMap();
      final userId = r['user_id'] as String;
      await _lockWallets(tx, [userId]);
      await _book(
        tx,
        userId: userId,
        kind: LedgerKind.refundClawback,
        delta: -(r['coins'] as int),
        reference: '${store.name}:$transactionId',
      );
      return true;
    });
  }

  // -------------------------------------------------------------- rewards

  /// Free coins (welcome bonus, daily reward). [reference] makes it
  /// once-only, e.g. `welcome` or `daily:2026-11-21`. Returns false if that
  /// reward was already given.
  Future<bool> grantReward(
    UserId userId,
    int coins, {
    required String reference,
    String? note,
  }) {
    if (coins <= 0) throw ArgumentError.value(coins, 'coins');
    return _db.runTx((tx) async {
      await _lockWallets(tx, [userId]);
      return _book(
        tx,
        userId: userId,
        kind: LedgerKind.reward,
        delta: coins,
        reference: reference,
        note: note,
      );
    });
  }

  /// Manual correction by support. Always needs a [note].
  Future<bool> adjust(
    UserId userId,
    int delta, {
    required String note,
    required String reference,
  }) {
    if (note.trim().isEmpty) throw ArgumentError.value(note, 'note');
    return _db.runTx((tx) async {
      await _lockWallets(tx, [userId]);
      return _book(
        tx,
        userId: userId,
        kind: LedgerKind.adjustment,
        delta: delta,
        reference: reference,
        note: note,
      );
    });
  }

  // ------------------------------------------------------------- internals

  Future<void> _lockMatch(TxSession tx, MatchId matchId) => tx.execute(
    Sql.named("SELECT pg_advisory_xact_lock(hashtext('match:' || @m))"),
    parameters: {'m': matchId},
  );

  Future<bool> _isSettled(TxSession tx, MatchId matchId) async =>
      (await tx.execute(
        Sql.named('SELECT 1 FROM match_settlements WHERE match_id = @m'),
        parameters: {'m': matchId},
      )).isNotEmpty;

  Future<Map<UserId, int>> _escrowOf(TxSession tx, MatchId matchId) async {
    final rows = await tx.execute(
      Sql.named('SELECT user_id, stake FROM match_escrow WHERE match_id = @m'),
      parameters: {'m': matchId},
    );
    return {for (final r in rows) r[0]! as String: r[1]! as int};
  }

  Future<void> _markSettled(
    TxSession tx,
    MatchId matchId,
    String outcome,
    int pot,
    int fee,
  ) => tx.execute(
    Sql.named(
      'INSERT INTO match_settlements (match_id, outcome, pot, house_fee) '
      'VALUES (@m, @o, @p, @f)',
    ),
    parameters: {'m': matchId, 'o': outcome, 'p': pot, 'f': fee},
  );

  /// Creates missing wallets, then locks them in user id order (the same
  /// order everywhere, so two matches never deadlock). Returns available.
  Future<Map<UserId, int>> _lockWallets(
    TxSession tx,
    List<UserId> userIds,
  ) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO wallets (user_id) SELECT unnest(@ids::text[]) '
        'ON CONFLICT (user_id) DO NOTHING',
      ),
      parameters: {'ids': TypedValue(Type.textArray, userIds)},
    );
    final rows = await tx.execute(
      Sql.named(
        'SELECT user_id, available FROM wallets WHERE user_id = ANY(@ids) '
        'ORDER BY user_id FOR UPDATE',
      ),
      parameters: {'ids': TypedValue(Type.textArray, userIds)},
    );
    return {for (final r in rows) r[0]! as String: r[1]! as int};
  }

  Future<void> _moveEscrow(TxSession tx, UserId userId, int escrowDelta) =>
      tx.execute(
        Sql.named(
          'UPDATE wallets SET in_escrow = in_escrow + @e, updated_at = now() '
          'WHERE user_id = @u',
        ),
        parameters: {'u': userId, 'e': escrowDelta},
      );

  /// Writes one ledger row and applies it to the (already locked) wallet.
  /// Returns false, changing nothing, if this (user, kind, reference) was
  /// already booked.
  Future<bool> _book(
    TxSession tx, {
    required UserId userId,
    required LedgerKind kind,
    required int delta,
    required String reference,
    int escrowDelta = 0,
    String? note,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'WITH w AS (SELECT available + @d AS after FROM wallets '
        'WHERE user_id = @u) '
        'INSERT INTO ledger (user_id, kind, delta, balance_after, reference, '
        'note) SELECT @u, @k, @d, w.after, @r, @n FROM w '
        'ON CONFLICT (user_id, kind, reference) WHERE reference IS NOT NULL '
        'DO NOTHING RETURNING balance_after',
      ),
      parameters: {
        'u': userId,
        'k': kind.name,
        'd': delta,
        'r': reference,
        'n': note,
      },
    );
    if (rows.isEmpty) return false;
    await tx.execute(
      Sql.named(
        'UPDATE wallets SET available = available + @d, '
        'in_escrow = in_escrow + @e, updated_at = now() WHERE user_id = @u',
      ),
      parameters: {'u': userId, 'd': delta, 'e': escrowDelta},
    );
    return true;
  }
}
