import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/app/app.dart';
import 'package:pdm_viewer/app/state/app_controller.dart';
import 'package:pdm_viewer/app/state/theme_controller.dart';
import 'package:pdm_viewer/app/theme/app_theme.dart';
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
  const captureDir = String.fromEnvironment('README_CAPTURE_DIR');
  const language = String.fromEnvironment(
    'README_LANGUAGE',
    defaultValue: 'zh',
  );
  final english = language == 'en';
  const extraOnly = bool.fromEnvironment('README_CAPTURE_EXTRA_ONLY');

  testWidgets('capture README using only sample.pdm', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isMaximized' ? false : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('pdm_viewer/system_fonts'),
      (call) async => ['Microsoft YaHei', 'Noto Sans SC', 'Segoe UI'],
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('pdm_viewer/system_fonts'),
        null,
      ),
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      ),
    );

    late AppController controller;
    late ThemeController themes;
    await tester.runAsync(() async {
      final temp = await Directory.systemTemp.createTemp('PdmViewerReadme');
      final sample = await File(
        'examples/sample.pdm',
      ).copy('${temp.path}/sample.pdm');
      final parser = PdmParserService();
      final imported = await parser.parseFileWithHash(sample.path);
      final db = await AppDatabase.open(databasePath: '${temp.path}/state.db');
      final repository = ProjectRepository(db);
      final project = await repository.createProject(
        imported.parsedFile.modelName,
      );
      final file = await repository.upsertProjectFile(
        projectId: project.id,
        filePath: sample.path,
      );
      await repository.replaceProjectIndex(
        projectId: project.id,
        fileId: file.id,
        parsed: imported.parsedFile,
        lastImportedHash: imported.fileHash,
      );
      final resolver = JavaRuntimeResolver();
      controller = AppController(
        projectRepository: repository,
        searchRepository: SearchRepository(db),
        parserService: parser,
        driverRepository: DriverRepository(db),
        dataSourceRepository: DataSourceRepository(db),
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
      addTearDown(() async {
        controller.dispose();
        themes.dispose();
        db.dispose();
        await temp.delete(recursive: true);
      });
      await controller.initialize();
      final drivers = await controller.getJdbcDrivers();
      await DataSourceRepository(db).createDataSource(
        name: 'Sample MySQL',
        databaseType: JdbcDatabaseType.mysql,
        driverId: drivers
            .firstWhere((d) => d.databaseType == JdbcDatabaseType.mysql)
            .id,
        jdbcUrl: 'jdbc:mysql://127.0.0.1:3306/sample_db',
        username: 'sample_reader',
        password: '',
        schemaName: 'sample_db',
        catalogName: 'sample_db',
      );
      await controller.markUserGuideSeen();
      await themes.setAppearance(
        seedColor: AppTheme.defaultSeedColor,
        fontFamily: Platform.isWindows ? 'Noto Sans SC' : null,
        presetId: 'workbench',
        themeMode: ThemeMode.light,
      );
      await themes.setLocale(Locale(language));

      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      // Fonts are loaded from the local system for capture, not bundled or copied.
      if (Platform.isWindows) {
        for (final font in {
          'Segoe UI': 'segoeui.ttf',
          'Microsoft YaHei': 'msyh.ttc',
          'Noto Sans SC': 'NotoSansSC-VF.ttf',
        }.entries) {
          final source = File('C:/Windows/Fonts/${font.value}');
          if (await source.exists()) {
            await (FontLoader(font.key)..addFont(
                  Future.value(
                    ByteData.sublistView(await source.readAsBytes()),
                  ),
                ))
                .load();
          }
        }
      }
    });

    expect(controller.results.length, 3);
    expect(
      controller.results.map((result) => result.tableCode),
      unorderedEquals(['SYS_USER', 'BIZ_ORDER', 'BIZ_ORDER_ITEM']),
    );
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: PdmReaderApp(controller: controller, themeController: themes),
      ),
    );

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (extraOnly &&
          const ['home', 'fields', 'ddl', 'dml-dark'].contains(name)) {
        return;
      }
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(captureDir).create(recursive: true);
          await File(
            '$captureDir/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    await capture('home');
    await tester.runAsync(
      () => controller.selectResult(
        controller.results.firstWhere(
          (result) => result.tableCode == 'BIZ_ORDER',
        ),
      ),
    );
    await capture('fields');
    await tester.tap(find.text(english ? 'DDL' : 'DDL 视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MySQL'));
    await capture('ddl');
    await tester.tap(find.text(english ? 'DML' : 'DML 视图'));
    await tester.runAsync(
      () => themes.setAppearance(
        seedColor: themes.seedColor,
        fontFamily: themes.fontFamily,
        presetId: 'workbench',
        themeMode: ThemeMode.dark,
      ),
    );
    await capture('dml-dark');

    Future<void> appearance(String preset, ThemeMode mode) async {
      await tester.runAsync(
        () => themes.setAppearance(
          seedColor: themes.seedColor,
          fontFamily: themes.fontFamily,
          presetId: preset,
          themeMode: mode,
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final preset in ['workbench', 'material']) {
      await appearance(
        preset,
        preset == 'workbench' ? ThemeMode.dark : ThemeMode.light,
      );
      await tester.tap(find.text(english ? 'Theme' : '主题').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(english ? 'Theme' : '主题').last);
      // System font enumeration is asynchronous, outside the fake test clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await capture('theme-$preset');
      await tester.tap(find.text(english ? 'Cancel' : '取消'));
      await tester.pumpAndSettle();
    }

    await appearance('fluent', ThemeMode.light);
    await tester.tap(find.text(english ? 'Database' : '数据库'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(
        find.text(english ? 'Reverse Engineer PDM' : '逆向生成 PDM'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(5));
    await tester.enterText(fields.at(2), 'SYS_USER,BIZ_ORDER,BIZ_ORDER_ITEM');
    await tester.enterText(fields.at(3), 'examples/sample-reverse.pdm');
    FocusManager.instance.primaryFocus?.unfocus();
    await capture('reverse-fluent');
    await appearance('macos', ThemeMode.dark);
    await capture('reverse-macos-dark');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, skip: captureDir.isEmpty);
}
