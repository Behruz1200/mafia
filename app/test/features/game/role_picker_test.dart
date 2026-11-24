import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/features/game/game_screen.dart';
import 'package:mafia_app/features/game/story/story_scenes.dart';
import 'package:mafia_app/features/game/story/story_script.dart';
import 'package:mafia_app/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

Room _room({
  String host = 'user_0',
  Map<Role, int>? roles,
  bool public = false,
}) {
  final r = sampleRoom(stake: 0);
  return Room(
    id: r.id,
    inviteCode: r.inviteCode,
    hostId: host,
    status: r.status,
    settings: RoomSettings(
      roleCounts: roles,
      visibility: public ? RoomVisibility.public : RoomVisibility.private,
    ),
    memberIds: r.memberIds,
    memberNames: r.memberNames,
    createdAt: r.createdAt,
  );
}

Finder _chip(Role r) => find.byKey(ValueKey('role-chip-${r.name}'));

void main() {
  testWidgets('everyone sees the standard deal for the seated players', (
    tester,
  ) async {
    await pumpGameUi(
      tester,
      const GameScreen(roomId: 'room_1'),
      rooms: FakeRoomRepository(room: _room(host: 'user_3')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(_chip(Role.civilian));

    expect(find.text('Standard deal, by player count'), findsOneWidget);
    // 8 players: Don, Mafia, Detective, Doctor and 4 Civilians.
    expect(_chip(Role.don), findsOneWidget);
    expect(_chip(Role.maniac), findsNothing);
    expect(find.text('×4'), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-roles')), findsNothing);
  });

  testWidgets('the host adds the Maniac and a Bodyguard', (tester) async {
    final repo = await pumpGameUi(
      tester,
      const GameScreen(roomId: 'room_1'),
      rooms: FakeRoomRepository(room: _room()),
    );
    await tester.pumpAndSettle();
    final edit = find.byKey(const ValueKey('edit-roles'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('standard-deal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-maniac')));
    await tester.pump();
    final guard = find.byKey(const ValueKey('add-bodyguard'));
    await tester.ensureVisible(guard);
    await tester.tap(guard);
    await tester.pump();
    // One of a kind: no second Maniac.
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const ValueKey('add-maniac')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('save-roles')));
    await tester.pumpAndSettle();

    expect(repo.room.settings.roleCounts, {
      Role.don: 1,
      Role.mafia: 1,
      Role.detective: 1,
      Role.doctor: 1,
      Role.maniac: 1,
      Role.bodyguard: 1,
    });
    await tester.ensureVisible(_chip(Role.maniac));
    expect(find.text('Picked by you'), findsOneWidget);
    expect(_chip(Role.bodyguard), findsOneWidget);
  });

  testWidgets('an unfair setup cannot be saved', (tester) async {
    await pumpGameUi(
      tester,
      const GameScreen(roomId: 'room_1'),
      rooms: FakeRoomRepository(room: _room(roles: {Role.mafia: 2})),
    );
    await tester.pumpAndSettle();
    final edit = find.byKey(const ValueKey('edit-roles'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    // 8 players: 2 Mafia + Maniac + one more Mafia is 4 of 8.
    await tester.tap(find.byKey(const ValueKey('add-maniac')));
    await tester.tap(find.byKey(const ValueKey('add-mafia')));
    await tester.pump();
    expect(find.textContaining('Too many Mafia'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-roles')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('players are told when the host changes the roles', (
    tester,
  ) async {
    final repo = await pumpGameUi(
      tester,
      const GameScreen(roomId: 'room_1'),
      rooms: FakeRoomRepository(room: _room(host: 'user_3')),
    );
    await tester.pumpAndSettle();
    repo.emitRoom(
      _room(host: 'user_3', roles: {Role.mafia: 1, Role.immortal: 1}),
    );
    await tester.pumpAndSettle();
    expect(find.text('The host changed the roles'), findsOneWidget);
    await tester.ensureVisible(_chip(Role.immortal));
    await tester.tap(_chip(Role.immortal));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't be killed at night"), findsOneWidget);
  });

  testWidgets('quick match rooms have no Edit', (tester) async {
    await pumpGameUi(
      tester,
      const GameScreen(roomId: 'room_1'),
      rooms: FakeRoomRepository(room: _room(public: true)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(_chip(Role.civilian));
    expect(find.byKey(const ValueKey('edit-roles')), findsNothing);
  });

  group('story with the newer roles', () {
    const roles = {
      'user_0': Role.civilian,
      'user_1': Role.maniac,
      'user_2': Role.bodyguard,
      'user_3': Role.mafia,
      'user_4': Role.hypnotist,
      'user_5': Role.immortal,
      'user_6': Role.doctor,
      'user_7': Role.civilian,
    };
    final result = MatchResult(
      roomId: 'room_1',
      matchId: 'match_1',
      stake: 0,
      winningTeam: Team.maniac,
      winners: const ['user_1'],
      losers: [
        for (final id in roles.keys)
          if (id != 'user_1') id,
      ],
      roles: roles,
      story: const MatchStory(
        nights: [
          StoryNight(
            round: 1,
            target: 'user_0',
            shooters: ['user_3'],
            hypnotistId: 'user_4',
            slept: 'user_6',
            bodyguardId: 'user_2',
            guarded: 'user_0',
            attacks: [
              StoryAttack(
                shooters: ['user_3'],
                target: 'user_0',
                bodyguardId: 'user_2',
                outcome: ShotOutcome.died,
              ),
              StoryAttack(
                shooters: ['user_1'],
                target: 'user_5',
                byManiac: true,
                outcome: ShotOutcome.immortal,
              ),
            ],
          ),
        ],
      ),
      endedAt: DateTime.utc(2026, 11, 24),
    );

    test('sleep, then the Mafia shot, then the Maniac shot', () {
      final scenes = storyScenes(result);
      expect(scenes.map((s) => s.runtimeType.toString()), [
        'SleepScene',
        'ShotScene',
        'ShotScene',
        'FinaleScene',
      ]);
      final mafia = scenes[1] as ShotScene;
      expect(mafia.bodyguard, 'user_2');
      expect(mafia.hit, 'user_2');
      expect(mafia.killed, isTrue);
      final maniac = scenes[2] as ShotScene;
      expect(maniac.byManiac, isTrue);
      expect(maniac.immortal, isTrue);
      expect(maniac.killed, isFalse);
      expect((scenes.last as FinaleScene).winner, Team.maniac);
    });

    testWidgets('every scene draws', (tester) async {
      final cast = StoryCast(
        names: {for (final p in samplePlayers()) p.userId: p.displayName},
        roles: result.roles,
        winners: result.winners,
        me: 'user_0',
      );
      for (final scene in storyScenes(result)) {
        for (final at in [0.0, 1.0, 2.0, 3.0, 4.5]) {
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('ru'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              home: Builder(
                builder: (context) {
                  final t = AppLocalizations.of(context);
                  final text = sceneText(scene, cast, t);
                  return ListView(
                    children: [
                      SceneStage(scene: scene, cast: cast, t: at),
                      for (final c in text.captions) Text(c.text),
                    ],
                  );
                },
              ),
            ),
          );
          expect(tester.takeException(), isNull);
        }
      }
    });
  });
}
