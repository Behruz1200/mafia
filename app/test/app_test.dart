import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/app.dart';
import 'package:mafia_app/core/locale.dart';
import 'package:mafia_app/features/profile/profile_screen.dart';
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

  testWidgets(
    'the language picker in the profile switches the app and remembers it',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('uz')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final store = MemoryLocaleStore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [localeStoreProvider.overrideWithValue(store)],
          child: const MafiaApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tezkor o‘yin'), findsOneWidget);

      // Home has no language button: it lives in the profile.
      expect(find.byKey(const ValueKey('language-button')), findsNothing);
      await tester.tap(find.byTooltip('Profil'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('language-en')),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ProfileScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const ValueKey('language-en')));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Quick match'), findsOneWidget);
      expect(store.languageCode, 'en');
    },
  );

  testWidgets('a saved language wins over the phone language', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('uz')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeStoreProvider.overrideWithValue(MemoryLocaleStore('ru')),
        ],
        child: const MafiaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Быстрая игра'), findsOneWidget);
  });
}
