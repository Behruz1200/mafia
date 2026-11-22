import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/routes.dart';
import '../../l10n/generated/app_localizations.dart';
import '../game/ui/game_style.dart';
import 'widgets/create_room_sheet.dart';
import 'widgets/join_code_dialog.dart';

final _myProfileProvider = StreamProvider.autoDispose<UserProfile?>(
  (ref) => ref.watch(profileRepositoryProvider).watchMyProfile(),
);

/// Stream 6 (game UI) owns this folder: the home screen with quick match,
/// create a room and join with a code.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  bool _busy = false;

  Future<void> _open(Future<Room> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final room = await action();
      // Not awaited: the room screen leaves with `go(lobby)`, which never
      // completes this push, and awaiting it kept the lobby busy for good.
      if (mounted) unawaited(context.push(Routes.room(room.id)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).lobbyError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final rooms = ref.watch(roomRepositoryProvider);
    final balance = ref.watch(balanceProvider).value;
    final profile = ref.watch(_myProfileProvider).value;

    return Container(
      decoration: const BoxDecoration(gradient: GameStyle.lobbyGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(t.lobbyTitle),
          actions: [
            if (balance != null)
              CoinChip(
                label: t.coins(balance.available),
                onTap: () => context.push(Routes.shop),
              ),
            IconButton(
              icon: const Icon(Icons.person),
              tooltip: t.profileTitle,
              onPressed: () => context.push(Routes.profile),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _Hero(name: profile?.displayName),
              const SizedBox(height: 20),
              _ModeCard(
                key: const ValueKey('quickMatch'),
                icon: Icons.bolt,
                color: GameStyle.crimson,
                title: t.quickMatch,
                subtitle: t.lobbyQuickMatchHint,
                filled: true,
                onTap: () => _open(rooms.quickMatch),
              ),
              const SizedBox(height: 12),
              _ModeCard(
                key: const ValueKey('createRoom'),
                icon: Icons.add_circle_outline,
                color: GameStyle.gold,
                title: t.createRoom,
                subtitle: t.lobbyCreateRoomHint,
                onTap: () async {
                  final settings = await showCreateRoomSheet(
                    context,
                    available: balance?.available ?? 0,
                    canStake: profile?.isAdult ?? false,
                  );
                  if (settings != null) {
                    await _open(() => rooms.createRoom(settings));
                  }
                },
              ),
              const SizedBox(height: 12),
              _ModeCard(
                key: const ValueKey('joinRoom'),
                icon: Icons.vpn_key_outlined,
                color: GameStyle.town,
                title: t.joinRoom,
                subtitle: t.lobbyJoinRoomHint,
                onTap: () async {
                  final code = await showJoinCodeDialog(context);
                  if (code != null) await _open(() => rooms.joinByCode(code));
                },
              ),
              const SizedBox(height: 24),
              _HowToPlay(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return GamePanel(
      padding: const EdgeInsets.all(20),
      color: Colors.black.withValues(alpha: 0.25),
      child: Row(
        spacing: 16,
        children: [
          const Icon(Icons.theater_comedy, size: 56, color: GameStyle.gold),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                if (name != null)
                  Text(
                    t.lobbyGreeting(name!),
                    style: const TextStyle(color: GameStyle.muted),
                  ),
                Text(
                  t.lobbyTagline,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : GameStyle.card.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(GameStyle.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            spacing: 16,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled
                      ? Colors.white.withValues(alpha: 0.18)
                      : color.withValues(alpha: 0.16),
                ),
                child: Icon(icon, color: filled ? Colors.white : color),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: filled ? Colors.white70 : GameStyle.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: filled ? Colors.white : GameStyle.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HowToPlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Material(
      color: GameStyle.card.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(GameStyle.radius),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.menu_book, color: GameStyle.muted),
          title: Text(t.lobbyHowToPlay),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [Text(t.lobbyRulesBody)],
        ),
      ),
    );
  }
}
