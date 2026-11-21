import 'dart:io';

import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  // ServerConfig.fromEnvironment() is read by modules once they need the
  // database, JWT or LiveKit settings.
  final server = await io.serve(buildApp(), InternetAddress.anyIPv4, port);
  stdout.writeln('Mafia server listening on :${server.port}');
}
