import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/features/lobby/widgets/create_room_sheet.dart';
import 'package:material_ui/material_ui.dart';

import '../game/harness.dart';

void main() {
  testWidgets('create room returns the chosen stake', (tester) async {
    RoomSettings? picked;
    await pumpGameUi(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await showCreateRoomSheet(
              context,
              available: 300,
              canStake: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stake-100')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('createRoomConfirm')));
    await tester.pumpAndSettle();

    expect(picked?.stake, 100);
  });

  testWidgets('stakes are locked for players not verified as adults', (
    tester,
  ) async {
    RoomSettings? picked;
    await pumpGameUi(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await showCreateRoomSheet(
              context,
              available: 5000,
              canStake: false,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('Games for coins are only for players aged 18 and over.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('stake-100')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('createRoomConfirm')));
    await tester.pumpAndSettle();

    expect(picked?.stake, 0);
  });
}
