import '../json.dart';
import 'ids.dart';
import 'phase.dart';
import 'role.dart';

/// Who can read a chat message.
enum ChatChannel {
  /// Everyone at the table.
  table,

  /// Only the Mafia team, at night.
  mafia,

  /// Only players who are already out. They can talk among themselves but
  /// never reach the living.
  dead,
}

/// One typed message in a room. The server sets every field except the
/// text, and sends it only to players who may read its [channel].
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.channel,
    required this.sentAt,
    this.matchId,
    this.lastWord = false,
  });

  final String id;
  final RoomId roomId;

  /// The match it was sent in; null in the waiting room.
  final MatchId? matchId;
  final UserId senderId;
  final String senderName;
  final String text;
  final ChatChannel channel;
  final DateTime sentAt;

  /// Part of the sender's last word (also kept in the match log).
  final bool lastWord;

  Json toJson() => {
    'id': id,
    'roomId': roomId,
    'matchId': matchId,
    'senderId': senderId,
    'senderName': senderName,
    'text': text,
    'channel': channel.name,
    'sentAt': encodeTime(sentAt),
    'lastWord': lastWord,
  };

  factory ChatMessage.fromJson(Json j) => ChatMessage(
    id: j['id']! as String,
    roomId: j['roomId']! as String,
    matchId: j['matchId'] as String?,
    senderId: j['senderId']! as String,
    senderName: j['senderName'] as String? ?? '',
    text: j['text']! as String,
    channel: decodeEnum(ChatChannel.values, j['channel']),
    sentAt: decodeTime(j['sentAt']),
    lastWord: j['lastWord'] as bool? ?? false,
  );
}

/// The chat's secrecy rules, shared by the server (which enforces them)
/// and the app (which shows where a message will go). They follow the
/// camera and mic rules in `CallPolicy`:
///
/// - Waiting room, role reveal and after the match: everyone, to the table.
/// - Day and voting: the living write to the table. Players who are out
///   write only to each other ([ChatChannel.dead]).
/// - Night: the town cannot write. Living Mafia write to their private
///   [ChatChannel.mafia]. Players who are out still have their own chat.
/// - Last word: only the speaker writes to the table. Players who are out
///   keep their own chat.
abstract final class ChatRules {
  /// Longest message, in characters.
  static const maxLength = 200;

  /// Typed lines one player may add to their last word.
  static const maxLastWordLines = 3;

  /// Where a message from this player goes right now, or null if they may
  /// not write. [phase] null means no match is running (waiting room).
  static ChatChannel? channelFor({
    required GamePhase? phase,
    required bool inMatch,
    required bool isAlive,
    required Role? role,
    required bool isLastWordSpeaker,
  }) {
    if (phase == null ||
        phase == GamePhase.lobby ||
        phase == GamePhase.ended ||
        !inMatch) {
      return ChatChannel.table;
    }
    if (phase == GamePhase.lastWord && isLastWordSpeaker) {
      return ChatChannel.table;
    }
    if (!isAlive) return ChatChannel.dead;
    return switch (phase) {
      GamePhase.roleReveal ||
      GamePhase.day ||
      GamePhase.voting => ChatChannel.table,
      GamePhase.night => role?.team == Team.mafia ? ChatChannel.mafia : null,
      _ => null,
    };
  }

  /// Whether a player may read messages on [channel]. [inMatch], [isAlive]
  /// and [role] describe the reader in the message's match. Secret chats
  /// stay secret after the match too.
  static bool canRead({
    required ChatChannel channel,
    required bool inMatch,
    required bool isAlive,
    required Role? role,
  }) => switch (channel) {
    ChatChannel.table => true,
    ChatChannel.mafia => inMatch && role?.team == Team.mafia,
    ChatChannel.dead => inMatch && !isAlive,
  };

  /// Trims, turns line breaks and control characters into spaces, squeezes
  /// runs of spaces and cuts to [maxLength]. Empty means nothing to send.
  static String clean(String raw) {
    final out = StringBuffer();
    var space = false;
    for (final r in raw.runes) {
      final blank =
          r < 0x20 ||
          r == 0x7F ||
          (r >= 0x80 && r < 0xA0) ||
          r == 0x2028 ||
          r == 0x2029 ||
          r == 0x20;
      if (blank) {
        space = out.isNotEmpty;
        continue;
      }
      if (space) out.write(' ');
      space = false;
      out.writeCharCode(r);
    }
    final s = out.toString();
    final runes = s.runes;
    return runes.length <= maxLength
        ? s
        : String.fromCharCodes(runes.take(maxLength)).trimRight();
  }
}
