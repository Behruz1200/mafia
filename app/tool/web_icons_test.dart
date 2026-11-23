// Draws the browser icons in app/web/ (tab icon, home-screen icons) from the
// same Neon night card fan as the sign-in screen, so they change with it.
//
// Not part of the normal test run. To redraw after a style change:
//   cd app && flutter test tool/web_icons_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/core/theme.dart';
import 'package:mafia_app/features/auth/sign_in_art.dart';
import 'package:material_ui/material_ui.dart';

/// Every icon is laid out on a 512 square and scaled down when saved, so
/// shadows and glows keep their proportions at each size.
const _canvas = 512.0;

void main() {
  setUpAll(() async {
    // Tests draw icons with a placeholder font; load the real one.
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    final bytes = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytesSync();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  testWidgets('draw the web icons', (tester) async {
    // Tests draw shadows without blur unless told otherwise.
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    // Home-screen icons: the whole card fan on the night sky. The browser
    // or phone rounds the corners itself.
    await _save(tester, const _Icon(fan: 300), {
      'web/icons/Icon-192.png': 192,
      'web/icons/Icon-512.png': 512,
    });
    // Maskable icons may be cut to a circle, so the fan keeps to the middle.
    await _save(tester, const _Icon(fan: 250), {
      'web/icons/Icon-maskable-192.png': 192,
      'web/icons/Icon-maskable-512.png': 512,
    });
    // Tab icon: four cards turn to mush at this size, so only the Mafia card,
    // on a rounded tile.
    await _save(tester, const _TabIcon(), {'web/favicon.png': 48});
  });
}

Future<void> _save(
  WidgetTester tester,
  Widget icon,
  Map<String, int> files,
) async {
  final key = GlobalKey();
  tester.view.physicalSize = const Size(_canvas, _canvas);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(dimension: _canvas, child: icon),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  for (final MapEntry(key: path, value: px) in files.entries) {
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: px / _canvas);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(png!.buffer.asUint8List());
    });
  }
}

class _Icon extends StatelessWidget {
  const _Icon({required this.fan});

  /// Height of the card fan on the 512 canvas.
  final double fan;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _Sky()),
        Align(
          alignment: const Alignment(0, -0.04),
          child: RoleCardFan(height: fan),
        ),
      ],
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_canvas * 0.22),
      child: Stack(
        children: [
          const Positioned.fill(child: _Sky()),
          Center(
            child: Transform.rotate(
              angle: 0.14,
              child: Container(
                width: _canvas * 0.52,
                height: _canvas * 0.74,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_canvas * 0.09),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Palette.accent, Palette.accentDeep],
                  ),
                ),
                child: const Icon(
                  Icons.theater_comedy,
                  size: _canvas * 0.36,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sign-in screen's night sky, squeezed into a square.
class _Sky extends StatelessWidget {
  const _Sky();

  @override
  Widget build(BuildContext context) {
    Widget glow(Alignment at, Color color) => Align(
      alignment: at,
      child: Container(
        width: _canvas * 0.9,
        height: _canvas * 0.9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.34), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B0F3A), Palette.background],
        ),
      ),
      child: Stack(
        children: [
          glow(const Alignment(-1.3, -1.1), Palette.accent),
          glow(const Alignment(1.3, 0.6), const Color(0xFF6C4BD8)),
        ],
      ),
    );
  }
}
