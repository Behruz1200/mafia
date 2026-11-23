import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/app.dart';
import 'package:mafia_app/core/last_room.dart';
import 'package:mafia_app/core/providers.dart';
import 'package:mafia_app/features/game/game_providers.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // After a reload, an app restart or in a second browser tab the app opened
  // on the home screen, the player went offline and the server forfeited
  // their stake 60 s later. Now the home screen takes them back.
  Future<void> pump(
    WidgetTester tester, {
    required LastRoomStore store,
    required Room room,
  }) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameDemoEnabledProvider.overrideWithValue(false),
          lastRoomStoreProvider.overrideWithValue(store),
          roomRepositoryProvider.overrideWithValue(
            FakeRoomRepository(room: room),
          ),
        ],
        child: const MafiaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opens the room the player is still seated in', (tester) async {
    final store = MemoryLastRoomStore('room_1');
    await pump(tester, store: store, room: sampleRoom());
    expect(find.text('Waiting for players'), findsOneWidget);
    expect(store.roomId, 'room_1');
  });

  testWidgets('stays home and forgets a room that is closed', (tester) async {
    final store = MemoryLastRoomStore('room_1');
    final closed = sampleRoom();
    await pump(
      tester,
      store: store,
      room: Room(
        id: closed.id,
        inviteCode: closed.inviteCode,
        hostId: closed.hostId,
        status: RoomStatus.closed,
        settings: closed.settings,
        memberIds: closed.memberIds,
        createdAt: closed.createdAt,
      ),
    );
    expect(find.text('Quick match'), findsOneWidget);
    expect(store.roomId, isNull);
  });

  testWidgets('leaving the room forgets it', (tester) async {
    final store = MemoryLastRoomStore();
    await pump(tester, store: store, room: sampleRoom());
    await tester.tap(find.text('Quick match'));
    await tester.pumpAndSettle();
    expect(store.roomId, 'room_1');
    await tester.tap(find.byTooltip('Leave'));
    await tester.pumpAndSettle();
    expect(store.roomId, isNull);
    expect(find.text('Quick match'), findsOneWidget);
  });
}
