import '../json.dart';
import 'ids.dart';
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
    endedAt: decodeTime(j['endedAt']),
  );
}
