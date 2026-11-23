import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/locale.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'l10n/generated/app_localizations.dart';

export 'core/locale.dart' show supportedAppLocales;

class MafiaApp extends ConsumerWidget {
  const MafiaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      // The player's pick from the language button, else the phone's.
      locale: ref.watch(appLocaleProvider),
      supportedLocales: supportedAppLocales,
      // Built by hand rather than AppLocalizations.localizationsDelegates,
      // because the Material strings must come from package:material_ui.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
    );
  }
}
