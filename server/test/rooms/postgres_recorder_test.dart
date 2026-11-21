import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:postgres/postgres.dart';
import 'package:server/rooms/match_recorder.dart';
import 'package:test/test.dart';

/// Runs only with `TEST_DATABASE_URL` pointing at a scratch database that
/// has migrations 0001 and 0002 applied, e.g.
/// `TEST_DATABASE_URL=postgres://postgres@localhost:5432/mafia_test?sslmode=disable`.
void main() {
  final url = Platform.environment['TEST_DATABASE_URL'];

  test('records a match and finds it until it is settled', () async {
    final db = Pool.withUrl(url!);
    addTearDown(db.close);
    final rec = PostgresMatchRecorder(db);
    final id = 'm_test_${DateTime.now().microsecondsSinceEpoch}';
    final at = DateTime.utc(2026, 11, 21, 20);

    await rec.started(
      roomId: 'r1',
      matchId: id,
      stake: 100,
      players: ['a', 'b'],
      seed: 4294967295,
      at: at,
    );
    await rec.action(id, 0, const CastVote(actorId: 'a', targetId: 'b'), at);
    await rec.action(id, 1, const PhaseTimeout(), at);

    var open = (await rec.unsettled()).where((u) => u.matchId == id).single;
    expect(open.players, ['a', 'b']);
    expect(open.result, isNull);
    expect(open.resultOrCancelled(at).cancelled, isTrue);

    final result = MatchResult(
      roomId: 'r1',
      matchId: id,
      stake: 100,
      winningTeam: Team.mafia,
      winners: ['b'],
      losers: ['a'],
      endedAt: at,
    );
    await rec.ended(result);
    open = (await rec.unsettled()).where((u) => u.matchId == id).single;
    expect(open.result!.winners, ['b']);

    await rec.settled(id, at);
    expect((await rec.unsettled()).where((u) => u.matchId == id), isEmpty);

    final rows = await db.execute(
      Sql.named('SELECT count(*) FROM rooms_match_actions WHERE match_id = @m'),
      parameters: {'m': id},
    );
    expect(rows.single.single, 2);
  }, skip: url == null ? 'set TEST_DATABASE_URL to run' : false);
}
