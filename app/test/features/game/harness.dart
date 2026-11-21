import 'package:contracts/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/core/providers.dart';
import 'package:mafia_app/features/game/game_providers.dart';
import 'package:mafia_app/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// Pumps [child] in English with a scripted room and the demo turned off.
Future<FakeRoomRepository> pumpGameUi(
  WidgetTester tester,
  Widget child, {
  FakeRoomRepository? rooms,
}) async {
  final repo = rooms ?? FakeRoomRepository();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        roomRepositoryProvider.overrideWithValue(repo),
        gameDemoEnabledProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: child,
      ),
    ),
  );
  await tester.pump();
  return repo;
}
