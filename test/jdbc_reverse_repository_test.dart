import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pdm_viewer/data/database/app_database.dart';
import 'package:pdm_viewer/data/repositories/data_source_repository.dart';
import 'package:pdm_viewer/data/repositories/driver_repository.dart';
import 'package:pdm_viewer/data/repositories/reverse_task_preset_repository.dart';
import 'package:pdm_viewer/data/repositories/runtime_settings_repository.dart';
import 'package:pdm_viewer/data/services/java_runtime_resolver.dart';
import 'package:pdm_viewer/data/services/jdbc_reverse_service.dart';
import 'package:pdm_viewer/domain/models/jdbc_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('driver and source names are unique on create and update', () async {
    final temp = await Directory.systemTemp.createTemp('PdmViewerUniqueNames');
    final db = await AppDatabase.open(
      databasePath: path.join(temp.path, 'state.db'),
    );
    addTearDown(() async {
      db.dispose();
      await temp.delete(recursive: true);
    });
    final drivers = DriverRepository(db);
    final sources = DataSourceRepository(db);
    Future<JdbcDriverRecord> createDriver(String name) => drivers.createDriver(
      name: name,
      databaseType: JdbcDatabaseType.mysql,
      driverClass: 'example.Driver',
      jdbcUrlTemplate: '',
      jarPaths: [],
      tableSql: '',
      columnSql: '',
      columnCommentSql: '',
      primaryKeySql: '',
      notes: '',
    );
    final first = await createDriver('Driver');
    final second = await createDriver('Other');
    await expectLater(createDriver(' DRIVER '), throwsStateError);
    Future<void> renameDriver(String id, String name) => drivers.updateDriver(
      id: id,
      name: name,
      databaseType: JdbcDatabaseType.mysql,
      driverClass: 'example.Driver',
      jdbcUrlTemplate: '',
      jarPaths: [],
      tableSql: '',
      columnSql: '',
      columnCommentSql: '',
      primaryKeySql: '',
      notes: '',
    );
    await expectLater(renameDriver(second.id, ' driver '), throwsStateError);
    await renameDriver(first.id, ' Driver ');
    expect((await drivers.getDriverById(first.id))!.name, 'Driver');
    Future<DataSourceRecord> createSource(String name) =>
        sources.createDataSource(
          name: name,
          databaseType: JdbcDatabaseType.mysql,
          driverId: first.id,
          jdbcUrl: 'jdbc:example',
          username: 'reader',
          password: 'test',
          schemaName: '',
          catalogName: '',
        );
    final source = await createSource('Source');
    final other = await createSource('Other');
    await expectLater(createSource(' SOURCE '), throwsStateError);
    Future<void> renameSource(String id, String name) =>
        sources.updateDataSource(
          id: id,
          name: name,
          databaseType: JdbcDatabaseType.mysql,
          driverId: first.id,
          jdbcUrl: 'jdbc:example',
          username: 'reader',
          password: 'test',
          schemaName: '',
          catalogName: '',
        );
    await expectLater(renameSource(other.id, ' source '), throwsStateError);
    await renameSource(source.id, ' Source ');
    expect((await sources.getDataSourceById(source.id))!.name, 'Source');
  });

  test('persists jdbc drivers, data sources, presets and jdk home', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'pdm_viewer_jdbc_repo_test',
    );
    final database = await AppDatabase.open(
      databasePath: path.join(tempDir.path, 'state.db'),
    );
    addTearDown(() async {
      database.dispose();
      await tempDir.delete(recursive: true);
    });
    final driverRepository = DriverRepository(database);
    final dataSourceRepository = DataSourceRepository(database);
    final presetRepository = ReverseTaskPresetRepository(database);
    final runtimeSettingsRepository = RuntimeSettingsRepository(database);

    await driverRepository.ensureBuiltInTemplates();
    final builtInDrivers = await driverRepository.getDrivers();
    expect(
      builtInDrivers.where((item) => item.isBuiltInTemplate),
      hasLength(6),
    );

    final customDriver = await driverRepository.createDriver(
      name: '自定义 PostgreSQL 驱动',
      databaseType: JdbcDatabaseType.postgresql,
      driverClass: 'org.postgresql.Driver',
      jdbcUrlTemplate: 'jdbc:postgresql://127.0.0.1:5432/demo',
      jarPaths: const ['D:/drivers/postgresql.jar'],
      tableSql: 'select 1 as table_name, 1 as table_code, 1 as table_comment',
      columnSql:
          'select 1 as table_name, 1 as column_name, 1 as column_code, 1 as data_type, 1 as length, 0 as precision, 1 as nullable, 1 as default_value, 1 as column_comment, 1 as ordinal_position',
      columnCommentSql:
          'select 1 as table_name, 1 as column_name, 1 as column_comment',
      primaryKeySql: 'select 1 as table_name, 1 as column_name',
      notes: '测试驱动',
    );
    final legacyOracleDriver = await driverRepository.createDriver(
      name: '旧 Oracle SQL',
      databaseType: JdbcDatabaseType.oracle,
      driverClass: 'oracle.jdbc.driver.OracleDriver',
      jdbcUrlTemplate: 'jdbc:oracle:thin:@127.0.0.1:1521/orcl',
      jarPaths: const ['D:/drivers/ojdbc8.jar'],
      tableSql: 'select 1 as table_name, 1 as table_code, 1 as table_comment',
      columnSql:
          "select COALESCE(c.DATA_DEFAULT, '') AS default_value from ALL_TAB_COLUMNS c",
      columnCommentSql: '',
      primaryKeySql: 'select 1 as table_name, 1 as column_name',
      notes: 'legacy oracle sql',
    );

    final dataSource = await dataSourceRepository.createDataSource(
      name: '本地 PG',
      databaseType: JdbcDatabaseType.postgresql,
      driverId: customDriver.id,
      jdbcUrl: 'jdbc:postgresql://127.0.0.1:5432/demo',
      username: 'demo',
      password: 'secret',
      schemaName: 'public',
      catalogName: 'demo',
    );

    final preset = await presetRepository.savePreset(
      name: '默认逆向配置',
      adapterType: ReverseAdapterType.customSql,
      dataSourceId: dataSource.id,
      driverId: customDriver.id,
      outputPath: 'D:/temp/demo.pdm',
      includeTableComments: true,
      includeColumnComments: false,
      schemaName: 'public',
      catalogName: 'demo',
      tableNames: 't_user',
      tableNamePrefix: '',
      tableNameContains: '',
      customTableSql:
          'select 1 as table_name, 1 as table_code, 1 as table_comment',
      customColumnSql:
          'select 1 as table_name, 1 as column_name, 1 as column_code, 1 as data_type, 1 as length, 0 as precision, 1 as nullable, 1 as default_value, 1 as column_comment, 1 as ordinal_position',
      customPrimaryKeySql: 'select 1 as table_name, 1 as column_name',
    );

    await runtimeSettingsRepository.setJdkHome('D:/Java/jdk-17');

    final reloadedDrivers = await driverRepository.getDrivers();
    final reloadedDataSources = await dataSourceRepository.getDataSources();
    final reloadedPresets = await presetRepository.getPresets();
    final jdkHome = await runtimeSettingsRepository.getJdkHome();

    expect(reloadedDrivers.any((item) => item.id == customDriver.id), isTrue);
    expect(
      reloadedDrivers
          .firstWhere((item) => item.id == customDriver.id)
          .jdbcUrlTemplate,
      'jdbc:postgresql://127.0.0.1:5432/demo',
    );
    expect(
      reloadedDrivers
          .firstWhere((item) => item.id == legacyOracleDriver.id)
          .columnSql,
      'select c.DATA_DEFAULT AS default_value from ALL_TAB_COLUMNS c',
    );
    expect(reloadedDataSources.single.name, '本地 PG');
    expect(reloadedPresets.single.id, preset.id);
    expect(reloadedPresets.single.includeColumnComments, isFalse);
    expect(jdkHome, 'D:/Java/jdk-17');
  });

  test('deduplicates built-in drivers by database type', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'pdm_viewer_jdbc_repo_dedupe_test',
    );
    final database = await AppDatabase.open(
      databasePath: path.join(tempDir.path, 'state.db'),
    );
    addTearDown(() async {
      database.dispose();
      await tempDir.delete(recursive: true);
    });
    final driverRepository = DriverRepository(database);
    final dataSourceRepository = DataSourceRepository(database);

    await driverRepository.ensureBuiltInTemplates();
    final before = await driverRepository.getDrivers();
    final mysqlBuiltIn = before.firstWhere(
      (item) =>
          item.isBuiltInTemplate && item.databaseType == JdbcDatabaseType.mysql,
    );

    final duplicate = await driverRepository.createDriver(
      name: 'MySQL JDBC 驱动',
      databaseType: JdbcDatabaseType.mysql,
      driverClass: mysqlBuiltIn.driverClass,
      jdbcUrlTemplate: mysqlBuiltIn.jdbcUrlTemplate,
      jarPaths: const [],
      tableSql: '',
      columnSql: '',
      columnCommentSql: '',
      primaryKeySql: '',
      notes: 'legacy',
      isBuiltInTemplate: true,
    );

    await dataSourceRepository.createDataSource(
      name: '引用旧驱动',
      databaseType: JdbcDatabaseType.mysql,
      driverId: duplicate.id,
      jdbcUrl: 'jdbc:mysql://localhost:3306/demo',
      username: 'demo',
      password: 'demo',
      schemaName: 'demo',
      catalogName: 'demo',
    );

    await driverRepository.ensureBuiltInTemplates();

    final afterDrivers = await driverRepository.getDrivers();
    final mysqlDrivers = afterDrivers
        .where(
          (item) =>
              item.isBuiltInTemplate &&
              item.databaseType == JdbcDatabaseType.mysql,
        )
        .toList(growable: false);
    final dataSources = await dataSourceRepository.getDataSources();

    expect(mysqlDrivers, hasLength(1));
    expect(mysqlDrivers.single.name, 'MySQL');
    expect(dataSources.single.driverId, mysqlDrivers.single.id);
  });

  test('oracle built-in column sql does not coalesce LONG default value', () {
    final service = JdbcReverseService(
      workspaceDirectory: Directory.systemTemp,
      javaRuntimeResolver: JavaRuntimeResolver(),
    );

    for (final databaseType in <JdbcDatabaseType>[
      JdbcDatabaseType.oracle,
      JdbcDatabaseType.obOracle,
      JdbcDatabaseType.dameng,
    ]) {
      final sql = service.buildBuiltInSql(
        databaseType: databaseType,
        schemaName: 'A8ACC',
        catalogName: '',
      );

      expect(sql.columnSql, contains('c.DATA_DEFAULT AS default_value'));
      expect(sql.columnSql, isNot(contains("COALESCE(c.DATA_DEFAULT, '')")));
    }
  });
}
