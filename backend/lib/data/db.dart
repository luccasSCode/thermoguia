import 'package:postgres/postgres.dart';

import '../config.dart';
import 'schema.dart';

typedef TxQuery = Future<List<Map<String, dynamic>>> Function(String sql, [Map<String, Object?> params]);

/// Acesso ao PostgreSQL com pool de conexões.
class Db {
  Db._(this._pool);
  final Pool _pool;

  static Future<Db> connect(Config c) async {
    final pool = Pool.withEndpoints(
      [
        Endpoint(
          host: c.dbHost,
          port: c.dbPort,
          database: c.dbName,
          username: c.dbUser,
          password: c.dbPassword,
        ),
      ],
      settings: PoolSettings(maxConnectionCount: 10, sslMode: SslMode.disable),
    );
    final db = Db._(pool);
    await db._migrate();
    return db;
  }

  Future<void> _migrate() =>
      _pool.execute(schemaSql, queryMode: QueryMode.simple);

  Future<List<Map<String, dynamic>>> query(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async {
    final result = await _pool.execute(Sql.named(sql), parameters: params);
    return result.map((r) => r.toColumnMap()).toList();
  }

  Future<Map<String, dynamic>?> one(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async {
    final rows = await query(sql, params);
    return rows.isEmpty ? null : rows.first;
  }

  /// Executa [fn] numa transação (tudo ou nada). [fn] recebe uma função de
  /// consulta igual a [query], ligada à transação.
  Future<T> tx<T>(Future<T> Function(TxQuery q) fn) => _pool.runTx((s) => fn(
        (sql, [params = const {}]) async =>
            (await s.execute(Sql.named(sql), parameters: params)).map((r) => r.toColumnMap()).toList(),
      ));

  Future<void> close() => _pool.close();
}
