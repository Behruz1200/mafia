import 'package:material_ui/material_ui.dart';

/// App-wide look. Dark by default: the game is played "at night".
abstract final class AppTheme {
  static const _seed = Color(0xFFB71C1C); // deep red

  static ThemeData get dark => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ),
  );

  static ThemeData get light =>
      ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seed));
}
