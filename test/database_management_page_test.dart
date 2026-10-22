import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/app/app.dart';
import 'package:pdm_viewer/app/state/app_controller.dart';
import 'package:pdm_viewer/app/state/theme_controller.dart';
import 'package:pdm_viewer/data/database/app_database.dart';
import 'package:pdm_viewer/data/repositories/data_source_repository.dart';
import 'package:pdm_viewer/data/repositories/driver_repository.dart';
import 'package:pdm_viewer/data/repositories/project_repository.dart';
import 'package:pdm_viewer/data/repositories/reverse_task_preset_repository.dart';
import 'package:pdm_viewer/data/repositories/runtime_settings_repository.dart';
import 'package:pdm_viewer/data/repositories/search_repository.dart';
import 'package:pdm_viewer/data/services/java_runtime_resolver.dart';
import 'package:pdm_viewer/data/services/jdbc_reverse_service.dart';
import 'package:pdm_viewer/data/services/pdm_parser_service.dart';
import 'package:pdm_viewer/data/services/pdm_writer_service.dart';
import 'package:pdm_viewer/domain/models/jdbc_models.dart';

void main() {
  testWidgets('copy drafts, unique names and guarded database navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isMaximized' ? false : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      ),
    );
    late AppController controller;
    late ThemeController themes;
    late DriverRepository drivers;
    late DataSourceRepository sources;
    await tester.runAsync(() async {
      final temp = await Directory.systemTemp.createTemp('PdmViewerDatabaseUi');
      final db = await AppDatabase.open(databasePath: '${temp.path}/state.db');
      drivers = DriverRepository(db);
      sources = DataSourceRepository(db);
      final jar = await File(
        '${temp.path}/driver.jar',
      ).writeAsString('test fixture');
      final driver = await drivers.createDriver(
        name: 'A Driver',
        databaseType: JdbcDatabaseType.mysql,
        driverClass: 'example.Driver',
        jdbcUrlTemplate: 'jdbc:example://localhost/db',
        jarPaths: [jar.path],
        tableSql: 'select table_name from example_tables',
        columnSql: 'select column_name from example_columns',
        columnCommentSql: 'select comment from example_comments',
        primaryKeySql: 'select pk from example_keys',
        notes: 'original notes',
      );
      await sources.createDataSource(
        name: 'A Source',
        databaseType: JdbcDatabaseType.mysql,
        driverId: driver.id,
        jdbcUrl: 'jdbc:example://localhost/db',
        username: 'reader',
        password: 'fixture-password',
        schemaName: 'schema',
        catalogName: 'catalog',
      );
      final resolver = JavaRuntimeResolver();
      controller = AppController(
        projectRepository: ProjectRepository(db),
        searchRepository: SearchRepository(db),
        parserService: PdmParserService(),
        driverRepository: drivers,
        dataSourceRepository: sources,
        reverseTaskPresetRepository: ReverseTaskPresetRepository(db),
        runtimeSettingsRepository: RuntimeSettingsRepository(db),
        javaRuntimeResolver: resolver,
        jdbcReverseService: JdbcReverseService(
          workspaceDirectory: db.rootDirectory,
          javaRuntimeResolver: resolver,
        ),
        pdmWriterService: PdmWriterService(),
      );
      themes = ThemeController(storagePath: '${temp.path}/theme.json');
      await themes.setLocale(const Locale('zh'));
      await controller.initialize();
      await controller.markUserGuideSeen();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        themes.dispose();
        db.dispose();
        await temp.delete(recursive: true);
      });
    });
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Future<void> click(String label) async {
      final target = label == 'A Driver'
          ? find.widgetWithText(ListTile, label)
          : find.text(label).last;
      await tester.ensureVisible(target);
      await tester.tap(target);
      await settle();
    }

    String value(String key) =>
        tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
    await tester.pumpWidget(
      PdmReaderApp(controller: controller, themeController: themes),
    );
    await settle();
    await click('数据库');
    await click('驱动管理');
    await tester.tap(
      find.widgetWithText(ListTile, 'A Driver'),
      buttons: kSecondaryMouseButton,
    );
    await settle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(value('database-driver-name'), 'A Driver');
    await click('复制');
    expect(value('database-driver-name'), 'A Driver_副本');
    expect(await tester.runAsync(() => drivers.getDrivers()), hasLength(7));
    await tester.enterText(
      find.byKey(const ValueKey('database-driver-name')),
      ' mysql ',
    );
    await click('保存');
    expect(find.text('驱动名称不能重复。'), findsOneWidget);
    await click('知道了');
    await click('数据源管理');
    expect(find.text('未保存的更改'), findsOneWidget);
    await click('取消');
    expect(value('database-driver-name'), ' mysql ');
    // The application menu must use the same guard, not replace the page.
    await click('数据库');
    await click('数据源管理');
    await click('不保存');
    expect(find.text('数据源配置'), findsOneWidget);
    await click('复制');
    expect(value('database-source-name'), 'A Source_副本');
    await tester.enterText(
      find.byKey(const ValueKey('database-source-name')),
      ' a source ',
    );
    await click('保存');
    expect(find.text('数据源名称不能重复。'), findsOneWidget);
    await click('知道了');
    await tester.enterText(
      find.byKey(const ValueKey('database-source-name')),
      'A Source_副本',
    );
    await click('返回主页');
    await click('取消');
    expect(value('database-source-name'), 'A Source_副本');
    await click('逆向生成');
    await click('保存');
    expect(find.text('逆向配置'), findsOneWidget);
    final copiedSources = (await tester.runAsync(
      () => sources.getDataSources(),
    ))!;
    expect(copiedSources, hasLength(2));
    final copiedSource = copiedSources.singleWhere(
      (item) => item.name.endsWith('_副本'),
    );
    expect(copiedSource.username, 'reader');
    expect(copiedSource.password, 'fixture-password');
    expect(copiedSource.schemaName, 'schema');
    await click('驱动管理');
    await click('复制');
    await click('保存');
    await click('知道了');
    final copiedDrivers = (await tester.runAsync(() => drivers.getDrivers()))!;
    final copiedDriver = copiedDrivers.singleWhere(
      (item) => item.name == 'A Driver_副本',
    );
    expect(copiedDriver.isBuiltInTemplate, isFalse);
    expect(copiedDriver.tableSql, 'select table_name from example_tables');
    expect(copiedDriver.notes, 'original notes');
    expect(copiedDriver.jarPaths, isNotEmpty);
    // Repeated copies get a unique name; switching list records is guarded.
    await click('A Driver');
    await click('复制');
    expect(value('database-driver-name'), 'A Driver_副本2');
    await click('A Driver');
    await click('不保存');
    await tester.enterText(
      find.byKey(const ValueKey('database-driver-class')),
      'example.UpdatedDriver',
    );
    await click('返回主页');
    await click('保存');
    expect(find.text('驱动配置'), findsNothing);
    final savedDrivers = (await tester.runAsync(() => drivers.getDrivers()))!;
    expect(
      savedDrivers.singleWhere((item) => item.name == 'A Driver').driverClass,
      'example.UpdatedDriver',
    );
    await click('数据库');
    await click('驱动管理');
    await click('新增');
    await click('返回主页');
    await click('保存');
    expect(find.text('请填写驱动名称和驱动类名。'), findsOneWidget);
    await click('知道了');
    expect(find.text('驱动配置'), findsOneWidget);
    await click('返回主页');
    await click('不保存');
    expect(find.text('驱动配置'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await settle();
  });
}
