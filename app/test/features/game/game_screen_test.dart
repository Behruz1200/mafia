import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/features/game/game_screen.dart';
import 'package:mafia_app/features/game/widgets/chat_panel.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

PublicGameState _state(
  GamePhase phase, {
  Map<UserId, UserId?> votes = const {},
  List<UserId> skipVotes = const [],
  List<PublicEvent> log = const [],
  Team? winner,
  UserId? lastWordBy,
  Set<UserId> dead = const {},
}) {
  final s = samplePublicState(phase: phase);
  return PublicGameState(
    roomId: s.roomId,
    matchId: s.matchId,
    phase: phase,
    round: 1,
    players: [
      for (final p in s.players)
        dead.contains(p.userId) ? p.copyWith(isAlive: false) : p,
    ],
    votes: votes,
    skipVotes: skipVotes,
    log: log,
    winner: winner,
    lastWordBy: lastWordBy,
  );
}

void main() {
  testWidgets('waiting room shows the code and lets the host start', (
    tester,
  ) async {
    final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
    repo.emitPublic(_state(GamePhase.lobby));
    await tester.pumpAndSettle();

    expect(find.text('K7QF2'), findsOneWidget);
    expect(find.text('8 of 12 players'), findsOneWidget);
    expect(find.text('Stake: 100 coins'), findsOneWidget);

    await tester.tap(find.text('Start the game'));
    await tester.pump();
    expect(repo.sent.single, isA<StartMatch>());
  });

  testWidgets('before the match, seats show names, not ids', (tester) async {
    await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
    await tester.pumpAndSettle();

    expect(find.text('Kamola'), findsOneWidget);
    expect(find.textContaining('user_4'), findsNothing);
  });

  testWidgets('role card flips to show the secret role', (tester) async {
    final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
    repo
      ..emitPublic(_state(GamePhase.roleReveal))
      ..emitPrivate(samplePrivateState(role: Role.mafia));
    await tester.pumpAndSettle();

    expect(find.text('Tap to see your role. Keep it secret!'), findsOneWidget);
    await tester.tap(find.text('Tap to see your role. Keep it secret!'));
    await tester.pumpAndSettle();
    expect(find.text('Mafia'), findsWidgets);
    expect(find.text('Your team: Jasur'), findsOneWidget);
  });

  testWidgets('detective picks a player at night and confirms', (tester) async {
    final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
    repo
      ..emitPublic(_state(GamePhase.night))
      ..emitPrivate(
        const PrivatePlayerState(
          userId: 'user_0',
          role: Role.detective,
          allowedActions: ['nightCheck'],
        ),
      );
    await tester.pumpAndSettle();

    expect(find.text('Choose who to check tonight'), findsOneWidget);
    await tester.tap(find.text('Kamola'));
    await tester.pump();
    await tester.tap(find.text('Confirm: Kamola'));
    await tester.pump();

    final sent = repo.sent.single as NightCheck;
    expect(sent.targetId, 'user_4');
  });

  testWidgets('a confirmed choice locks until another player is picked', (
    tester,
  ) async {
    final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
    repo
      ..emitPublic(_state(GamePhase.voting))
      ..emitPrivate(
        const PrivatePlayerState(
          userId: 'user_0',
          role: Role.civilian,
          allowedActions: ['castVote'],
        ),
      );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kamola'));
    await tester.pump();
    await tester.tap(find.text('Confirm: Kamola'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmed: Kamola'), findsOneWidget);
    expect(find.text('Done. Waiting for the others…'), findsOneWidget);

    await tester.tap(find.text('Confirmed: Kamola'));
    await tester.pumpAndSettle();
    expect(repo.sent, hasLength(1));

    // Changing the vote is still allowed.
    await tester.tap(find.text('Jasur'));
    await tester.pump();
    await tester.tap(find.text('Confirm: Jasur'));
    await tester.pumpAndSettle();
    expect(repo.sent, hasLength(2));
    expect((repo.sent.last as CastVote).targetId, 'user_3');
  });

  testWidgets('a civilian sleeps at night with no buttons', (tester) async {
    final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
    repo
      ..emitPublic(_state(GamePhase.night))
      ..emitPrivate(samplePrivateState());
    await tester.pumpAndSettle();

    expect(
      find.text('Night has fallen. Close your eyes and wait for the morning.'),
      findsWidgets,
    );
    expect(find.textContaining('Confirm'), findsNothing);
  });

  testWidgets('voting shows open votes and can skip', (tester) async {
    final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
    repo
      ..emitPublic(
        _state(
          GamePhase.voting,
          votes: {'user_1': 'user_3', 'user_2': 'user_3'},
          log: const [
            PublicEvent(
              round: 1,
              phase: GamePhase.day,
              message: 'eliminated',
              userId: 'user_5',
              cause: EliminationCause.killedAtNight,
            ),
          ],
        ),
      )
      ..emitPrivate(
        const PrivatePlayerState(
          userId: 'user_0',
          role: Role.civilian,
          allowedActions: ['castVote'],
        ),
      );
    await tester.pumpAndSettle();

    expect(find.text('Vote for who should leave the table'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('seat-user_3')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(find.text('Otabek was eliminated in the night'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect((repo.sent.single as CastVote).targetId, isNull);
  });

  testWidgets('results show the winner and the lost stake', (tester) async {
    final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
    await tester.pump();
    repo
      ..emitPublic(_state(GamePhase.ended, winner: Team.town))
      ..emitMatchEnd(
        MatchResult(
          roomId: 'room_1',
          matchId: 'match_1',
          stake: 100,
          winningTeam: Team.town,
          winners: const ['user_1', 'user_2'],
          losers: const ['user_0', 'user_3'],
          endedAt: fixtureNow,
        ),
      );
    await tester.pumpAndSettle();

    expect(find.text('The town wins!'), findsOneWidget);
    expect(find.text('You lost'), findsOneWidget);
    expect(
      find.text('Your stake of 100 coins went to the winners.'),
      findsOneWidget,
    );
    expect(find.text('Play again'), findsOneWidget);
  });

  testWidgets('skip timer counts agreements and can be taken back', (
    tester,
  ) async {
    final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
    final day = _state(GamePhase.day, skipVotes: const ['user_1', 'user_2']);
    final alive = day.alive.length;
    repo
      ..emitPublic(day)
      ..emitPrivate(
        const PrivatePlayerState(
          userId: 'user_0',
          role: Role.civilian,
          allowedActions: ['skipPhase'],
        ),
      );
    await tester.pumpAndSettle();

    expect(find.text('Skip timer · 2/$alive'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('skip-timer')));
    await tester.pump();
    expect((repo.sent.single as SkipPhase).skip, isTrue);

    repo.emitPublic(
      _state(GamePhase.day, skipVotes: const ['user_1', 'user_2', 'user_0']),
    );
    await tester.pumpAndSettle();
    expect(find.text('You want to skip · 3/$alive'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect((repo.sent.last as SkipPhase).skip, isFalse);
  });

  testWidgets('no skip button for players who cannot skip', (tester) async {
    final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
    repo
      ..emitPublic(_state(GamePhase.day))
      ..emitPrivate(samplePrivateState());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('skip-timer')), findsNothing);
  });

  testWidgets('waiting room has camera and mic and a refresh button', (
    tester,
  ) async {
    final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
    repo.emitPublic(_state(GamePhase.lobby));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('call-camera')), findsOneWidget);
    expect(find.byKey(const ValueKey('call-mic')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('refresh-button')));
    await tester.pumpAndSettle();
    expect(find.text('Refreshed'), findsOneWidget);
    expect(find.text('K7QF2'), findsOneWidget);
  });

  group('chat', () {
    Future<void> scrollToChat(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('chat-input')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }

    testWidgets('in the day everyone can write to the table', (tester) async {
      final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
      repo
        ..emitPublic(_state(GamePhase.day))
        ..emitPrivate(samplePrivateState());
      await tester.pumpAndSettle();
      await scrollToChat(tester);

      expect(find.text('Everyone'), findsOneWidget);
      expect(find.text('Message everyone…'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('chat-input')), ' hi! ');
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await tester.pumpAndSettle();
      expect(repo.chat.single.text, 'hi!');
      expect(find.textContaining('hi!'), findsOneWidget);
    });

    testWidgets('the town cannot write at night', (tester) async {
      final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
      repo
        ..emitPublic(_state(GamePhase.night))
        ..emitPrivate(samplePrivateState());
      await tester.pumpAndSettle();
      await scrollToChat(tester);

      expect(
        find.text('The town sleeps. Chat opens in the morning.'),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('chat-input')),
      );
      expect(field.enabled, isFalse);
      expect(find.byKey(const ValueKey('react-👍')), findsNothing);
    });

    testWidgets('the Mafia see their private chat at night', (tester) async {
      final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
      repo
        ..emitPublic(_state(GamePhase.night))
        ..emitPrivate(
          const PrivatePlayerState(
            userId: 'user_0',
            role: Role.mafia,
            teammates: ['user_3'],
            allowedActions: ['nightKill'],
          ),
        )
        ..emitChat(
          ChatMessage(
            id: 'c1',
            roomId: 'room_1',
            matchId: 'match_1',
            senderId: 'user_3',
            senderName: 'Jasur',
            text: 'take Kamola',
            channel: ChatChannel.mafia,
            sentAt: fixtureNow,
          ),
        );
      await tester.pumpAndSettle();
      await scrollToChat(tester);

      expect(find.text('Mafia only'), findsOneWidget);
      expect(find.text('Only the Mafia sees this…'), findsOneWidget);
      expect(find.textContaining('take Kamola'), findsOneWidget);
    });

    testWidgets('an emoji pops up on my seat for a moment', (tester) async {
      final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
      repo
        ..emitPublic(_state(GamePhase.day))
        ..emitPrivate(samplePrivateState());
      await tester.pumpAndSettle();
      await scrollToChat(tester);

      await tester.tap(find.byKey(const ValueKey('react-😂')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ReactionPop), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(ReactionPop), findsNothing);
    });
  });

  group('last word', () {
    testWidgets('the eliminated player speaks, types and ends it', (
      tester,
    ) async {
      final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
      repo
        ..emitPublic(
          _state(
            GamePhase.lastWord,
            lastWordBy: 'user_0',
            dead: {'user_0'},
            log: const [
              PublicEvent(
                round: 1,
                phase: GamePhase.lastWord,
                message: 'lastWord',
                userId: 'user_0',
                text: 'Jasur is lying',
              ),
            ],
          ),
        )
        ..emitPrivate(
          const PrivatePlayerState(
            userId: 'user_0',
            role: Role.civilian,
            allowedActions: ['lastWord', 'skipPhase'],
          ),
        );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('last-word-stage')), findsOneWidget);
      expect(find.text('“Jasur is lying”'), findsOneWidget);
      expect(
        find.text(
          'Your last word. Talk on camera or type it below, then tap Done.',
        ),
        findsOneWidget,
      );
      expect(find.text('Last word'), findsWidgets);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('chat-input')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Type your last word…'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('chat-input')), 'bye');
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await tester.pumpAndSettle();
      expect(repo.chat.single.text, 'bye');

      await tester.tap(find.byKey(const ValueKey('last-word-done')));
      await tester.pump();
      expect(repo.sent.single, isA<SkipPhase>());
    });

    testWidgets('everyone else listens and cannot write', (tester) async {
      final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
      repo
        ..emitPublic(
          _state(GamePhase.lastWord, lastWordBy: 'user_4', dead: {'user_4'}),
        )
        ..emitPrivate(samplePrivateState());
      await tester.pumpAndSettle();

      expect(
        find.text('Kamola is saying a last word. Listen.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('last-word-done')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('chat-input')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Only Kamola can write now.'), findsOneWidget);
    });
  });
}
