import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/last_room.dart';
import '../../core/providers.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
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

  @override
  void initState() {
    super.initState();
    unawaited(_resume());
  }

  /// Takes the player back into the room they last had open if they are
  /// still seated there (after a reload, an app restart or in a second
  /// browser tab). True if it did.
  Future<bool> _resume() async {
    final store = ref.read(lastRoomStoreProvider);
    final id = await store.read();
    if (id == null || !mounted) return false;
    final me = ref.read(authRepositoryProvider).currentSession?.userId;
    Room? room;
    try {
      room = await ref
          .read(roomRepositoryProvider)
          .watchRoom(id)
          .first
          .timeout(const Duration(seconds: 5));
    } on Object {
      room = null; // gone, or not ours any more
    }
    final seated =
        room != null &&
        room.status != RoomStatus.closed &&
        (me == null || room.memberIds.contains(me));
    if (!seated) {
      await store.write(null);
      return false;
    }
    if (mounted) unawaited(context.push(Routes.room(id)));
    return mounted;
  }

  void _go(Room room) =>
      // Not awaited: the room screen leaves with `go(lobby)`, which never
      // completes this push, and awaiting it kept the lobby busy for good.
      unawaited(context.push(Routes.room(room.id)));

  Future<void> _open(Future<Room> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final room = await action();
      if (mounted) _go(room);
    } catch (_) {
      // Most likely still seated in a running game: go back to it.
      if (await _resume()) return;
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
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              children: [
                _TopBar(
                  name: profile?.displayName,
                  coins: balance == null ? null : t.coins(balance.available),
                ),
                const SizedBox(height: 28),
                _Tagline(text: t.lobbyTagline, highlight: t.appTitle),
                const SizedBox(height: 24),
                _QuickMatchCard(
                  key: const ValueKey('quickMatch'),
                  title: t.quickMatch,
                  subtitle: t.lobbyQuickMatchHint,
                  onTap: () => _open(rooms.quickMatch),
                ),
                const SizedBox(height: 14),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      Expanded(
                        child: _ModeCard(
                          key: const ValueKey('createRoom'),
                          icon: Icons.add_rounded,
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
                      ),
                      Expanded(
                        child: _ModeCard(
                          key: const ValueKey('joinRoom'),
                          icon: Icons.vpn_key_rounded,
                          color: GameStyle.town,
                          title: t.joinRoom,
                          subtitle: t.lobbyJoinRoomHint,
                          onTap: () async {
                            final code = await showJoinCodeDialog(context);
                            if (code != null) {
                              await _open(() => rooms.joinByCode(code));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _HowToPlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The player's avatar (opens the profile), a greeting and the coins
/// (open the shop).
class _TopBar extends StatelessWidget {
  const _TopBar({this.name, this.coins});

  final String? name;
  final String? coins;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final name = this.name;
    return Row(
      spacing: 12,
      children: [
        Tooltip(
          message: t.profileTitle,
          child: Material(
            color: GameStyle.feltLight,
            borderRadius: BorderRadius.circular(15),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => context.push(Routes.profile),
              child: SizedBox.square(
                dimension: 46,
                child: name == null || name.isEmpty
                    ? const Icon(Icons.person_rounded, color: GameStyle.muted)
                    : Center(
                        child: Text(
                          name.characters.first.toUpperCase(),
                          style: GameStyle.display(
                            18,
                            color: GameStyle.crimson,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
        Expanded(
          child: name == null
              ? const SizedBox.shrink()
              : Text(
                  t.lobbyGreeting(name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
        ),
        if (coins != null)
          CoinChip(label: coins!, onTap: () => context.push(Routes.shop)),
      ],
    );
  }
}

/// "Who is the Mafia tonight?" with the word Mafia in the accent colour.
class _Tagline extends StatelessWidget {
  const _Tagline({required this.text, required this.highlight});

  final String text;
  final String highlight;

  @override
  Widget build(BuildContext context) {
    final style = GameStyle.display(32);
    final at = highlight.isEmpty
        ? -1
        : text.toLowerCase().indexOf(highlight.toLowerCase());
    if (at < 0) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, at)),
          TextSpan(
            text: text.substring(at, at + highlight.length),
            style: const TextStyle(color: GameStyle.crimson),
          ),
          TextSpan(text: text.substring(at + highlight.length)),
        ],
      ),
    );
  }
}

/// The big glowing "play now" card.
class _QuickMatchCard extends StatelessWidget {
  const _QuickMatchCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: GameStyle.glow(GameStyle.crimson),
      ),
      child: Material(
        color: GameStyle.crimson,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 172,
            child: Stack(
              children: [
                Positioned(
                  right: -36,
                  bottom: -52,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                Positioned(
                  right: 22,
                  top: 22,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 36,
                      color: GameStyle.crimson,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.bolt_rounded, color: Colors.white),
                      const Spacer(),
                      Text(
                        title,
                        style: GameStyle.display(26, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GameStyle.card,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBlob(icon: icon, color: color),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: Palette.display,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  color: GameStyle.muted,
                  fontSize: 13,
                  height: 1.35,
                ),
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.outlineSoft, width: 1.5),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const IconBlob(
            icon: Icons.help_outline_rounded,
            color: GameStyle.moon,
            size: 36,
          ),
          title: Text(
            t.lobbyHowToPlay,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          children: [
            Text(
              t.lobbyRulesBody,
              style: const TextStyle(color: GameStyle.muted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
