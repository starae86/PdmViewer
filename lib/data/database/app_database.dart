import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

import '../services/app_storage_directory.dart';

class AppDatabase {
  AppDatabase._({
    required this.rootDirectory,
    required this.databaseFile,
    required Database database,
  }) : _database = database;

  final Directory rootDirectory;
  final File databaseFile;
  final Database _database;

  /// A worker connection must not run schema initialization or modify settings.
  static AppDatabase openReadOnly(String databasePath) {
    final file = File(databasePath);
    final database = sqlite3.open(databasePath, mode: OpenMode.readOnly);
    database.execute('PRAGMA busy_timeout = 5000');
    return AppDatabase._(
      rootDirectory: file.parent,
      databaseFile: file,
      database: database,
    );
  }

  static Future<AppDatabase> open({String? databasePath}) async {
    final resolvedPath = databasePath ?? await _defaultDatabasePath();
    final file = File(resolvedPath);
    final directory = file.parent;
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    final database = sqlite3.open(file.path);
    final appDatabase = AppDatabase._(
      rootDirectory: directory,
      databaseFile: file,
      database: database,
    );
    appDatabase._initialize();
    return appDatabase;
  }

  ResultSet select(String sql, [List<Object?> parameters = const <Object?>[]]) {
    return _database.select(sql, parameters);
  }

  void execute(String sql, [List<Object?> parameters = const <Object?>[]]) {
    _database.execute(sql, parameters);
  }

  T transaction<T>(T Function() action) {
    _database.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      _database.execute('COMMIT');
      return result;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void dispose() {
    _database.close();
  }

  static Future<String> _defaultDatabasePath() async {
    final appDir = await AppStorageDirectory.resolve();
    final databaseFile = File(path.join(appDir.path, 'PdmViewer.db'));
    final legacyFile = File(path.join(appDir.path, 'pdm_viewer.db'));
    if (!await databaseFile.exists() && await legacyFile.exists()) {
      // Keep SQLite sidecars with the database during the one-time rename.
      for (final suffix in ['-wal', '-shm', '-journal', '']) {
        final source = File('${legacyFile.path}$suffix');
        if (await source.exists()) {
          await source.rename('${databaseFile.path}$suffix');
        }
      }
    }
    return databaseFile.path;
  }

  void _initialize() {
    _database.execute('PRAGMA foreign_keys = ON');
    _database.execute('PRAGMA journal_mode = WAL');
    _database.execute('PRAGMA synchronous = NORMAL');

    _database.execute('''
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    _database.execute('''
      CREATE TABLE IF NOT EXISTS project_files (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        path TEXT NOT NULL,
        display_name TEXT NOT NULL,
        last_imported_at TEXT,
        last_imported_hash TEXT,
        import_error TEXT,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
        UNIQUE(project_id, path)
      )
    ''');

    _database.execute('''
      CREATE TABLE IF NOT EXISTS pdm_tables (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        file_id TEXT NOT NULL,
        source_table_id TEXT NOT NULL,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        comment TEXT NOT NULL,
        source_pdm TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
        FOREIGN KEY (file_id) REFERENCES project_files(id) ON DELETE CASCADE,
        UNIQUE(project_id, file_id, source_table_id)
      )
    ''');

    _database.execute('''
      CREATE TABLE IF NOT EXISTS pdm_columns (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        file_id TEXT NOT NULL,
        table_id TEXT NOT NULL,
        source_column_id TEXT NOT NULL,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        comment TEXT NOT NULL,
        data_type TEXT NOT NULL,
        length TEXT NOT NULL,
        precision TEXT NOT NULL,
        nullable INTEGER NOT NULL,
        default_value TEXT NOT NULL,
        is_primary_key INTEGER NOT NULL,
        sort_order INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
        FOREIGN KEY (file_id) REFERENCES project_files(id) ON DELETE CASCADE,
        FOREIGN KEY (table_id) REFERENCES pdm_tables(id) ON DELETE CASCADE,
        UNIQUE(project_id, file_id, table_id, source_column_id)
      )
    ''');

    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_project_files_project ON project_files(project_id)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_pdm_tables_project_file ON pdm_tables(project_id, file_id, sort_order)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_pdm_columns_table ON pdm_columns(table_id, sort_order)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_pdm_tables_search ON pdm_tables(project_id, file_id, code, name, comment)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_pdm_columns_search ON pdm_columns(project_id, file_id, code, name)',
    );

    _database.execute('''
      CREATE TABLE IF NOT EXISTS jdbc_drivers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        database_type TEXT NOT NULL,
        driver_class TEXT NOT NULL,
        jdbc_url_template TEXT NOT NULL DEFAULT '',
        jar_paths TEXT NOT NULL,
        is_builtin_template INTEGER NOT NULL,
        table_sql TEXT NOT NULL DEFAULT '',
        column_sql TEXT NOT NULL DEFAULT '',
        column_comment_sql TEXT NOT NULL DEFAULT '',
        primary_key_sql TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _ensureColumn(
      table: 'jdbc_drivers',
      column: 'jdbc_url_template',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _ensureColumn(
      table: 'jdbc_drivers',
      column: 'table_sql',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _ensureColumn(
      table: 'jdbc_drivers',
      column: 'column_sql',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _ensureColumn(
      table: 'jdbc_drivers',
      column: 'column_comment_sql',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _ensureColumn(
      table: 'jdbc_drivers',
      column: 'primary_key_sql',
      definition: "TEXT NOT NULL DEFAULT ''",
    );

    _database.execute('''
      CREATE TABLE IF NOT EXISTS data_sources (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        database_type TEXT NOT NULL,
        driver_id TEXT NOT NULL,
        jdbc_url TEXT NOT NULL,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        schema_name TEXT NOT NULL,
        catalog_name TEXT NOT NULL,
        last_connection_status TEXT NOT NULL,
        last_error TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (driver_id) REFERENCES jdbc_drivers(id) ON DELETE RESTRICT
      )
    ''');

    _database.execute('''
      CREATE TABLE IF NOT EXISTS reverse_task_presets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        adapter_type TEXT NOT NULL,
        data_source_id TEXT NOT NULL,
        driver_id TEXT NOT NULL,
        output_path TEXT NOT NULL,
        include_table_comments INTEGER NOT NULL,
        include_column_comments INTEGER NOT NULL,
        schema_name TEXT NOT NULL,
        catalog_name TEXT NOT NULL,
        table_names TEXT NOT NULL,
        table_name_prefix TEXT NOT NULL,
        table_name_contains TEXT NOT NULL,
        custom_table_sql TEXT NOT NULL,
        custom_column_sql TEXT NOT NULL,
        custom_primary_key_sql TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (data_source_id) REFERENCES data_sources(id) ON DELETE CASCADE,
        FOREIGN KEY (driver_id) REFERENCES jdbc_drivers(id) ON DELETE CASCADE
      )
    ''');

    _database.execute('''
      CREATE TABLE IF NOT EXISTS app_runtime_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_data_sources_driver ON data_sources(driver_id)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_reverse_presets_source ON reverse_task_presets(data_source_id)',
    );
  }

  void _ensureColumn({
    required String table,
    required String column,
    required String definition,
  }) {
    final rows = _database.select('PRAGMA table_info($table)');
    final hasColumn = rows.any((row) => row['name'] == column);
    if (hasColumn) {
      return;
    }
    _database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}
