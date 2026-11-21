import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:postgres/postgres.dart';

/// A match whose coins were held but not yet settled. Found again after a
/// crash or restart so no stake is ever left stuck in escrow.
class UnsettledMatch {
  const UnsettledMatch({
    required this.roomId,
    required this.matchId,
    required this.stake,
    required this.players,
    this.result,
  });

  final RoomId roomId;
  final MatchId matchId;
  final int stake;
  final List<UserId> players;

  /// Set if the match finished before the server stopped; otherwise the
  /// match is settled as cancelled and everyone gets their stake back.
  final MatchResult? result;

  MatchResult resultOrCancelled(DateTime now) =>
      result ??
      MatchResult(
        roomId: roomId,
        matchId: matchId,
        stake: stake,
        winners: const [],
        losers: const [],
        endedAt: now,
      );
}

/// Durable record of every match: who played, the seed and every action
/// (enough to replay it through the engine for a dispute), the result, and
/// whether coins were settled.
abstract interface class MatchRecorder {
  Future<void> started({
    required RoomId roomId,
    required MatchId matchId,
    required int stake,
    required List<UserId> players,
    required int seed,
    required DateTime at,
  });

  Future<void> action(MatchId matchId, int seq, GameAction a, DateTime at);

  Future<void> ended(MatchResult result);

  Future<void> settled(MatchId matchId, DateTime at);

  Future<List<UnsettledMatch>> unsettled();
}

/// Keeps records in memory. For tests and for running without a database.
class InMemoryMatchRecorder implements MatchRecorder {
  final matches = <MatchId, Map<String, Object?>>{};
  final actions = <MatchId, List<GameAction>>{};

  @override
  Future<void> started({
    required RoomId roomId,
    required MatchId matchId,
    required int stake,
    required List<UserId> players,
    required int seed,
    required DateTime at,
  }) async {
    matches[matchId] = {
      'roomId': roomId,
      'stake': stake,
      'players': players,
      'seed': seed,
    };
  }

  @override
  Future<void> action(
    MatchId matchId,
    int seq,
    GameAction a,
    DateTime at,
  ) async => (actions[matchId] ??= []).add(a);

  @override
  Future<void> ended(MatchResult result) async =>
      matches[result.matchId]?['result'] = result;

  @override
  Future<void> settled(MatchId matchId, DateTime at) async =>
      matches[matchId]?['settled'] = true;

  @override
  Future<List<UnsettledMatch>> unsettled() async => [
    for (final e in matches.entries)
      if (e.value['settled'] != true)
        UnsettledMatch(
          roomId: e.value['roomId']! as String,
          matchId: e.key,
          stake: e.value['stake']! as int,
          players: e.value['players']! as List<UserId>,
          result: e.value['result'] as MatchResult?,
        ),
  ];
}

/// Stores records in the `rooms_matches` and `rooms_match_actions` tables
/// (migration 0002).
class PostgresMatchRecorder implements MatchRecorder {
  PostgresMatchRecorder(this._db);

  final Session _db;

  @override
  Future<void> started({
    required RoomId roomId,
    required MatchId matchId,
    required int stake,
    required List<UserId> players,
    required int seed,
    required DateTime at,
  }) => _db.execute(
    Sql.named(
      'INSERT INTO rooms_matches '
      '(match_id, room_id, stake, players, seed, started_at) '
      'VALUES (@m, @r, @s, @p, @seed, @at) ON CONFLICT DO NOTHING',
    ),
    parameters: {
      'm': matchId,
      'r': roomId,
      's': stake,
      'p': TypedValue(Type.textArray, players),
      'seed': seed,
      'at': at.toUtc(),
    },
  );

  @override
  Future<void> action(MatchId matchId, int seq, GameAction a, DateTime at) =>
      _db.execute(
        Sql.named(
          'INSERT INTO rooms_match_actions (match_id, seq, action, at) '
          'VALUES (@m, @seq, @a, @at) ON CONFLICT DO NOTHING',
        ),
        parameters: {
          'm': matchId,
          'seq': seq,
          'a': TypedValue(Type.jsonb, a.toJson()),
          'at': at.toUtc(),
        },
      );

  @override
  Future<void> ended(MatchResult result) => _db.execute(
    Sql.named(
      'UPDATE rooms_matches SET result = @res, ended_at = @at '
      'WHERE match_id = @m AND result IS NULL',
    ),
    parameters: {
      'm': result.matchId,
      'res': TypedValue(Type.jsonb, result.toJson()),
      'at': result.endedAt.toUtc(),
    },
  );

  @override
  Future<void> settled(MatchId matchId, DateTime at) => _db.execute(
    Sql.named(
      'UPDATE rooms_matches SET settled_at = @at '
      'WHERE match_id = @m AND settled_at IS NULL',
    ),
    parameters: {'m': matchId, 'at': at.toUtc()},
  );

  @override
  Future<List<UnsettledMatch>> unsettled() async {
    final rows = await _db.execute(
      'SELECT room_id, match_id, stake, players, result FROM rooms_matches '
      'WHERE settled_at IS NULL ORDER BY started_at',
    );
    return [
      for (final r in rows)
        UnsettledMatch(
          roomId: r[0]! as String,
          matchId: r[1]! as String,
          stake: r[2]! as int,
          players: [for (final p in r[3]! as List) p as String],
          result: r[4] == null ? null : MatchResult.fromJson(_json(r[4]!)),
        ),
    ];
  }

  static Json _json(Object v) =>
      (v is String ? jsonDecode(v) : v) as Map<String, Object?>;
}
