import 'dart:async';

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

/// A round "refresh" button for screens that can look stuck (home, the
/// waiting room, the table). It spins until [onPressed] is done.
class RefreshButton extends StatefulWidget {
  const RefreshButton({super.key, required this.onPressed, this.size = 40});

  final Future<void> Function() onPressed;
  final double size;

  @override
  State<RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<RefreshButton>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    unawaited(_spin.repeat());
    try {
      await widget.onPressed();
    } finally {
      _spin
        ..stop()
        ..reset();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('refresh-button'),
      tooltip: AppLocalizations.of(context).refresh,
      onPressed: _busy ? null : _run,
      style: IconButton.styleFrom(
        fixedSize: Size.square(widget.size),
        minimumSize: Size.square(widget.size),
        backgroundColor: Palette.surfaceHigh,
        disabledBackgroundColor: Palette.surfaceHigh,
        foregroundColor: Palette.text,
        disabledForegroundColor: Palette.cyan,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Palette.outlineSoft),
        ),
      ),
      icon: RotationTransition(
        turns: _spin,
        child: const Icon(Icons.refresh_rounded, size: 20),
      ),
    );
  }
}
