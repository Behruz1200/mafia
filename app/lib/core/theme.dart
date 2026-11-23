import 'package:material_ui/material_ui.dart';

/// The app's look: "Neon night". Deep violet, bold rounded headings
/// (Unbounded), a friendly body face (Manrope), one hot accent for the main
/// action, cyan for the town and gold for coins.
///
/// Every colour and font lives in [Palette]; widgets read these or the
/// [ThemeData] below, so the whole app changes from this one file.
abstract final class Palette {
  static const background = Color(0xFF0E0A1F);
  static const surface = Color(0xFF1A1433);
  static const surfaceHigh = Color(0xFF241C45);
  static const surfaceSheet = Color(0xFF150F2C);
  static const outline = Color(0xFF3A3266);
  static const outlineSoft = Color(0xFF2A2350);

  static const accent = Color(0xFFFF3B5C);
  static const accentDeep = Color(0xFFB0123A);
  static const cyan = Color(0xFF2EE6D6);
  static const gold = Color(0xFFFFC83D);
  static const lavender = Color(0xFFA996FF);
  static const sun = Color(0xFFFFB547);
  static const error = Color(0xFFFF6B7D);

  static const text = Color(0xFFFFFFFF);
  static const muted = Color(0xFFA49DC4);

  /// Headings, numbers, the logo.
  static const display = 'Unbounded';

  /// Everything else.
  static const body = 'Manrope';
}

abstract final class AppTheme {
  static const _radius = 18.0;
  static final _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_radius),
  );

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: Palette.accent,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF4A1530),
      onPrimaryContainer: Colors.white,
      secondary: Palette.cyan,
      onSecondary: Palette.background,
      secondaryContainer: Palette.surfaceHigh,
      onSecondaryContainer: Colors.white,
      tertiary: Palette.gold,
      onTertiary: Color(0xFF2E2200),
      error: Palette.error,
      onError: Colors.white,
      surface: Palette.background,
      onSurface: Palette.text,
      onSurfaceVariant: Palette.muted,
      surfaceContainerLowest: Color(0xFF0A0717),
      surfaceContainerLow: Color(0xFF130E29),
      surfaceContainer: Palette.surface,
      surfaceContainerHigh: Palette.surfaceHigh,
      surfaceContainerHighest: Color(0xFF2C2352),
      outline: Palette.outline,
      outlineVariant: Palette.outlineSoft,
      inverseSurface: Colors.white,
      onInverseSurface: Palette.background,
    );

    final base = ThemeData(
      colorScheme: scheme,
      brightness: Brightness.dark,
      fontFamily: Palette.body,
    );
    final text = base.textTheme;
    TextStyle? display(TextStyle? s, FontWeight w) => s?.copyWith(
      fontFamily: Palette.display,
      fontWeight: w,
      letterSpacing: -0.3,
    );
    final textTheme = text.copyWith(
      displayLarge: display(text.displayLarge, FontWeight.w800),
      displayMedium: display(text.displayMedium, FontWeight.w800),
      displaySmall: display(text.displaySmall, FontWeight.w800),
      headlineLarge: display(text.headlineLarge, FontWeight.w800),
      headlineMedium: display(text.headlineMedium, FontWeight.w800),
      headlineSmall: display(text.headlineSmall, FontWeight.w700),
      titleLarge: display(
        text.titleLarge,
        FontWeight.w600,
      )?.copyWith(fontSize: 20),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      bodyMedium: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      bodySmall: text.bodySmall?.copyWith(color: Palette.muted),
    );

    const buttonText = TextStyle(
      fontFamily: Palette.body,
      fontWeight: FontWeight.w800,
      fontSize: 16,
    );

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: Palette.background,
      canvasColor: Palette.background,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Palette.text,
        titleTextStyle: TextStyle(
          fontFamily: Palette.display,
          fontWeight: FontWeight.w600,
          fontSize: 18,
          color: Palette.text,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Palette.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Palette.surfaceHigh,
          disabledForegroundColor: Palette.muted,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: _shape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Palette.text,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: const BorderSide(color: Palette.outline, width: 1.5),
          shape: _shape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Palette.cyan,
          shape: _shape,
          textStyle: buttonText.copyWith(fontSize: 15),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        labelStyle: const TextStyle(color: Palette.muted),
        hintStyle: const TextStyle(color: Palette.muted),
        floatingLabelStyle: const TextStyle(color: Palette.cyan),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Palette.outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Palette.cyan, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Palette.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Palette.error, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: Palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Palette.surface,
        selectedColor: Palette.accent,
        disabledColor: Palette.surface.withValues(alpha: 0.5),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(
          fontFamily: Palette.body,
          fontWeight: FontWeight.w700,
          color: Palette.text,
        ),
        secondaryLabelStyle: const TextStyle(
          fontFamily: Palette.body,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
        checkmarkColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Palette.surfaceSheet,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: Palette.outline,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: const TextStyle(
          fontFamily: Palette.display,
          fontWeight: FontWeight.w600,
          fontSize: 19,
          color: Palette.text,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: Palette.body,
          fontWeight: FontWeight.w500,
          fontSize: 15,
          height: 1.4,
          color: Palette.muted,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Palette.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: Palette.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Palette.surfaceHigh,
        contentTextStyle: const TextStyle(
          fontFamily: Palette.body,
          fontWeight: FontWeight.w600,
          color: Palette.text,
        ),
        actionTextColor: Palette.cyan,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: Palette.muted,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      dividerTheme: const DividerThemeData(
        color: Palette.outlineSoft,
        thickness: 1,
        space: 1,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: Palette.accent,
        inactiveTrackColor: Palette.surfaceHigh,
        thumbColor: Colors.white,
        valueIndicatorColor: Palette.accent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Colors.white : Palette.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Palette.accent
              : Palette.surfaceHigh,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Palette.accent,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: Palette.muted,
        collapsedIconColor: Palette.muted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Palette.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(color: Palette.text),
      ),
    );
  }

  /// The game is played "at night": the app is always dark. Kept so the
  /// app can still pass a light theme to MaterialApp.
  static ThemeData get light => dark;
}
