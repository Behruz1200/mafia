import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/app.dart';
import 'package:mafia_app/features/game/game_providers.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // Regression: leaving a room used to leave the lobby stuck "busy", so the
  // next Quick match / Create room tap did nothing.
  testWidgets('after leaving a room, Quick match opens a room again', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameDemoEnabledProvider.overrideWithValue(false)],
        child: const MafiaApp(),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Quick match'));
      await tester.pumpAndSettle();
      expect(
        find.text('Waiting for players'),
        findsOneWidget,
        reason: 'try $i',
      );

      await tester.tap(find.byTooltip('Leave'));
      await tester.pumpAndSettle();
      expect(find.text('Quick match'), findsOneWidget);
    }
  });
}
