import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/features/game/game_screen.dart';
import 'package:mafia_app/features/game/ui/game_text.dart';
import 'package:mafia_app/l10n/generated/app_localizations_en.dart';

import 'harness.dart';

PublicGameState _state(
  GamePhase phase, {
  Set<UserId> dead = const {},
  List<PublicEvent> log = const [],
  Team? winner,
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
    log: log,
    winner: winner,
  );
}

void main() {
  testWidgets('Play again shows who is seated now, not the last table', (
    tester,
  ) async {
    final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
    repo
      ..emitPublic(_state(GamePhase.ended, winner: Team.town, dead: {'user_4'}))
      ..emitMatchEnd(
        MatchResult(
          roomId: 'room_1',
          matchId: 'match_1',
          stake: 0,
          winningTeam: Team.town,
          winners: const ['user_0'],
          losers: const ['user_4'],
          endedAt: fixtureNow,
        ),
      );
    await tester.pumpAndSettle();

    // Kamola (user_4) left after the match; Nilufar joined.
    final room = sampleRoom();
    repo.emitRoom(
      Room(
        id: room.id,
        inviteCode: room.inviteCode,
        hostId: room.hostId,
        status: RoomStatus.open,
        settings: room.settings,
        memberIds: [
          for (final id in room.memberIds)
            if (id != 'user_4') id,
          'user_11',
        ],
        memberNames: {...room.memberNames, 'user_11': 'Nilufar'}
          ..remove('user_4'),
        createdAt: room.createdAt,
      ),
    );
    await tester.tap(find.text('Play again'));
    await tester.pumpAndSettle();

    expect(find.text('K7QF2'), findsOneWidget);
    expect(find.text('Nilufar'), findsOneWidget);
    expect(find.text('Kamola'), findsNothing);
  });

  testWidgets('a refused move can be confirmed again and says why', (
    tester,
  ) async {
    final errors = StreamController<SocketError>.broadcast();
    addTearDown(errors.close);
    final repo = await pumpGameUi(
      tester,
      const GameScreen(roomId: 'room_1'),
      errors: errors.stream,
    );
    repo
      ..emitPublic(_state(GamePhase.night))
      ..emitPrivate(
        const PrivatePlayerState(
          userId: 'user_0',
          role: Role.doctor,
          allowedActions: ['nightHeal'],
        ),
      );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kamola'));
    await tester.pump();
    await tester.tap(find.text('Confirm: Kamola'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmed: Kamola'), findsOneWidget);

    errors.add(const SocketError('same_heal_twice'));
    await tester.pumpAndSettle();
    expect(
      find.text("You can't save the same player two nights in a row."),
      findsOneWidget,
    );
    expect(find.text('Confirm: Kamola'), findsOneWidget);
  });

  testWidgets('the Don shoots, then checks for the Detective', (tester) async {
    final repo = await pumpGameUi(tester, const GameScreen(roomId: 'room_1'));
    repo
      ..emitPublic(_state(GamePhase.night))
      ..emitPrivate(
        const PrivatePlayerState(
          userId: 'user_0',
          role: Role.don,
          teammates: ['user_3'],
          detectiveChecks: {'user_2': false},
          allowedActions: ['nightKill', 'nightCheck'],
        ),
      );
    await tester.pumpAndSettle();

    expect(find.text('Shoot'), findsOneWidget);
    expect(find.text('Find the Detective'), findsOneWidget);
    // Last night's check is on Dilnoza's seat.
    expect(find.text('NOT DETECTIVE'), findsOneWidget);

    await tester.tap(find.text('Kamola'));
    await tester.pump();
    await tester.tap(find.text('Confirm: Kamola'));
    await tester.pumpAndSettle();
    expect(repo.sent.last, isA<NightKill>());

    // Straight on to the check.
    expect(find.text('Check one player: are they the Detective?'), findsOne);
    expect(find.text('Shoot: Kamola'), findsOneWidget);
    await tester.tap(find.text('Otabek'));
    await tester.pump();
    await tester.tap(find.text('Confirm: Otabek'));
    await tester.pumpAndSettle();
    final check = repo.sent.last as NightCheck;
    expect(check.targetId, 'user_5');
    expect(find.text('Done. Waiting for the others…'), findsOneWidget);
  });

  test('every log line the engine writes has words', () {
    final t = AppLocalizationsEn();
    String name(UserId _) => 'Aziza';
    PublicEvent e(String m) =>
        PublicEvent(round: 1, phase: GamePhase.day, message: m, userId: 'u');
    expect(t.eventText(e('playerLeft'), name), 'Aziza left the game');
    expect(t.eventText(e('nobodyVotedOut'), name), isNotNull);
    expect(t.errorText('wrong_phase'), isNull);
    expect(t.errorText('room_full'), 'This room is full.');
    expect(t.errorText('something_new', fallback: 'x'), 'x');
  });
}
