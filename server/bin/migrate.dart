import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:server/src/migrate.dart';

/// Brings the database up to date with `server/migrations`.
///
/// Production runs it before every server start (`ExecStartPre` in
/// `deploy/production/systemd/mafia-server.service`); local Docker runs it
/// as the `migrate` service. Without `DATABASE_URL` there is nothing to do.
Future<void> main() async {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    stdout.writeln('migrate: DATABASE_URL is not set; nothing to do');
    return;
  }
  final dir = findMigrationsDir();
  final db = Pool<void>.withUrl(url);
  try {
    final applied = await applyMigrations(
      db,
      dir,
      log: (m) => stdout.writeln('migrate: $m'),
    );
    stdout.writeln(
      applied.isEmpty
          ? 'migrate: database is up to date'
          : 'migrate: applied ${applied.length} file(s)',
    );
  } on Object catch (e) {
    stderr.writeln('migrate: failed: $e');
    exitCode = 1;
  } finally {
    await db.close();
  }
}
