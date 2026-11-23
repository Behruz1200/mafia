import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/features/game/game_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

PublicGameState _state(
  GamePhase phase, {
  Map<UserId, UserId?> votes = const {},
  List<UserId> skipVotes = const [],
  List<PublicEvent> log = const [],
  Team? winner,
}) {
  final s = samplePublicState(phase: phase);
  return PublicGameState(
    roomId: s.roomId,
    matchId: s.matchId,
    phase: phase,
    round: 1,
    players: s.players,
    votes: votes,
    skipVotes: skipVotes,
    log: log,
    winner: winner,
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
}
