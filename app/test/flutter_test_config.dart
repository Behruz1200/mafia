import 'dart:async';

import 'package:mafia_app/features/game/ui/noir_art.dart';

/// Runs before every test file in this folder.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // The night city on the home screen moves forever; tests wait for the
  // screen to settle, so keep it still here.
  NightCity.animationsEnabled = false;
  await testMain();
}
