import 'dart:io';

import 'package:server/rooms/rooms_module.dart';
import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  // ServerConfig.fromEnvironment() is read by modules once they need the
  // database, JWT or LiveKit settings.
  final rooms = RoomsModule.fromEnvironment();
  final server = await io.serve(
    buildApp(rooms: rooms),
    InternetAddress.anyIPv4,
    port,
  );
  stdout.writeln('Mafia server listening on :${server.port}');
  // Settle any match a previous run left with coins in escrow.
  try {
    final n = await rooms.service.recoverUnsettled();
    if (n > 0) stdout.writeln('Settled $n unfinished matches');
  } on Object catch (e) {
    stderr.writeln('Could not check for unfinished matches: $e');
  }
}
