import 'dart:math';

import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/features/game/demo/demo_match.dart';

void main() {
  testWidgets('the demo plays a whole match to a result', (tester) async {
    {
      final repo = FakeRoomRepository();
      final phases = <GamePhase>[];
      final ends = <MatchResult>[];
      repo.watchPublicState('room_1').listen((s) {
        if (phases.isEmpty || phases.last != s.phase) phases.add(s.phase);
      });
      repo.watchMatchEnd('room_1').listen(ends.add);

      await tester.pump(); // let the listeners subscribe
      final demo = DemoMatch(
        repo: repo,
        call: FakeCallController(),
        me: 'user_0',
        random: Random(1),
      )..prepare();
      demo.onPlayerAction(const StartMatch(actorId: 'user_0'));
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(phases.first, GamePhase.lobby);
      expect(
        phases,
        containsAllInOrder([
          GamePhase.roleReveal,
          GamePhase.night,
          GamePhase.day,
          GamePhase.voting,
          GamePhase.ended,
        ]),
      );
      expect(ends, hasLength(1));
      expect(ends.single.winningTeam, Team.town);
      demo.dispose();
    }
  });
}
