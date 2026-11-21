import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/features/shop/shop_screen.dart';
import 'package:mafia_app/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

Widget _app() => const ProviderScope(
  child: MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ShopScreen(),
  ),
);

void main() {
  testWidgets('shows the balance, the no cash-out rule and packs', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('1000 coins'), findsOneWidget);
    expect(find.textContaining("can't be exchanged for money"), findsOneWidget);
    expect(find.text('550 coins'), findsOneWidget);
    expect(find.text('+50 bonus'), findsOneWidget);
    expect(find.text('No coin activity yet'), findsOneWidget);
  });

  testWidgets('buying a pack adds its coins', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('buy-coins_500')));
    await tester.pumpAndSettle();

    expect(find.text('1550 coins'), findsOneWidget);
    expect(find.text('+550 coins added'), findsOneWidget);
  });
}
