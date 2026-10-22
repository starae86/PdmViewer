import 'package:uuid/uuid.dart';

import '../../domain/models/jdbc_models.dart';
import '../database/app_database.dart';

class DataSourceRepository {
  DataSourceRepository(this.database) : _uuid = const Uuid();

  final AppDatabase database;
  final Uuid _uuid;

  void _validateName(String name, {String? excludingId}) {
    if (name.trim().isEmpty) throw StateError('请填写数据源名称。');
    final rows = database.select(
      'SELECT id FROM data_sources WHERE LOWER(TRIM(name)) = ? AND (? IS NULL OR id != ?) LIMIT 1',
      [name.trim().toLowerCase(), excludingId, excludingId],
    );
    if (rows.isNotEmpty) throw StateError('数据源名称不能重复。');
  }

  Future<List<DataSourceRecord>> getDataSources() async {
    final rows = database.select('''
      SELECT id, name, database_type, driver_id, jdbc_url, username, password,
             schema_name, catalog_name, last_connection_status, last_error,
             created_at, updated_at
      FROM data_sources
      ORDER BY LOWER(TRIM(name)), created_at
    ''');
    return rows.map(_mapRecord).toList(growable: false);
  }

  Future<DataSourceRecord?> getDataSourceById(String id) async {
    final rows = database.select(
      '''
      SELECT id, name, database_type, driver_id, jdbc_url, username, password,
             schema_name, catalog_name, last_connection_status, last_error,
             created_at, updated_at
      FROM data_sources
      WHERE id = ?
      LIMIT 1
      ''',
      [id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapRecord(rows.first);
  }

  Future<DataSourceRecord> createDataSource({
    required String name,
    required JdbcDatabaseType databaseType,
    required String driverId,
    required String jdbcUrl,
    required String username,
    required String password,
    required String schemaName,
    required String catalogName,
  }) async {
    _validateName(name);
    final now = DateTime.now();
    final record = DataSourceRecord(
      id: _uuid.v4(),
      name: name.trim(),
      databaseType: databaseType,
      driverId: driverId,
      jdbcUrl: jdbcUrl,
      username: username,
      password: password,
      schemaName: schemaName,
      catalogName: catalogName,
      lastConnectionStatus: ConnectionHealthStatus.unknown,
      lastError: '',
      createdAt: now,
      updatedAt: now,
    );
    database.execute(
      '''
      INSERT INTO data_sources (
        id, name, database_type, driver_id, jdbc_url, username, password,
        schema_name, catalog_name, last_connection_status, last_error,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        record.id,
        record.name,
        record.databaseType.value,
        record.driverId,
        record.jdbcUrl,
        record.username,
        record.password,
        record.schemaName,
        record.catalogName,
        record.lastConnectionStatus.value,
        record.lastError,
        record.createdAt.toIso8601String(),
        record.updatedAt.toIso8601String(),
      ],
    );
    return record;
  }

  Future<void> updateDataSource({
    required String id,
    required String name,
    required JdbcDatabaseType databaseType,
    required String driverId,
    required String jdbcUrl,
    required String username,
    required String password,
    required String schemaName,
    required String catalogName,
  }) async {
    _validateName(name, excludingId: id);
    database.execute(
      '''
      UPDATE data_sources
      SET name = ?, database_type = ?, driver_id = ?, jdbc_url = ?,
          username = ?, password = ?, schema_name = ?, catalog_name = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        name.trim(),
        databaseType.value,
        driverId,
        jdbcUrl,
        username,
        password,
        schemaName,
        catalogName,
        DateTime.now().toIso8601String(),
        id,
      ],
    );
  }

  Future<void> deleteDataSource(String id) async {
    database.execute('DELETE FROM data_sources WHERE id = ?', [id]);
  }

  Future<void> updateConnectionStatus({
    required String id,
    required ConnectionHealthStatus status,
    required String errorMessage,
  }) async {
    database.execute(
      '''
      UPDATE data_sources
      SET last_connection_status = ?, last_error = ?, updated_at = ?
      WHERE id = ?
      ''',
      [status.value, errorMessage, DateTime.now().toIso8601String(), id],
    );
  }

  DataSourceRecord _mapRecord(dynamic row) {
    return DataSourceRecord(
      id: row['id'] as String,
      name: row['name'] as String,
      databaseType: JdbcDatabaseType.fromValue(row['database_type'] as String),
      driverId: row['driver_id'] as String,
      jdbcUrl: row['jdbc_url'] as String,
      username: row['username'] as String,
      password: row['password'] as String,
      schemaName: row['schema_name'] as String,
      catalogName: row['catalog_name'] as String,
      lastConnectionStatus: ConnectionHealthStatus.fromValue(
        row['last_connection_status'] as String,
      ),
      lastError: row['last_error'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
