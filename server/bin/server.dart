import 'dart:io';

import 'package:server/auth/auth_module.dart';
import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final env = Platform.environment;
  final port = int.parse(env['PORT'] ?? '8080');
  // Production sets HOST=127.0.0.1 so only nginx on the same machine can
  // reach the server. Docker (local dev) needs all interfaces.
  final host = env['HOST'] ?? '0.0.0.0';
  // ServerConfig.fromEnvironment() is read by modules once they need the
  // database, JWT or LiveKit settings.
  // Built here (not inside buildApp) so recovery below uses the same one.
  final auth = AuthModule();
  final rooms = defaultRooms(auth);
  final server = await io.serve(buildApp(rooms: rooms, auth: auth), host, port);
  stdout.writeln('Mafia server listening on $host:${server.port}');
  // Settle any match a previous run left with coins in escrow.
  try {
    final n = await rooms.service.recoverUnsettled();
    if (n > 0) stdout.writeln('Settled $n unfinished matches');
  } on Object catch (e) {
    stderr.writeln('Could not check for unfinished matches: $e');
  }
}
