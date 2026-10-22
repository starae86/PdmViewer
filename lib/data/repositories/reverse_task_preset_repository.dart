import 'package:uuid/uuid.dart';

import '../../domain/models/jdbc_models.dart';
import '../database/app_database.dart';

class ReverseTaskPresetRepository {
  ReverseTaskPresetRepository(this.database) : _uuid = const Uuid();

  final AppDatabase database;
  final Uuid _uuid;

  Future<List<ReverseTaskPreset>> getPresets() async {
    final rows = database.select('''
      SELECT id, name, adapter_type, data_source_id, driver_id, output_path,
             include_table_comments, include_column_comments, schema_name,
             catalog_name, table_names, table_name_prefix, table_name_contains,
             custom_table_sql, custom_column_sql, custom_primary_key_sql,
             created_at, updated_at
      FROM reverse_task_presets
      ORDER BY LOWER(TRIM(name)), created_at
    ''');
    return rows.map(_mapPreset).toList(growable: false);
  }

  Future<ReverseTaskPreset?> getPresetById(String id) async {
    final rows = database.select(
      '''
      SELECT id, name, adapter_type, data_source_id, driver_id, output_path,
             include_table_comments, include_column_comments, schema_name,
             catalog_name, table_names, table_name_prefix, table_name_contains,
             custom_table_sql, custom_column_sql, custom_primary_key_sql,
             created_at, updated_at
      FROM reverse_task_presets
      WHERE id = ?
      LIMIT 1
      ''',
      [id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapPreset(rows.first);
  }

  Future<ReverseTaskPreset> savePreset({
    String? id,
    required String name,
    required ReverseAdapterType adapterType,
    required String dataSourceId,
    required String driverId,
    required String outputPath,
    required bool includeTableComments,
    required bool includeColumnComments,
    required String schemaName,
    required String catalogName,
    required String tableNames,
    required String tableNamePrefix,
    required String tableNameContains,
    required String customTableSql,
    required String customColumnSql,
    required String customPrimaryKeySql,
  }) async {
    final existingId = id ?? _uuid.v4();
    final existing = id == null ? null : await getPresetById(id);
    final now = DateTime.now();
    final record = ReverseTaskPreset(
      id: existingId,
      name: name,
      adapterType: adapterType,
      dataSourceId: dataSourceId,
      driverId: driverId,
      outputPath: outputPath,
      includeTableComments: includeTableComments,
      includeColumnComments: includeColumnComments,
      schemaName: schemaName,
      catalogName: catalogName,
      tableNames: tableNames,
      tableNamePrefix: tableNamePrefix,
      tableNameContains: tableNameContains,
      customTableSql: customTableSql,
      customColumnSql: customColumnSql,
      customPrimaryKeySql: customPrimaryKeySql,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    database.execute(
      '''
      INSERT INTO reverse_task_presets (
        id, name, adapter_type, data_source_id, driver_id, output_path,
        include_table_comments, include_column_comments, schema_name,
        catalog_name, table_names, table_name_prefix, table_name_contains,
        custom_table_sql, custom_column_sql, custom_primary_key_sql,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        adapter_type = excluded.adapter_type,
        data_source_id = excluded.data_source_id,
        driver_id = excluded.driver_id,
        output_path = excluded.output_path,
        include_table_comments = excluded.include_table_comments,
        include_column_comments = excluded.include_column_comments,
        schema_name = excluded.schema_name,
        catalog_name = excluded.catalog_name,
        table_names = excluded.table_names,
        table_name_prefix = excluded.table_name_prefix,
        table_name_contains = excluded.table_name_contains,
        custom_table_sql = excluded.custom_table_sql,
        custom_column_sql = excluded.custom_column_sql,
        custom_primary_key_sql = excluded.custom_primary_key_sql,
        updated_at = excluded.updated_at
      ''',
      [
        record.id,
        record.name,
        record.adapterType.value,
        record.dataSourceId,
        record.driverId,
        record.outputPath,
        record.includeTableComments ? 1 : 0,
        record.includeColumnComments ? 1 : 0,
        record.schemaName,
        record.catalogName,
        record.tableNames,
        record.tableNamePrefix,
        record.tableNameContains,
        record.customTableSql,
        record.customColumnSql,
        record.customPrimaryKeySql,
        record.createdAt.toIso8601String(),
        record.updatedAt.toIso8601String(),
      ],
    );
    return record;
  }

  Future<void> deletePreset(String id) async {
    database.execute('DELETE FROM reverse_task_presets WHERE id = ?', [id]);
  }

  ReverseTaskPreset _mapPreset(dynamic row) {
    return ReverseTaskPreset(
      id: row['id'] as String,
      name: row['name'] as String,
      adapterType: ReverseAdapterType.fromValue(row['adapter_type'] as String),
      dataSourceId: row['data_source_id'] as String,
      driverId: row['driver_id'] as String,
      outputPath: row['output_path'] as String,
      includeTableComments: (row['include_table_comments'] as int) == 1,
      includeColumnComments: (row['include_column_comments'] as int) == 1,
      schemaName: row['schema_name'] as String,
      catalogName: row['catalog_name'] as String,
      tableNames: row['table_names'] as String,
      tableNamePrefix: row['table_name_prefix'] as String,
      tableNameContains: row['table_name_contains'] as String,
      customTableSql: row['custom_table_sql'] as String,
      customColumnSql: row['custom_column_sql'] as String,
      customPrimaryKeySql: row['custom_primary_key_sql'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
