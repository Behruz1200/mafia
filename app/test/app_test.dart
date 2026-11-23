import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/app.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('opens on the lobby in Uzbek with fake services', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('uz')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const ProviderScope(child: MafiaApp()));
    await tester.pumpAndSettle();

    expect(find.text('Tezkor o‘yin'), findsOneWidget);
    expect(find.text('1000 tanga'), findsOneWidget);
  });

  testWidgets('falls back to Uzbek for an unsupported language', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const ProviderScope(child: MafiaApp()));
    await tester.pumpAndSettle();

    expect(find.text('Tezkor o‘yin'), findsOneWidget);
  });

  testWidgets('shows Russian when the phone is in Russian', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const ProviderScope(child: MafiaApp()));
    await tester.pumpAndSettle();

    expect(find.text('Быстрая игра'), findsOneWidget);
  });
}
