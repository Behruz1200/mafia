import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/features/game/widgets/player_table.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

Widget _table({
  Set<UserId> selectable = const {},
  ValueChanged<UserId>? onSelect,
}) => Scaffold(
  body: Padding(
    padding: const EdgeInsets.all(16),
    child: PlayerTable(
      players: samplePublicState().players,
      me: 'user_0',
      selectable: selectable,
      onSelect: onSelect,
      face: (id, placeholder) =>
          KeyedSubtree(key: ValueKey('face-$id'), child: placeholder),
    ),
  ),
);

void main() {
  test('phones get 2 cameras across up to 4 players, then 3', () {
    expect(PlayerTable.columnsFor(361, 1), 2);
    expect(PlayerTable.columnsFor(361, 4), 2);
    expect(PlayerTable.columnsFor(361, 5), 3);
    expect(PlayerTable.columnsFor(361, 12), 3);
    expect(PlayerTable.columnsFor(900, 12), 6);
  });

  testWidgets('cameras fill a phone-wide table', (tester) async {
    await pumpGameUi(tester, _table());
    await tester.pumpAndSettle();
    // 8 players on a 432-wide screen: 3 across, each well over 84 wide.
    final seat = tester.getSize(find.byKey(const ValueKey('seat-user_1')));
    expect(seat.width, greaterThan(120));
    expect(seat.height, greaterThan(seat.width));
  });

  testWidgets('tapping a camera opens it full screen and swipes on', (
    tester,
  ) async {
    await pumpGameUi(tester, _table());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('seat-user_3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('seat-camera-viewer')), findsOneWidget);
    expect(find.text('4 · Jasur'), findsOneWidget);
    final big = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('seat-camera-viewer')),
        matching: find.byKey(const ValueKey('face-user_3')),
      ),
    );
    expect(big.width, 432);

    await tester.tap(find.byKey(const ValueKey('seat-camera-user_0')));
    await tester.pumpAndSettle();
    expect(find.text('1 · You'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('close-seat-camera')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('seat-camera-viewer')), findsNothing);
  });

  testWidgets('while picking, a tap picks and holding opens the camera', (
    tester,
  ) async {
    UserId? picked;
    await pumpGameUi(
      tester,
      _table(selectable: {'user_3'}, onSelect: (u) => picked = u),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('seat-user_3')));
    await tester.pumpAndSettle();
    expect(picked, 'user_3');
    expect(find.byKey(const ValueKey('seat-camera-viewer')), findsNothing);

    // Not a target: a tap does nothing.
    await tester.tap(find.byKey(const ValueKey('seat-user_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('seat-camera-viewer')), findsNothing);

    await tester.longPress(find.byKey(const ValueKey('seat-user_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('seat-camera-viewer')), findsOneWidget);
    expect(picked, 'user_3');
  });
}
