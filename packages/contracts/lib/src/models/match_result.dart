import '../json.dart';
import 'ids.dart';
import 'match_story.dart';
import 'role.dart';

/// The match-end event. The game server produces it once, and the wallet
/// settles coins from it. This is the only link between the game and coins.
class MatchResult {
  const MatchResult({
    required this.roomId,
    required this.matchId,
    required this.stake,
    required this.winners,
    required this.losers,
    required this.endedAt,
    this.winningTeam,
    this.forfeited = const [],
    this.roles = const {},
    this.story,
  });

  final RoomId roomId;
  final MatchId matchId;

  /// Coins each player put in at match start.
  final int stake;

  /// Null when the match was cancelled; the wallet then returns all stakes.
  final Team? winningTeam;
  final List<UserId> winners;
  final List<UserId> losers;

  /// Players who left mid-match. They lose their stake; they are also
  /// listed in [losers].
  final List<UserId> forfeited;

  /// Every player's role, revealed only now that the match is over. Empty
  /// for a cancelled match and for results from older servers.
  final Map<UserId, Role> roles;

  /// What happened each night and day, for the end-of-match cartoon. Null
  /// for a cancelled match and for results from older servers.
  final MatchStory? story;
  final DateTime endedAt;

  bool get cancelled => winningTeam == null;

  Json toJson() => {
    'roomId': roomId,
    'matchId': matchId,
    'stake': stake,
    'winningTeam': winningTeam?.name,
    'winners': winners,
    'losers': losers,
    'forfeited': forfeited,
    'roles': {for (final e in roles.entries) e.key: e.value.name},
    'story': story?.toJson(),
    'endedAt': encodeTime(endedAt),
  };

  factory MatchResult.fromJson(Json j) => MatchResult(
    roomId: j['roomId']! as String,
    matchId: j['matchId']! as String,
    stake: j['stake']! as int,
    winningTeam: j['winningTeam'] == null
        ? null
        : decodeEnum(Team.values, j['winningTeam']),
    winners: decodeStrings(j['winners']),
    losers: decodeStrings(j['losers']),
    forfeited: decodeStrings(j['forfeited']),
    roles: {
      for (final e in ((j['roles'] as Map?) ?? const {}).entries)
        e.key as String: ?Role.values.asNameMap()[e.value],
    },
    story: j['story'] == null ? null : MatchStory.fromJson(j['story']! as Json),
    endedAt: decodeTime(j['endedAt']),
  );
}
