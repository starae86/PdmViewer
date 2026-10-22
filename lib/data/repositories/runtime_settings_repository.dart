import '../../domain/models/jdbc_models.dart';
import '../database/app_database.dart';

class RuntimeSettingsRepository {
  RuntimeSettingsRepository(this.database);

  static const String jdkHomeKey = 'jdkHome';

  final AppDatabase database;

  Future<void> setSetting(String key, String value) async {
    database.execute(
      '''
      INSERT INTO app_runtime_settings (key, value, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value,
        updated_at = excluded.updated_at
      ''',
      [key, value, DateTime.now().toIso8601String()],
    );
  }

  Future<String?> getJdkHome() async {
    final rows = database.select(
      '''
      SELECT value
      FROM app_runtime_settings
      WHERE key = ?
      LIMIT 1
      ''',
      [jdkHomeKey],
    );
    if (rows.isEmpty) {
      return null;
    }
    final value = (rows.first['value'] as String).trim();
    return value.isEmpty ? null : value;
  }

  Future<void> setJdkHome(String? value) async {
    if (value == null || value.trim().isEmpty) {
      database.execute('DELETE FROM app_runtime_settings WHERE key = ?', [
        jdkHomeKey,
      ]);
      return;
    }

    final now = DateTime.now().toIso8601String();
    database.execute(
      '''
      INSERT INTO app_runtime_settings (key, value, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value,
        updated_at = excluded.updated_at
      ''',
      [jdkHomeKey, value.trim(), now],
    );
  }

  Future<AppRuntimeSetting?> getSetting(String key) async {
    final rows = database.select(
      '''
      SELECT key, value, updated_at
      FROM app_runtime_settings
      WHERE key = ?
      LIMIT 1
      ''',
      [key],
    );
    if (rows.isEmpty) {
      return null;
    }
    return AppRuntimeSetting(
      key: rows.first['key'] as String,
      value: rows.first['value'] as String,
      updatedAt: DateTime.parse(rows.first['updated_at'] as String),
    );
  }
}
