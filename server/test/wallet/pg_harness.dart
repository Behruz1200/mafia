import 'dart:io';
import 'dart:math';

import 'package:postgres/postgres.dart';

/// Wallet tests run against a real PostgreSQL. Set `TEST_DATABASE_URL` to a
/// role that may create databases, e.g.
/// `postgres://mafia_test:test@localhost:5432/mafia_test`. Each test file
/// gets its own throwaway database with every migration applied.
/// Without the variable the tests are skipped.
final testDatabaseUrl = Platform.environment['TEST_DATABASE_URL'];

String? get skipWithoutDatabase =>
    testDatabaseUrl == null ? 'Set TEST_DATABASE_URL to run' : null;

class TestDatabase {
  TestDatabase._(this._admin, this.name, this.pool);

  final Connection _admin;
  final String name;
  final Pool<void> pool;

  static Future<TestDatabase> create() async {
    final base = Uri.parse(testDatabaseUrl!);
    final admin = await Connection.openFromUrl(testDatabaseUrl!);
    final name = 'wallet_test_${Random().nextInt(1 << 32)}';
    await admin.execute('CREATE DATABASE $name');
    final url = base.replace(path: '/$name', query: 'sslmode=disable');
    final pool = Pool<void>.withUrl(url.toString());

    final dir = Directory('migrations');
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      await pool.execute(f.readAsStringSync(), queryMode: QueryMode.simple);
    }
    return TestDatabase._(admin, name, pool);
  }

  Future<void> dispose() async {
    await pool.close();
    await _admin.execute('DROP DATABASE IF EXISTS $name WITH (FORCE)');
    await _admin.close();
  }
}
