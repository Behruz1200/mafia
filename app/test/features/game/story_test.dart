import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/features/game/game_screen.dart';
import 'package:mafia_app/features/game/story/story_scenes.dart';
import 'package:mafia_app/features/game/story/story_script.dart';
import 'package:mafia_app/features/game/story/story_view.dart';
import 'package:mafia_app/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';
import 'story_fixture.dart';

PublicGameState _ended() {
  final s = samplePublicState(phase: GamePhase.ended);
  return PublicGameState(
    roomId: s.roomId,
    matchId: s.matchId,
    phase: GamePhase.ended,
    round: 3,
    players: s.players,
    winner: Team.town,
  );
}

StoryCast _cast(MatchResult r) => StoryCast(
  names: {for (final p in samplePlayers()) p.userId: p.displayName},
  roles: r.roles,
  winners: r.winners,
  me: 'user_0',
);

void main() {
  test('the story plays each round in order, then the result', () {
    final scenes = storyScenes(storyResult());
    expect(scenes.map((s) => s.runtimeType.toString()), [
      'ShotScene', 'CheckScene', 'CheckScene', 'VoteScene', // round 1
      'ShotScene', 'CheckScene', 'CheckScene', 'VoteScene', // round 2
      'QuietNightScene', 'VoteScene', // round 3
      'FinaleScene',
    ]);

    final shot = scenes[0] as ShotScene;
    expect(shot.saved, isTrue);
    expect(shot.shooters.first, 'user_6', reason: 'the Don holds the gun');
    expect(
      (scenes[1] as CheckScene).check.byDon,
      isFalse,
      reason: 'the Detective goes first',
    );
    final vote = scenes[3] as VoteScene;
    expect(vote.target, 'user_3');
    expect(vote.voters, ['user_0', 'user_1', 'user_2', 'user_4', 'user_5']);
    expect((scenes[4] as ShotScene).saved, isFalse);
    expect((scenes[7] as VoteScene).tied, isTrue);
    expect((scenes[8] as QuietNightScene).mafia, [
      'user_6',
    ], reason: 'the Mafia voted out on day 1 is not shown');
    final finale = scenes.last as FinaleScene;
    expect(finale.winner, Team.town);
    expect(
      finale.team.take(4),
      isNot(contains('user_1')),
      reason: 'survivors celebrate first',
    );
  });

  test('no story for a cancelled match or an older server', () {
    final r = storyResult();
    expect(
      storyScenes(
        MatchResult(
          roomId: r.roomId,
          matchId: r.matchId,
          stake: 0,
          winners: const [],
          losers: const [],
          endedAt: fixtureNow,
        ),
      ),
      isEmpty,
    );
  });

  testWidgets(
    'the story opens by itself after the match, and can be replayed',
    (tester) async {
      final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
      await tester.pump();
      repo
        ..emitPublic(_ended())
        ..emitMatchEnd(storyResult());
      // The results show, then the story opens over them.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.byType(StoryPlayer), findsOneWidget);
      expect(find.text('Night 1'), findsOneWidget);
      expect(find.text('The Mafia shot at Kamola…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('…but Doctor Dilnoza saved them!'), findsOneWidget);

      // Tap the picture: the Detective's check.
      await tester.tap(find.byKey(const Key('story-stage')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2500));
      expect(find.text('Detective Bekzod checked Jasur…'), findsOneWidget);
      expect(find.text('…and found the Mafia!'), findsOneWidget);

      // Skip to the result.
      await tester.tap(find.byKey(const Key('story-skip')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Result'), findsOneWidget);
      expect(find.text('The town found all the Mafia.'), findsOneWidget);
      expect(find.text('Replay'), findsOneWidget);

      await tester.tap(find.byKey(const Key('story-close')));
      await tester.pumpAndSettle();
      expect(find.byType(StoryPlayer), findsNothing);

      // It does not open again by itself, but the button brings it back.
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(StoryPlayer), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('watch-story')));
      await tester.tap(find.byKey(const Key('watch-story')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StoryPlayer), findsOneWidget);
      await tester.tap(find.byKey(const Key('story-close')));
      await tester.pumpAndSettle();
    },
  );

  for (final lang in ['en', 'uz', 'ru']) {
    testWidgets('every scene draws in $lang without overflow', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 740 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final r = storyResult();
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(lang),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: StoryPlayer(result: r, cast: _cast(r)),
        ),
      );
      final scenes = storyScenes(r);
      for (var i = 0; i < scenes.length; i++) {
        // Step through the whole scene, then on to the next.
        for (var ms = 0; ms < scenes[i].duration.inMilliseconds; ms += 700) {
          await tester.pump(const Duration(milliseconds: 700));
          expect(tester.takeException(), isNull, reason: 'scene $i at $ms ms');
        }
      }
      expect(find.byType(SceneStage), findsOneWidget);
    });
  }
}
