import 'dart:io';

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
  final server = await io.serve(buildApp(), host, port);
  stdout.writeln('Mafia server listening on $host:${server.port}');
}
