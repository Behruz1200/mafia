import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../l10n/generated/app_localizations.dart';
import 'data/http_wallet_repository.dart';
import 'data/store_billing.dart';
import 'data/wallet_providers.dart';

final _packsProvider = FutureProvider(
  (ref) => ref.watch(walletRepositoryProvider).coinPacks(),
);

final _historyProvider = FutureProvider(
  (ref) => ref.watch(walletRepositoryProvider).history(limit: 30),
);

/// Stream 4 (coins). Balance, coin packs through Apple in-app purchase
/// (Google Play later) and the coin history. Coins never leave the app:
/// there is no cash-out and no sending coins to other players.
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  String? _buying;

  Future<void> _buy(CoinPack pack) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _buying = pack.productId);
    String? message;
    try {
      await ref.read(walletRepositoryProvider).buy(pack);
      message = t.shopBought(pack.coins + pack.bonusCoins);
      ref.invalidate(_historyProvider);
    } on PurchaseCancelled {
      message = null;
    } on WalletException catch (e) {
      message = switch (e.code) {
        'network' || 'store_unavailable' => t.shopErrorOffline,
        'purchase_invalid' ||
        'purchase_not_found' ||
        'purchase_refunded' ||
        'purchase_other_account' => t.shopErrorRefused,
        _ => t.shopErrorGeneric,
      };
    } on Object {
      message = t.shopErrorGeneric;
    } finally {
      if (mounted) setState(() => _buying = null);
    }
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final balance = ref.watch(balanceProvider).value;
    final packs = ref.watch(_packsProvider);
    final ids = packs.value?.map((p) => p.productId).join(',') ?? '';
    final prices = ref.watch(storePricesProvider(ids)).value ?? const {};
    final canBuy = ref.watch(canBuyProvider).value ?? false;
    final history = ref.watch(_historyProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t.shopTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(_packsProvider)
            ..invalidate(_historyProvider);
          final wallet = ref.read(walletRepositoryProvider);
          if (wallet is HttpWalletRepository) await wallet.refresh();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.shopBalance, style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      t.coins(balance?.available ?? 0),
                      key: const Key('shop-balance'),
                      style: theme.textTheme.headlineMedium,
                    ),
                    if ((balance?.inEscrow ?? 0) > 0)
                      Text(t.shopInEscrow(balance!.inEscrow)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(t.shopNoCashOut, style: theme.textTheme.bodySmall),
            const SizedBox(height: 24),
            Text(t.shopPacksTitle, style: theme.textTheme.titleMedium),
            if (!canBuy && ref.watch(canBuyProvider).hasValue)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(t.shopBuyUnavailable),
              ),
            ...packs.when(
              data: (list) => [
                for (final p in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.toll_rounded,
                      color: Palette.gold,
                    ),
                    title: Text(t.coins(p.coins + p.bonusCoins)),
                    subtitle: p.bonusCoins > 0
                        ? Text(t.shopBonus(p.bonusCoins))
                        : null,
                    trailing: _buying == p.productId
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : FilledButton(
                            key: Key('buy-${p.productId}'),
                            onPressed: canBuy && _buying == null
                                ? () => _buy(p)
                                : null,
                            child: Text(prices[p.productId] ?? t.shopBuy),
                          ),
                  ),
              ],
              loading: () => [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (_, _) => [
                ListTile(
                  title: Text(t.shopErrorOffline),
                  trailing: TextButton(
                    onPressed: () => ref.invalidate(_packsProvider),
                    child: Text(t.shopRetry),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(t.shopHistoryTitle, style: theme.textTheme.titleMedium),
            ...switch (history) {
              AsyncData(value: final rows) when rows.isEmpty => [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(t.shopHistoryEmpty),
                ),
              ],
              AsyncData(value: final rows) => [
                for (final e in rows) _HistoryRow(entry: e),
              ],
              AsyncError() => [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.shopErrorOffline),
                ),
              ],
              _ => const [LinearProgressIndicator()],
            },
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});
  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final label = switch (entry.kind) {
      LedgerKind.purchase => t.shopKindPurchase,
      LedgerKind.refundClawback => t.shopKindRefund,
      LedgerKind.reward => t.shopKindReward,
      LedgerKind.stakeHold => t.shopKindStake,
      LedgerKind.stakeReturn => t.shopKindStakeReturn,
      LedgerKind.matchPayout => t.shopKindPayout,
      LedgerKind.houseFee => t.shopKindHouseFee,
      LedgerKind.adjustment => t.shopKindAdjustment,
    };
    final colors = Theme.of(context).colorScheme;
    final up = entry.delta >= 0;
    final local = entry.createdAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      subtitle: Text(
        '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}',
      ),
      trailing: Text(
        '${up ? '+' : '−'}${entry.delta.abs()}',
        style: TextStyle(
          color: up ? colors.primary : colors.error,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
