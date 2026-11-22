import 'dart:io';

import 'package:postgres/postgres.dart';

/// Applies the SQL files in [dir] (`NNNN_<stream>_<what>.sql`) in name
/// order, each one once, and records them in `schema_migrations`.
///
/// Safe to run on every start: files already recorded are skipped, and an
/// advisory lock keeps two runs from applying the same file at once. The
/// whole run is one transaction: if any file fails, nothing is applied and
/// the error is thrown. Returns the names it applied.
Future<List<String>> applyMigrations(
  SessionExecutor db,
  Directory dir, {
  void Function(String)? log,
}) async {
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => _name(a).compareTo(_name(b)));
  if (files.isEmpty) {
    throw StateError('No migrations found in ${dir.path}');
  }

  final applied = <String>[];
  await db.runTx((tx) async {
    // One run at a time; released when this transaction ends.
    await tx.execute("SELECT pg_advisory_xact_lock(hashtext('mafia:migrate'))");
    await tx.execute(
      'CREATE TABLE IF NOT EXISTS schema_migrations ('
      'name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())',
    );
    final done = {
      for (final r in await tx.execute('SELECT name FROM schema_migrations'))
        r[0]! as String,
    };
    for (final f in files) {
      final name = _name(f);
      if (done.contains(name)) continue;
      log?.call('applying $name');
      await tx.execute(
        await f.readAsString(),
        // Simple protocol so a file with several statements runs at once.
        queryMode: QueryMode.simple,
      );
      await tx.execute(
        Sql.named('INSERT INTO schema_migrations (name) VALUES (@n)'),
        parameters: {'n': name},
      );
      applied.add(name);
    }
  });
  return applied;
}

String _name(File f) => f.uri.pathSegments.last;

/// Where the migrations are: `MIGRATIONS_DIR` if set, else a `migrations`
/// folder next to the compiled binary (production and Docker), else
/// `migrations` in the working directory (`dart run` from `server/`).
Directory findMigrationsDir([Map<String, String>? env]) {
  final e = env ?? Platform.environment;
  final fromEnv = e['MIGRATIONS_DIR'];
  if (fromEnv != null && fromEnv.isNotEmpty) return Directory(fromEnv);
  final besideBinary = Directory.fromUri(
    File(Platform.resolvedExecutable).parent.uri.resolve('migrations/'),
  );
  if (besideBinary.existsSync()) return besideBinary;
  return Directory('migrations');
}
