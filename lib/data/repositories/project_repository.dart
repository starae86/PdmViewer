import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../domain/models/pdm_models.dart';
import '../../domain/models/project.dart';
import '../database/app_database.dart';

class ProjectRepository {
  ProjectRepository(this.database) : _uuid = const Uuid();

  final AppDatabase database;
  final Uuid _uuid;

  Future<List<ProjectRecord>> getProjects() async {
    final rows = database.select('''
      SELECT id, name, created_at, updated_at
      FROM projects
      ORDER BY LOWER(TRIM(name)), created_at
    ''');
    return rows.map(_mapProject).toList(growable: false);
  }

  Future<ProjectRecord> createProject(String name) async {
    final now = DateTime.now();
    final project = ProjectRecord(
      id: _uuid.v4(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    database.execute(
      '''
      INSERT INTO projects (id, name, created_at, updated_at)
      VALUES (?, ?, ?, ?)
      ''',
      [
        project.id,
        project.name,
        project.createdAt.toIso8601String(),
        project.updatedAt.toIso8601String(),
      ],
    );
    return project;
  }

  Future<void> renameProject(String projectId, String name) async {
    database.execute(
      '''
      UPDATE projects
      SET name = ?, updated_at = ?
      WHERE id = ?
      ''',
      [name, DateTime.now().toIso8601String(), projectId],
    );
  }

  Future<void> deleteProject(String projectId) async {
    database.execute('DELETE FROM projects WHERE id = ?', [projectId]);
  }

  Future<List<ProjectPdmFileRecord>> getProjectFiles(String projectId) async {
    final rows = database.select(
      '''
      SELECT id, project_id, path, display_name, last_imported_at,
             last_imported_hash, import_error
      FROM project_files
      WHERE project_id = ?
      ORDER BY LOWER(display_name), path
      ''',
      [projectId],
    );
    return rows.map(_mapProjectFile).toList(growable: false);
  }

  Future<ProjectPdmFileRecord> upsertProjectFile({
    required String projectId,
    required String filePath,
  }) async {
    final existingRows = database.select(
      '''
      SELECT id, project_id, path, display_name, last_imported_at,
             last_imported_hash, import_error
      FROM project_files
      WHERE project_id = ? AND path = ?
      LIMIT 1
      ''',
      [projectId, filePath],
    );
    if (existingRows.isNotEmpty) {
      return _mapProjectFile(existingRows.first);
    }

    final record = ProjectPdmFileRecord(
      id: _uuid.v4(),
      projectId: projectId,
      path: filePath,
      displayName: path.basename(filePath),
      lastImportedAt: null,
      lastImportedHash: null,
      importError: null,
    );
    database.execute(
      '''
      INSERT INTO project_files (
        id, project_id, path, display_name, last_imported_at,
        last_imported_hash, import_error
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        record.id,
        record.projectId,
        record.path,
        record.displayName,
        null,
        null,
        null,
      ],
    );
    return record;
  }

  Future<List<ProjectPdmFileRecord>> upsertProjectFiles({
    required String projectId,
    required List<String> filePaths,
  }) async {
    final records = <ProjectPdmFileRecord>[];
    database.transaction(() {
      for (final filePath in filePaths) {
        final existingRows = database.select(
          '''
          SELECT id, project_id, path, display_name, last_imported_at,
                 last_imported_hash, import_error
          FROM project_files
          WHERE project_id = ? AND path = ?
          LIMIT 1
          ''',
          [projectId, filePath],
        );
        if (existingRows.isNotEmpty) {
          records.add(_mapProjectFile(existingRows.first));
          continue;
        }

        final record = ProjectPdmFileRecord(
          id: _uuid.v4(),
          projectId: projectId,
          path: filePath,
          displayName: path.basename(filePath),
          lastImportedAt: null,
          lastImportedHash: null,
          importError: null,
        );
        database.execute(
          '''
          INSERT INTO project_files (
            id, project_id, path, display_name, last_imported_at,
            last_imported_hash, import_error
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            record.id,
            record.projectId,
            record.path,
            record.displayName,
            null,
            null,
            null,
          ],
        );
        records.add(record);
      }
    });
    return records;
  }

  Future<void> removeProjectFile({
    required String projectId,
    required String fileId,
  }) async {
    database.transaction(() {
      database.execute(
        'DELETE FROM project_files WHERE id = ? AND project_id = ?',
        [fileId, projectId],
      );
      _touchProject(projectId);
    });
  }

  Future<void> replaceProjectIndex({
    required String projectId,
    required String fileId,
    required ParsedPdmFile parsed,
    required String lastImportedHash,
  }) async {
    final update = ProjectPdmImportUpdate(
      projectId: projectId,
      fileId: fileId,
      parsedFile: parsed,
      lastImportedHash: lastImportedHash,
    );
    await applyProjectImportUpdates(updates: [update]);
  }

  Future<void> applyProjectImportUpdates({
    required List<ProjectPdmImportUpdate> updates,
  }) async {
    if (updates.isEmpty) {
      return;
    }

    database.transaction(() {
      final nowIso = DateTime.now().toIso8601String();
      final touchedProjectIds = <String>{};

      for (final update in updates) {
        touchedProjectIds.add(update.projectId);
        if (update.parsedFile != null) {
          _replaceFileIndex(
            projectId: update.projectId,
            fileId: update.fileId,
            parsed: update.parsedFile!,
          );
          database.execute(
            '''
            UPDATE project_files
            SET last_imported_at = ?, last_imported_hash = ?, import_error = ?,
                display_name = ?, path = ?
            WHERE id = ? AND project_id = ?
            ''',
            [
              nowIso,
              update.lastImportedHash,
              null,
              update.parsedFile!.sourceName,
              update.parsedFile!.sourcePath,
              update.fileId,
              update.projectId,
            ],
          );
        } else if (update.importError != null) {
          database.execute(
            '''
            UPDATE project_files
            SET import_error = ?
            WHERE id = ? AND project_id = ?
            ''',
            [update.importError, update.fileId, update.projectId],
          );
        }
      }

      for (final projectId in touchedProjectIds) {
        _touchProject(projectId, updatedAtIso: nowIso);
      }
    });
  }

  Future<void> markImportError({
    required String fileId,
    required String message,
  }) async {
    database.execute(
      'UPDATE project_files SET import_error = ? WHERE id = ?',
      [message, fileId],
    );
  }

  Future<ProjectWorkspaceStats> getWorkspaceStats(String? projectId) async {
    final projectCount = _singleInt(
      database.select('SELECT COUNT(*) AS count FROM projects'),
    );

    if (projectId == null) {
      return ProjectWorkspaceStats(
        projectCount: projectCount,
        fileCount: 0,
        tableCount: 0,
        columnCount: 0,
        errorFileCount: 0,
      );
    }

    final fileCount = _singleInt(
      database.select(
        'SELECT COUNT(*) AS count FROM project_files WHERE project_id = ?',
        [projectId],
      ),
    );
    final tableCount = _singleInt(
      database.select(
        'SELECT COUNT(*) AS count FROM pdm_tables WHERE project_id = ?',
        [projectId],
      ),
    );
    final columnCount = _singleInt(
      database.select(
        'SELECT COUNT(*) AS count FROM pdm_columns WHERE project_id = ?',
        [projectId],
      ),
    );
    final errorFileCount = _singleInt(
      database.select(
        '''
        SELECT COUNT(*) AS count
        FROM project_files
        WHERE project_id = ? AND TRIM(COALESCE(import_error, '')) <> ''
        ''',
        [projectId],
      ),
    );

    return ProjectWorkspaceStats(
      projectCount: projectCount,
      fileCount: fileCount,
      tableCount: tableCount,
      columnCount: columnCount,
      errorFileCount: errorFileCount,
    );
  }

  void _replaceFileIndex({
    required String projectId,
    required String fileId,
    required ParsedPdmFile parsed,
  }) {
    database.execute(
      'DELETE FROM pdm_columns WHERE project_id = ? AND file_id = ?',
      [projectId, fileId],
    );
    database.execute(
      'DELETE FROM pdm_tables WHERE project_id = ? AND file_id = ?',
      [projectId, fileId],
    );

    for (var tableIndex = 0; tableIndex < parsed.tables.length; tableIndex++) {
      final table = parsed.tables[tableIndex];
      final tableRowId = '$projectId:$fileId:${table.id}';
      database.execute(
        '''
        INSERT INTO pdm_tables (
          id, project_id, file_id, source_table_id, name, code, comment,
          source_pdm, sort_order
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          tableRowId,
          projectId,
          fileId,
          table.id,
          table.name,
          table.code,
          table.comment,
          parsed.sourceName,
          tableIndex,
        ],
      );

      for (
        var columnIndex = 0;
        columnIndex < table.columns.length;
        columnIndex++
      ) {
        final column = table.columns[columnIndex];
        database.execute(
          '''
          INSERT INTO pdm_columns (
            id, project_id, file_id, table_id, source_column_id, name, code,
            comment, data_type, length, precision, nullable, default_value,
            is_primary_key, sort_order
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            '$tableRowId:${column.id}',
            projectId,
            fileId,
            tableRowId,
            column.id,
            column.name,
            column.code,
            column.comment,
            column.dataType,
            column.length,
            column.precision,
            column.nullable ? 1 : 0,
            column.defaultValue,
            column.isPrimaryKey ? 1 : 0,
            columnIndex,
          ],
        );
      }
    }
  }

  void _touchProject(String projectId, {String? updatedAtIso}) {
    database.execute(
      'UPDATE projects SET updated_at = ? WHERE id = ?',
      [updatedAtIso ?? DateTime.now().toIso8601String(), projectId],
    );
  }

  int _singleInt(Iterable<dynamic> rows) {
    if (rows.isEmpty) {
      return 0;
    }
    final row = rows.first;
    final value = row['count'];
    if (value is int) {
      return value;
    }
    if (value is BigInt) {
      return value.toInt();
    }
    return int.tryParse(value.toString()) ?? 0;
  }

  ProjectRecord _mapProject(dynamic row) {
    return ProjectRecord(
      id: row['id'] as String,
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  ProjectPdmFileRecord _mapProjectFile(dynamic row) {
    final importedAt = row['last_imported_at'] as String?;
    return ProjectPdmFileRecord(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      path: row['path'] as String,
      displayName: row['display_name'] as String,
      lastImportedAt: importedAt == null ? null : DateTime.parse(importedAt),
      lastImportedHash: row['last_imported_hash'] as String?,
      importError: row['import_error'] as String?,
    );
  }
}
