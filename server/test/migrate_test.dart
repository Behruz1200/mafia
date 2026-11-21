import 'dart:io';
import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:server/src/migrate.dart';
import 'package:test/test.dart';

/// Needs `TEST_DATABASE_URL` with a role that may create databases; each
/// run uses its own throwaway database.
void main() {
  final url = Platform.environment['TEST_DATABASE_URL'];
  if (url == null) {
    test('migrations', () {}, skip: 'TEST_DATABASE_URL is not set');
    return;
  }

  late Connection admin;
  late String name;
  late Pool<void> db;

  setUp(() async {
    admin = await Connection.openFromUrl(url);
    name = 'migrate_test_${Random().nextInt(1 << 32)}';
    await admin.execute('CREATE DATABASE $name');
    db = Pool<void>.withUrl(Uri.parse(url).replace(path: '/$name').toString());
  });

  tearDown(() async {
    await db.close();
    await admin.execute('DROP DATABASE IF EXISTS $name WITH (FORCE)');
    await admin.close();
  });

  test('applies every file once, in name order, then nothing', () async {
    final files =
        Directory('migrations')
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where((n) => n.endsWith('.sql'))
            .toList()
          ..sort();

    final first = await applyMigrations(db, Directory('migrations'));
    expect(first, files);
    expect(await applyMigrations(db, Directory('migrations')), isEmpty);

    // One table from each stream exists.
    for (final table in ['users', 'rooms_matches', 'ledger', 'wallets']) {
      final rows = await db.execute(
        Sql.named('SELECT to_regclass(@t)::text'),
        parameters: {'t': table},
      );
      expect(rows.single[0], table);
    }
  });

  test('a failing file changes nothing and stops the run', () async {
    final dir = await Directory.systemTemp.createTemp('migrations');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/0001_a.sql').writeAsStringSync('CREATE TABLE a (x int);');
    File('${dir.path}/0002_b.sql').writeAsStringSync('NOT SQL;');

    await expectLater(applyMigrations(db, dir), throwsA(anything));
    final rows = await db.execute("SELECT to_regclass('a')::text");
    expect(rows.single[0], isNull);
  });
}
