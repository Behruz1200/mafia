import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/routes.dart';
import '../../l10n/generated/app_localizations.dart';

/// Stream 6 (game UI) owns this folder: create, join and quick-match.
class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final rooms = ref.watch(roomRepositoryProvider);
    final coins = ref.watch(balanceProvider).value?.available;

    Future<void> open(Future<Room> Function() action) async {
      final room = await action();
      if (context.mounted) context.push(Routes.room(room.id));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.lobbyTitle),
        actions: [
          if (coins != null)
            TextButton(
              onPressed: () => context.push(Routes.shop),
              child: Text(t.coins(coins)),
            ),
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: t.profileTitle,
            onPressed: () => context.push(Routes.profile),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            FilledButton(
              onPressed: () => open(rooms.quickMatch),
              child: Text(t.quickMatch),
            ),
            OutlinedButton(
              onPressed: () =>
                  open(() => rooms.createRoom(const RoomSettings())),
              child: Text(t.createRoom),
            ),
            OutlinedButton(
              onPressed: () => open(() => rooms.joinByCode('K7QF2')),
              child: Text(t.joinRoom),
            ),
          ],
        ),
      ),
    );
  }
}
