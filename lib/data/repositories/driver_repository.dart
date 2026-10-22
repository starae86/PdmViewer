import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../domain/models/jdbc_models.dart';
import '../database/app_database.dart';

class DriverRepository {
  DriverRepository(this.database) : _uuid = const Uuid();

  final AppDatabase database;
  final Uuid _uuid;

  void _validateName(String name, {String? excludingId}) {
    if (name.trim().isEmpty) throw StateError('请填写驱动名称和驱动类名。');
    final rows = database.select(
      'SELECT id FROM jdbc_drivers WHERE LOWER(TRIM(name)) = ? AND (? IS NULL OR id != ?) LIMIT 1',
      [name.trim().toLowerCase(), excludingId, excludingId],
    );
    if (rows.isNotEmpty) throw StateError('驱动名称不能重复。');
  }

  Future<void> ensureBuiltInTemplates() async {
    database.transaction(() {
      for (final template in kJdbcBuiltInDriverTemplates) {
        final rows = database.select(
          '''
          SELECT d.id, d.name, d.created_at,
                 (SELECT COUNT(*) FROM data_sources s WHERE s.driver_id = d.id) AS data_source_refs,
                 (SELECT COUNT(*) FROM reverse_task_presets p WHERE p.driver_id = d.id) AS preset_refs
          FROM jdbc_drivers d
          WHERE is_builtin_template = 1 AND database_type = ?
          ORDER BY created_at, id
          ''',
          [template.databaseType.value],
        );
        if (rows.isNotEmpty) {
          final keeper = _pickBuiltInKeeper(rows, template.name);
          database.execute(
            '''
            UPDATE jdbc_drivers
            SET name = ?, is_builtin_template = 1
            WHERE id = ?
            ''',
            [template.name, keeper['id']],
          );
          for (final row in rows) {
            final driverId = row['id'] as String;
            if (driverId == keeper['id']) {
              continue;
            }
            database.execute(
              'UPDATE data_sources SET driver_id = ? WHERE driver_id = ?',
              [keeper['id'], driverId],
            );
            database.execute(
              'UPDATE reverse_task_presets SET driver_id = ? WHERE driver_id = ?',
              [keeper['id'], driverId],
            );
            database.execute('DELETE FROM jdbc_drivers WHERE id = ?', [
              driverId,
            ]);
          }
          continue;
        }

        final now = DateTime.now().toIso8601String();
        database.execute(
          '''
          INSERT INTO jdbc_drivers (
            id, name, database_type, driver_class, jdbc_url_template, jar_paths,
            is_builtin_template, table_sql, column_sql, column_comment_sql, primary_key_sql,
            notes, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            _uuid.v4(),
            template.name,
            template.databaseType.value,
            template.driverClass,
            template.jdbcUrlTemplate,
            jsonEncode(const <String>[]),
            1,
            '',
            '',
            '',
            '',
            template.notes,
            now,
            now,
          ],
        );
      }
    });
  }

  Future<List<JdbcDriverRecord>> getDrivers() async {
    final rows = database.select('''
      SELECT id, name, database_type, driver_class, jar_paths,
             jdbc_url_template,
             is_builtin_template, table_sql, column_sql, column_comment_sql, primary_key_sql,
             notes, created_at, updated_at
      FROM jdbc_drivers
      ORDER BY is_builtin_template DESC, LOWER(TRIM(name)), created_at
    ''');
    return rows.map(_mapDriver).toList(growable: false);
  }

  Future<JdbcDriverRecord?> getDriverById(String id) async {
    final rows = database.select(
      '''
      SELECT id, name, database_type, driver_class, jar_paths,
             jdbc_url_template,
             is_builtin_template, table_sql, column_sql, column_comment_sql, primary_key_sql,
             notes, created_at, updated_at
      FROM jdbc_drivers
      WHERE id = ?
      LIMIT 1
      ''',
      [id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapDriver(rows.first);
  }

  Future<JdbcDriverRecord> createDriver({
    required String name,
    required JdbcDatabaseType databaseType,
    required String driverClass,
    required String jdbcUrlTemplate,
    required List<String> jarPaths,
    required String tableSql,
    required String columnSql,
    required String columnCommentSql,
    required String primaryKeySql,
    required String notes,
    bool isBuiltInTemplate = false,
  }) async {
    _validateName(name);
    final now = DateTime.now();
    final record = JdbcDriverRecord(
      id: _uuid.v4(),
      name: name.trim(),
      databaseType: databaseType,
      driverClass: driverClass,
      jdbcUrlTemplate: jdbcUrlTemplate,
      jarPaths: List.unmodifiable(jarPaths),
      isBuiltInTemplate: isBuiltInTemplate,
      tableSql: tableSql,
      columnSql: columnSql,
      columnCommentSql: columnCommentSql,
      primaryKeySql: primaryKeySql,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    database.execute(
      '''
      INSERT INTO jdbc_drivers (
        id, name, database_type, driver_class, jdbc_url_template, jar_paths,
        is_builtin_template, table_sql, column_sql, column_comment_sql, primary_key_sql,
        notes, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        record.id,
        record.name,
        record.databaseType.value,
        record.driverClass,
        record.jdbcUrlTemplate,
        jsonEncode(record.jarPaths),
        record.isBuiltInTemplate ? 1 : 0,
        record.tableSql,
        record.columnSql,
        record.columnCommentSql,
        record.primaryKeySql,
        record.notes,
        record.createdAt.toIso8601String(),
        record.updatedAt.toIso8601String(),
      ],
    );
    return record;
  }

  Future<void> updateDriver({
    required String id,
    required String name,
    required JdbcDatabaseType databaseType,
    required String driverClass,
    required String jdbcUrlTemplate,
    required List<String> jarPaths,
    required String tableSql,
    required String columnSql,
    required String columnCommentSql,
    required String primaryKeySql,
    required String notes,
  }) async {
    _validateName(name, excludingId: id);
    database.execute(
      '''
      UPDATE jdbc_drivers
      SET name = ?, database_type = ?, driver_class = ?, jdbc_url_template = ?, jar_paths = ?,
          table_sql = ?, column_sql = ?, column_comment_sql = ?, primary_key_sql = ?,
          notes = ?, updated_at = ?
      WHERE id = ?
      ''',
      [
        name.trim(),
        databaseType.value,
        driverClass,
        jdbcUrlTemplate,
        jsonEncode(jarPaths),
        tableSql,
        columnSql,
        columnCommentSql,
        primaryKeySql,
        notes,
        DateTime.now().toIso8601String(),
        id,
      ],
    );
  }

  Future<void> deleteDriver(String id) async {
    final referencedRows = database.select(
      '''
      SELECT name
      FROM data_sources
      WHERE driver_id = ?
      ORDER BY LOWER(TRIM(name)), created_at
      LIMIT 5
      ''',
      [id],
    );
    if (referencedRows.isNotEmpty) {
      final names = referencedRows
          .map((row) => row['name'] as String? ?? '')
          .where((name) => name.trim().isNotEmpty)
          .toList(growable: false);
      final suffix = names.isEmpty ? '' : '：${names.join('、')}';
      throw StateError('该驱动仍被数据源引用，无法删除$suffix');
    }
    database.execute('DELETE FROM jdbc_drivers WHERE id = ?', [id]);
  }

  JdbcDriverRecord _mapDriver(dynamic row) {
    final jarPathsText = row['jar_paths'] as String? ?? '[]';
    final decoded = jsonDecode(jarPathsText);
    return JdbcDriverRecord(
      id: row['id'] as String,
      name: row['name'] as String,
      databaseType: JdbcDatabaseType.fromValue(row['database_type'] as String),
      driverClass: row['driver_class'] as String,
      jdbcUrlTemplate: row['jdbc_url_template'] as String? ?? '',
      jarPaths: decoded is List
          ? decoded.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
      isBuiltInTemplate: (row['is_builtin_template'] as int) == 1,
      tableSql: _normalizeStoredSql(row['table_sql'] as String? ?? ''),
      columnSql: _normalizeStoredSql(row['column_sql'] as String? ?? ''),
      columnCommentSql: _normalizeStoredSql(
        row['column_comment_sql'] as String? ?? '',
      ),
      primaryKeySql: _normalizeStoredSql(
        row['primary_key_sql'] as String? ?? '',
      ),
      notes: row['notes'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  dynamic _pickBuiltInKeeper(Iterable<dynamic> rows, String canonicalName) {
    dynamic referenced;
    dynamic canonical;
    for (final row in rows) {
      final refCount =
          (row['data_source_refs'] as int? ?? 0) +
          (row['preset_refs'] as int? ?? 0);
      if (refCount > 0 && referenced == null) {
        referenced = row;
      }
      if ((row['name'] as String? ?? '') == canonicalName &&
          canonical == null) {
        canonical = row;
      }
    }
    return referenced ?? canonical ?? rows.first;
  }

  String _normalizeStoredSql(String sql) {
    return sql.replaceAll(
      "COALESCE(c.DATA_DEFAULT, '') AS default_value",
      'c.DATA_DEFAULT AS default_value',
    );
  }
}
