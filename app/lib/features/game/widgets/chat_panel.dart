import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../game_providers.dart';
import '../ui/game_style.dart';

/// Where my next message would go right now, by the same rules the server
/// enforces (`ChatRules`). Null when I may not write.
ChatChannel? myChatChannel(
  PublicGameState? state,
  PrivatePlayerState? private,
  UserId? me,
) {
  final mine = state?.players.where((p) => p.userId == me).firstOrNull;
  final phase = state?.phase;
  return ChatRules.channelFor(
    phase: phase,
    inMatch: mine != null,
    isAlive: mine?.isAlive ?? false,
    role: private?.role,
    isLastWordSpeaker:
        phase == GamePhase.lastWord && me != null && state?.lastWordBy == me,
  );
}

/// The room's text chat: the latest messages, the emoji bar and a box to
/// type in. What the box says tells the player who will read it (everyone,
/// only the Mafia, only players who are out), or why it is closed.
class ChatPanel extends ConsumerStatefulWidget {
  const ChatPanel({
    super.key,
    required this.roomId,
    required this.state,
    required this.private,
    required this.me,
  });

  final RoomId roomId;

  /// The match, or null in the waiting room.
  final PublicGameState? state;
  final PrivatePlayerState? private;
  final UserId? me;

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _name(UserId id) =>
      widget.state?.players
          .where((p) => p.userId == id)
          .map((p) => p.displayName)
          .firstOrNull ??
      '…';

  Future<void> _send() async {
    final text = ChatRules.clean(_text.text);
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(gameActionsProvider(widget.roomId)).sendChat(text);
      _text.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).lobbyError)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final messages = ref.watch(chatProvider(widget.roomId)).value ?? const [];
    final s = widget.state;
    final channel = myChatChannel(s, widget.private, widget.me);
    final speaking =
        s?.phase == GamePhase.lastWord && s?.lastWordBy == widget.me;
    final lastWordFull =
        speaking &&
        !(widget.private?.allowedActions.contains('lastWord') ?? true);
    final open = channel != null && !lastWordFull;

    final hint = switch (channel) {
      _ when speaking => t.chatHintLastWord,
      ChatChannel.table => t.chatHintTable,
      ChatChannel.mafia => t.chatHintMafia,
      ChatChannel.dead => t.chatHintDead,
      null when s?.phase == GamePhase.lastWord && s?.lastWordBy != null =>
        t.chatClosedLastWord(_name(s!.lastWordBy!)),
      null => t.chatClosedNight,
    };
    final accent = switch (channel) {
      _ when speaking => GameStyle.gold,
      ChatChannel.mafia => GameStyle.crimson,
      ChatChannel.dead => GameStyle.muted,
      _ => GameStyle.town,
    };

    return GamePanel(
      key: const ValueKey('chat-panel'),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      borderColor: channel == ChatChannel.mafia
          ? GameStyle.crimson.withValues(alpha: 0.5)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 8,
            children: [
              Text(
                t.chatTitle.toUpperCase(),
                style: const TextStyle(
                  color: GameStyle.muted,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              if (channel != null) _ChannelChip(channel: channel),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: messages.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      t.chatEmpty,
                      style: const TextStyle(color: GameStyle.muted),
                    ),
                  )
                : ListView.builder(
                    // Newest at the bottom, scrolled there by default.
                    reverse: true,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[messages.length - 1 - i];
                      return _Line(message: m, mine: m.senderId == widget.me);
                    },
                  ),
          ),
          if (open)
            _ReactionBar(
              onReact: (e) =>
                  ref.read(gameActionsProvider(widget.roomId)).react(e),
            ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('chat-input'),
                  controller: _text,
                  focusNode: _focus,
                  enabled: open,
                  maxLength: ChatRules.maxLength,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: hint,
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    prefixIcon: open
                        ? null
                        : Icon(
                            s?.phase == GamePhase.night
                                ? Icons.bedtime_rounded
                                : Icons.lock_rounded,
                            size: 18,
                            color: GameStyle.muted,
                          ),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: open ? GameStyle.glow(accent) : null,
                ),
                child: IconButton(
                  key: const ValueKey('chat-send'),
                  tooltip: t.chatSend,
                  onPressed: open && !_sending ? _send : null,
                  icon: const Icon(Icons.send_rounded),
                  style: IconButton.styleFrom(
                    fixedSize: const Size(48, 48),
                    backgroundColor: accent,
                    foregroundColor: Palette.background,
                    disabledBackgroundColor: Palette.surfaceHigh,
                    disabledForegroundColor: GameStyle.muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({required this.channel});

  final ChatChannel channel;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (icon, color, text) = switch (channel) {
      ChatChannel.table => (
        Icons.forum_rounded,
        GameStyle.town,
        t.chatChannelTable,
      ),
      ChatChannel.mafia => (
        Icons.lock_rounded,
        GameStyle.crimson,
        t.chatChannelMafia,
      ),
      ChatChannel.dead => (
        Icons.visibility_off_rounded,
        GameStyle.muted,
        t.chatChannelDead,
      ),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(icon, size: 13, color: color),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// One message: the sender's name in their colour, then the text. Mafia
/// and dead-player messages carry a small tag; a last word glows gold.
class _Line extends StatelessWidget {
  const _Line({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final m = message;
    final nameColor = m.lastWord
        ? GameStyle.gold
        : mine
        ? GameStyle.gold
        : _nameColor(m.senderName);
    final (IconData? icon, Color tagColor) = switch (m.channel) {
      _ when m.lastWord => (Icons.record_voice_over_rounded, GameStyle.gold),
      ChatChannel.mafia => (Icons.lock_rounded, GameStyle.crimson),
      ChatChannel.dead => (Icons.visibility_off_rounded, GameStyle.muted),
      ChatChannel.table => (null, GameStyle.muted),
    };
    final line = Text.rich(
      TextSpan(
        children: [
          if (icon != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(icon, size: 14, color: tagColor),
              ),
            ),
          TextSpan(
            text: '${mine ? t.gameYou : m.senderName}  ',
            style: TextStyle(color: nameColor, fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: m.text,
            style: TextStyle(
              color: m.channel == ChatChannel.dead
                  ? GameStyle.muted
                  : Palette.text,
              fontStyle: m.lastWord ? FontStyle.italic : null,
            ),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 14, height: 1.35),
    );
    if (!m.lastWord) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: line,
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: GameStyle.gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GameStyle.gold.withValues(alpha: 0.45)),
      ),
      child: line,
    );
  }

  static const _names = [
    Color(0xFF2EE6D6),
    Color(0xFFA996FF),
    Color(0xFFFF8AB3),
    Color(0xFF7FE38B),
    Color(0xFFFFB547),
    Color(0xFF6FB8FF),
  ];

  static Color _nameColor(String name) =>
      _names[name.codeUnits.fold(0, (a, b) => a + b) % _names.length];
}

/// The emoji a player can pop on their own seat.
class _ReactionBar extends StatelessWidget {
  const _ReactionBar({required this.onReact});

  final Future<void> Function(String emoji) onReact;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // One row that always fits: each emoji gets an equal share.
    return SizedBox(
      height: 38,
      child: Row(
        spacing: 5,
        children: [
          for (final e in ChatRules.reactions)
            Expanded(
              child: Tooltip(
                message: t.chatReact,
                child: Material(
                  color: Palette.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: ValueKey('react-$e'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onReact(e).catchError((Object _) {}),
                    child: Center(
                      child: FittedBox(
                        child: Text(e, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Listens for emoji popped on seats and shows each for a few seconds.
/// [builder] gets the emoji to show per player right now.
class SeatReactions extends ConsumerStatefulWidget {
  const SeatReactions({super.key, required this.roomId, required this.builder});

  final RoomId roomId;
  final Widget Function(BuildContext context, Map<UserId, String> showing)
  builder;

  static const showFor = Duration(milliseconds: 2800);

  @override
  ConsumerState<SeatReactions> createState() => _SeatReactionsState();
}

class _SeatReactionsState extends ConsumerState<SeatReactions> {
  final _showing = <UserId, String>{};
  final _timers = <UserId, Timer>{};
  StreamSubscription<ChatReaction>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref
        .read(roomRepositoryProvider)
        .watchReactions(widget.roomId)
        .listen(_onReaction, onError: (Object _) {});
  }

  void _onReaction(ChatReaction r) {
    if (!mounted) return;
    setState(() => _showing[r.senderId] = r.emoji);
    _timers[r.senderId]?.cancel();
    _timers[r.senderId] = Timer(SeatReactions.showFor, () {
      if (mounted) setState(() => _showing.remove(r.senderId));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, Map.unmodifiable(_showing));
}

/// A big emoji that pops up over a seat.
class ReactionPop extends StatelessWidget {
  const ReactionPop({super.key, required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(emoji),
          tween: Tween(begin: 0.3, end: 1),
          duration: const Duration(milliseconds: 380),
          curve: Curves.elasticOut,
          builder: (context, v, child) =>
              Transform.scale(scale: v, child: child),
          child: Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Palette.background.withValues(alpha: 0.55),
              boxShadow: [
                BoxShadow(
                  color: Palette.lavender.withValues(alpha: 0.5),
                  blurRadius: 22,
                ),
              ],
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 32)),
          ),
        ),
      ),
    );
  }
}
