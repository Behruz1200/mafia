import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

final _packsProvider = FutureProvider(
  (ref) => ref.watch(walletRepositoryProvider).coinPacks(),
);

/// Stream 4 (coins) owns this folder: coin packs through Apple in-app
/// purchase first (Google Play later), balance and history.
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final wallet = ref.watch(walletRepositoryProvider);
    final packs = ref.watch(_packsProvider).value ?? const [];
    final coins = ref.watch(balanceProvider).value?.available ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text('${t.shopTitle} · ${t.coins(coins)}')),
      body: ListView(
        children: [
          for (final p in packs)
            ListTile(
              title: Text(t.coins(p.coins + p.bonusCoins)),
              onTap: () => wallet.buy(p),
            ),
        ],
      ),
    );
  }
}
