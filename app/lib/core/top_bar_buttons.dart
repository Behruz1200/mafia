import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/generated/app_localizations.dart';
import 'locale.dart';
import 'theme.dart';

/// A small "🌐 UZ" pill that opens a menu of the app's languages. Switching
/// changes every screen at once and is remembered on this device.
class LanguageButton extends ConsumerWidget {
  const LanguageButton({super.key, this.compact = false});

  /// Tighter, for a crowded top bar.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final current = Localizations.localeOf(context).languageCode;
    return PopupMenuButton<String>(
      key: const ValueKey('language-button'),
      tooltip: t.languageTitle,
      position: PopupMenuPosition.under,
      color: Palette.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onSelected: (code) =>
          ref.read(appLocaleProvider.notifier).set(Locale(code)),
      itemBuilder: (context) => [
        for (final l in supportedAppLocales)
          PopupMenuItem(
            key: ValueKey('language-${l.languageCode}'),
            value: l.languageCode,
            child: Row(
              spacing: 12,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    l.languageCode.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: Palette.display,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Palette.muted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    appLanguageNames[l.languageCode]!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (l.languageCode == current)
                  const Icon(Icons.check_rounded, color: Palette.cyan),
              ],
            ),
          ),
      ],
      child: Container(
        height: 40,
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
        decoration: BoxDecoration(
          color: Palette.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.outlineSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: compact ? 4 : 6,
          children: [
            Icon(
              Icons.language_rounded,
              size: compact ? 16 : 18,
              color: Palette.cyan,
            ),
            Text(
              current.toUpperCase(),
              style: const TextStyle(
                fontFamily: Palette.display,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The three languages side by side, the current one lit. For the profile
/// screen, where there is room for the names in full.
class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = Localizations.localeOf(context).languageCode;
    return SegmentedButton<String>(
      key: const ValueKey('language-picker'),
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        backgroundColor: Palette.surfaceHigh,
        selectedBackgroundColor: Palette.cyan,
        selectedForegroundColor: Palette.background,
        side: const BorderSide(color: Palette.outlineSoft),
        minimumSize: const Size.fromHeight(48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      segments: [
        for (final l in supportedAppLocales)
          ButtonSegment(
            value: l.languageCode,
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                appLanguageNames[l.languageCode]!,
                key: ValueKey('language-${l.languageCode}'),
                maxLines: 1,
              ),
            ),
          ),
      ],
      selected: {current},
      onSelectionChanged: (picked) =>
          ref.read(appLocaleProvider.notifier).set(Locale(picked.first)),
    );
  }
}
