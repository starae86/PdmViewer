import 'dart:isolate';

import '../../domain/models/pdm_models.dart';
import '../../domain/models/search_models.dart';
import '../database/app_database.dart';

class SearchRepository {
  SearchRepository(this.database);

  final AppDatabase database;

  Future<List<SearchResultItem>> search({
    String? projectId,
    required String keyword,
    required SearchScope scope,
    String? pdmFileId,
  }) async {
    if (keyword.trim().isEmpty) {
      return browse(projectId: projectId, pdmFileId: pdmFileId);
    }
    final databasePath = database.databaseFile.path;
    return Isolate.run(
      () => _searchInBackground(
        databasePath,
        projectId,
        keyword,
        scope,
        pdmFileId,
      ),
    );
  }

  Future<List<SearchResultItem>> _searchLocal({
    String? projectId,
    required String keyword,
    required SearchScope scope,
    String? pdmFileId,
  }) async {
    final normalizedKeyword = keyword.trim().toLowerCase();
    if (normalizedKeyword.isEmpty) {
      return browse(projectId: projectId, pdmFileId: pdmFileId);
    }

    final grouped = <String, _SearchAccumulator>{};
    final pattern = '%${_escapeLike(normalizedKeyword)}%';

    if (scope == SearchScope.all || scope == SearchScope.table) {
      final rows = database.select(
        '''
        SELECT t.id, t.project_id, p.name AS project_name, t.file_id, t.source_table_id,
               t.name, t.code, t.comment, t.source_pdm
        FROM pdm_tables t
        INNER JOIN projects p ON p.id = t.project_id
        WHERE (? IS NULL OR t.project_id = ?)
          AND (? IS NULL OR t.file_id = ?)
          AND (
            LOWER(t.name) LIKE ? ESCAPE '\\'
            OR LOWER(t.code) LIKE ? ESCAPE '\\'
            OR LOWER(t.comment) LIKE ? ESCAPE '\\'
          )
        ''',
        [projectId, projectId, pdmFileId, pdmFileId, pattern, pattern, pattern],
      );

      for (final row in rows) {
        final accumulator = _upsertTable(grouped: grouped, row: row);
        accumulator.matchedByTable = true;
      }
    }

    if (scope == SearchScope.all || scope == SearchScope.column) {
      final rows = database.select(
        '''
        SELECT t.id, t.project_id, p.name AS project_name, t.file_id, t.source_table_id,
               t.name, t.code, t.comment, t.source_pdm, c.source_column_id
        FROM pdm_columns c
        INNER JOIN pdm_tables t ON t.id = c.table_id
        INNER JOIN projects p ON p.id = t.project_id
        WHERE (? IS NULL OR t.project_id = ?)
          AND (? IS NULL OR t.file_id = ?)
          AND (
            LOWER(c.name) LIKE ? ESCAPE '\\'
            OR LOWER(c.code) LIKE ? ESCAPE '\\'
          )
        ''',
        [projectId, projectId, pdmFileId, pdmFileId, pattern, pattern],
      );

      for (final row in rows) {
        final accumulator = _upsertTable(grouped: grouped, row: row);
        accumulator.matchedColumnIds.add(row['source_column_id'] as String);
      }
    }

    final results = grouped.values
        .where(
          (item) => item.matchedByTable || item.matchedColumnIds.isNotEmpty,
        )
        .map((item) => item.build())
        .toList(growable: false);
    return results;
  }

  Future<List<SearchResultItem>> browse({
    String? projectId,
    String? pdmFileId,
    int? limit,
  }) async {
    final sql = StringBuffer('''
      SELECT t.project_id, p.name AS project_name, t.file_id, t.source_table_id,
             t.name, t.code, t.comment, t.source_pdm
      FROM pdm_tables t
      INNER JOIN projects p ON p.id = t.project_id
      WHERE (? IS NULL OR t.project_id = ?)
        AND (? IS NULL OR t.file_id = ?)
      ORDER BY UPPER(CASE WHEN TRIM(t.code) = '' THEN t.name ELSE t.code END),
               t.comment,
               t.source_pdm,
               t.source_table_id
    ''');
    if (limit != null) {
      sql.write(' LIMIT $limit');
    }

    final rows = database.select(sql.toString(), [
      projectId,
      projectId,
      pdmFileId,
      pdmFileId,
    ]);

    return rows
        .map(
          (row) => SearchResultItem(
            id: '${row['project_id']}:${row['file_id']}:${row['source_table_id']}:table',
            projectId: row['project_id'] as String,
            projectName: row['project_name'] as String,
            title: row['name'] as String,
            subtitle: row['code'] as String,
            comment: row['comment'] as String,
            sourcePdm: row['source_pdm'] as String,
            sourceTableId: row['source_table_id'] as String,
            pdmFileId: row['file_id'] as String,
            matchedColumnIds: const [],
            tableName: row['name'] as String,
            tableCode: row['code'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<TableDetail?> getTableDetail({
    required String projectId,
    required String pdmFileId,
    required String sourceTableId,
  }) async {
    final tableRows = database.select(
      '''
      SELECT id, name, code, comment, source_pdm
      FROM pdm_tables
      WHERE project_id = ? AND file_id = ? AND source_table_id = ?
      LIMIT 1
      ''',
      [projectId, pdmFileId, sourceTableId],
    );
    if (tableRows.isEmpty) {
      return null;
    }

    final tableRow = tableRows.first;
    final tableRowId = tableRow['id'] as String;
    final columnRows = database.select(
      '''
      SELECT source_column_id, name, code, comment, data_type, length,
             precision, nullable, default_value, is_primary_key
      FROM pdm_columns
      WHERE table_id = ?
      ORDER BY sort_order
      ''',
      [tableRowId],
    );

    return TableDetail(
      tableName: tableRow['name'] as String,
      tableCode: tableRow['code'] as String,
      comment: tableRow['comment'] as String,
      sourcePdm: tableRow['source_pdm'] as String,
      columns: columnRows
          .map(
            (row) => TableDetailColumn(
              id: row['source_column_id'] as String,
              name: row['name'] as String,
              code: row['code'] as String,
              dataType: row['data_type'] as String,
              length: row['length'] as String,
              precision: row['precision'] as String,
              nullable: (row['nullable'] as int) == 1,
              defaultValue: row['default_value'] as String,
              isPrimaryKey: (row['is_primary_key'] as int) == 1,
              comment: row['comment'] as String,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<Map<String, TableDetail>> getTableDetailsForResults(
    List<SearchResultItem> results,
  ) async {
    if (results.isEmpty) {
      return const {};
    }

    final requestedResults = <String, SearchResultItem>{};
    for (final result in results) {
      final key =
          '${result.projectId}\u0000${result.pdmFileId}\u0000${result.sourceTableId}';
      requestedResults.putIfAbsent(key, () => result);
    }

    final tableRowsById = <String, dynamic>{};
    final sourceKeyByTableId = <String, String>{};
    final uniqueResults = requestedResults.values.toList(growable: false);
    const tableChunkSize = 200;
    for (var start = 0; start < uniqueResults.length; start += tableChunkSize) {
      final end = (start + tableChunkSize).clamp(0, uniqueResults.length);
      final chunk = uniqueResults.sublist(start, end);
      final where = List<String>.filled(
        chunk.length,
        '(project_id = ? AND file_id = ? AND source_table_id = ?)',
      ).join(' OR ');
      final params = <Object?>[];
      for (final result in chunk) {
        params
          ..add(result.projectId)
          ..add(result.pdmFileId)
          ..add(result.sourceTableId);
      }
      final tableRows = database.select('''
        SELECT id, project_id, file_id, source_table_id, name, code, comment, source_pdm
        FROM pdm_tables
        WHERE $where
        ORDER BY project_id, file_id, source_table_id
        ''', params);
      for (final row in tableRows) {
        final sourceKey =
            '${row['project_id']}\u0000${row['file_id']}\u0000${row['source_table_id']}';
        final tableId = row['id'] as String;
        tableRowsById[tableId] = row;
        sourceKeyByTableId[tableId] = sourceKey;
      }
    }

    if (tableRowsById.isEmpty) {
      return const {};
    }

    final columnsByTableId = <String, List<TableDetailColumn>>{};
    final tableIds = tableRowsById.keys.toList(growable: false);
    const chunkSize = 400;
    for (var start = 0; start < tableIds.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, tableIds.length);
      final chunk = tableIds.sublist(start, end);
      final placeholders = List<String>.filled(chunk.length, '?').join(', ');
      final columnRows = database.select('''
        SELECT table_id, source_column_id, name, code, comment, data_type, length,
               precision, nullable, default_value, is_primary_key
        FROM pdm_columns
        WHERE table_id IN ($placeholders)
        ORDER BY table_id, sort_order
        ''', chunk);
      for (final row in columnRows) {
        final tableId = row['table_id'] as String;
        final columns = columnsByTableId.putIfAbsent(
          tableId,
          () => <TableDetailColumn>[],
        );
        columns.add(
          TableDetailColumn(
            id: row['source_column_id'] as String,
            name: row['name'] as String,
            code: row['code'] as String,
            dataType: row['data_type'] as String,
            length: row['length'] as String,
            precision: row['precision'] as String,
            nullable: (row['nullable'] as int) == 1,
            defaultValue: row['default_value'] as String,
            isPrimaryKey: (row['is_primary_key'] as int) == 1,
            comment: row['comment'] as String,
          ),
        );
      }
    }

    final details = <String, TableDetail>{};
    tableRowsById.forEach((tableId, row) {
      final sourceKey = sourceKeyByTableId[tableId];
      if (sourceKey == null) {
        return;
      }
      details[sourceKey] = TableDetail(
        tableName: row['name'] as String,
        tableCode: row['code'] as String,
        comment: row['comment'] as String,
        sourcePdm: row['source_pdm'] as String,
        columns: List<TableDetailColumn>.unmodifiable(
          columnsByTableId[tableId] ?? const <TableDetailColumn>[],
        ),
      );
    });

    return details;
  }

  _SearchAccumulator _upsertTable({
    required Map<String, _SearchAccumulator> grouped,
    required dynamic row,
  }) {
    final key =
        '${row['project_id']}:${row['file_id']}:${row['source_table_id']}';
    return grouped.putIfAbsent(
      key,
      () => _SearchAccumulator(
        id: '$key:table',
        projectId: row['project_id'] as String,
        projectName: row['project_name'] as String,
        title: row['name'] as String,
        subtitle: row['code'] as String,
        comment: row['comment'] as String,
        sourcePdm: row['source_pdm'] as String,
        sourceTableId: row['source_table_id'] as String,
        pdmFileId: row['file_id'] as String,
        tableName: row['name'] as String,
        tableCode: row['code'] as String,
      ),
    );
  }

  String _escapeLike(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }
}

Future<List<SearchResultItem>> _searchInBackground(
  String databasePath,
  String? projectId,
  String keyword,
  SearchScope scope,
  String? pdmFileId,
) async {
  final database = AppDatabase.openReadOnly(databasePath);
  try {
    return await SearchRepository(database)._searchLocal(
      projectId: projectId,
      keyword: keyword,
      scope: scope,
      pdmFileId: pdmFileId,
    );
  } finally {
    database.dispose();
  }
}

class _SearchAccumulator {
  _SearchAccumulator({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.title,
    required this.subtitle,
    required this.comment,
    required this.sourcePdm,
    required this.sourceTableId,
    required this.pdmFileId,
    required this.tableName,
    required this.tableCode,
  });

  final String id;
  final String projectId;
  final String projectName;
  final String title;
  final String subtitle;
  final String comment;
  final String sourcePdm;
  final String sourceTableId;
  final String pdmFileId;
  final String tableName;
  final String tableCode;
  bool matchedByTable = false;
  final Set<String> matchedColumnIds = <String>{};

  SearchResultItem build() {
    final highlights = matchedColumnIds.toList()..sort();
    return SearchResultItem(
      id: id,
      projectId: projectId,
      projectName: projectName,
      title: title,
      subtitle: subtitle,
      comment: comment,
      sourcePdm: sourcePdm,
      sourceTableId: sourceTableId,
      pdmFileId: pdmFileId,
      matchedColumnIds: highlights,
      tableName: tableName,
      tableCode: tableCode,
    );
  }
}
