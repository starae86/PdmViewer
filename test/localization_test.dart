import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/app/app.dart';
import 'package:pdm_viewer/app/l10n/app_strings.dart';
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

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
  });
  tearDown(() => binding.platformDispatcher.clearLocaleTestValue());

  test(
    'system language selects Chinese for zh and English otherwise',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'PdmViewerSystemLanguage',
      );
      addTearDown(() => temp.delete(recursive: true));
      for (final system in const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('zh', 'HK'),
        Locale('en', 'US'),
        Locale('ja', 'JP'),
        Locale('de', 'DE'),
      ]) {
        binding.platformDispatcher.localeTestValue = system;
        final settings = ThemeController(
          storagePath: '${temp.path}/theme.json',
        );
        await settings.initialize();
        expect(
          settings.locale.languageCode,
          system.languageCode == 'zh' ? 'zh' : 'en',
        );
        settings.dispose();
      }
    },
  );

  test(
    'appearance saves retain automatic language, explicit choice wins',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'PdmViewerAutoLanguage',
      );
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/theme.json');
      final settings = ThemeController(storagePath: file.path);
      addTearDown(settings.dispose);
      await settings.setSeedColor(Colors.teal);
      binding.platformDispatcher.localeTestValue = const Locale('ja');
      final restored = ThemeController(storagePath: file.path);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.locale, const Locale('en'));
      await restored.setLocale(const Locale('en'));
      binding.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
      await settings.initialize();
      expect(settings.locale, const Locale('en'));
      expect(restored.locale, const Locale('en'));
    },
  );

  test('messages preserve captured user data and use specific copy labels', () {
    const en = AppStrings(Locale('en'));
    const zh = AppStrings(Locale('zh'));
    expect(en.translate('共 10000 张表'), '10000 tables');
    expect(en.translate('复制全部(含表头)'), 'Copy All (with headers)');
    expect(
      en.translate('驼峰复制整列(含表头)'),
      'Copy Column as camelCase (with headers)',
    );
    expect(en.translate('确认删除“用户数据源”吗？'), 'Delete “用户数据源”?');
    expect(en.translate('SYS_USER 用户'), 'SYS_USER 用户');
    expect(zh.translate('生成 DDL'), '生成 DDL');
  });

  test(
    'language persists independently of appearance, with legacy fallback',
    () async {
      final temp = await Directory.systemTemp.createTemp('PdmViewerLanguage');
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/theme.json');
      await file.writeAsString('{"seedColorArgb":4278221516}');
      final settings = ThemeController(storagePath: file.path);
      addTearDown(settings.dispose);
      await settings.initialize();
      expect(settings.locale, const Locale('zh'));
      await settings.setLocale(const Locale('en'));
      await settings.setSeedColor(Colors.teal);
      final restored = ThemeController(storagePath: file.path);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.locale, const Locale('en'));
      expect(restored.seedColor.toARGB32(), Colors.teal.toARGB32());
      await restored.setLocale(const Locale('zh'));
      await settings.initialize();
      expect(settings.locale, const Locale('zh'));
      expect(() => settings.setLocale(const Locale('fr')), throwsArgumentError);
    },
  );

  test('failed language persistence retains the previous language', () async {
    final temp = await Directory.systemTemp.createTemp(
      'PdmViewerLanguageError',
    );
    addTearDown(() => temp.delete(recursive: true));
    final settings = ThemeController(storagePath: temp.path);
    addTearDown(settings.dispose);
    await expectLater(
      settings.setLocale(const Locale('en')),
      throwsA(isA<FileSystemException>()),
    );
    expect(settings.locale, const Locale('zh'));
  });

  testWidgets(
    'Help switches languages without losing tables; English screens fit',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => call.method == 'isMaximized' ? false : null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('pdm_viewer/system_fonts'),
        (_) async => ['Arial'],
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('pdm_viewer/system_fonts'),
          null,
        );
      });
      late AppController controller;
      late ThemeController themes;
      await tester.runAsync(() async {
        final temp = await Directory.systemTemp.createTemp(
          'PdmViewerEnglishUi',
        );
        final db = await AppDatabase.open(
          databasePath: '${temp.path}/state.db',
        );
        final repository = ProjectRepository(db);
        final project = await repository.createProject('示例项目');
        final sample = await File(
          'examples/sample.pdm',
        ).copy('${temp.path}/sample.pdm');
        final parser = PdmParserService();
        final imported = await parser.parseFileWithHash(sample.path);
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
      await tester.pumpWidget(
        PdmReaderApp(controller: controller, themeController: themes),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => controller.selectResult(controller.results.first),
      );
      await tester.pumpAndSettle();
      final selected = controller.selectedResult;
      await tester.tap(find.text('帮助'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('语言'));
      await tester.pumpAndSettle();
      var languageChanged = false;
      void onLanguageChanged() => languageChanged = true;
      themes.addListener(onLanguageChanged);
      await tester.tap(find.text('English'));
      for (var i = 0; i < 100 && !languageChanged; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      themes.removeListener(onLanguageChanged);
      expect(languageChanged, isTrue);
      await tester.pumpAndSettle();
      expect(themes.locale.languageCode, 'en');
      expect(find.text('Help'), findsOneWidget);
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Support the Author'));
      await tester.pumpAndSettle();
      expect(find.text('Alipay'), findsOneWidget);
      expect(find.text('WeChat Pay'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Columns'), findsWidgets);
      expect(find.text('Nullable'), findsOneWidget);
      expect(find.text('示例项目'), findsWidgets);
      expect(controller.selectedResult, same(selected));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Current Scope'), findsOneWidget);
      expect(find.text('Tables: 3'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(800, 500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Theme').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme').last);
      await tester.pumpAndSettle();
      expect(find.text('Visual Style'), findsOneWidget);
      expect(find.text('Contrast'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(const Size(1100, 720));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Database'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Drivers'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Driver Settings'), findsOneWidget);
      expect(find.text('Driver Name'), findsWidgets);
      expect(find.text('Save'), findsOneWidget);
      final navigationViewport = find.ancestor(
        of: find.text('Back to Home'),
        matching: find.byType(SingleChildScrollView),
      );
      final saveDriverButton = find.ancestor(
        of: find.text('Save'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(
        tester.getTopLeft(navigationViewport).dx,
        closeTo(tester.getTopLeft(find.text('Driver Settings')).dx, 1),
      );
      expect(
        tester.getTopRight(saveDriverButton).dx,
        closeTo(tester.getTopRight(navigationViewport).dx, 1),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Data Sources'));
      await tester.pumpAndSettle();
      expect(find.text('Data Source Settings'), findsOneWidget);
      expect(find.text('Test Connection'), findsOneWidget);
      await tester.ensureVisible(find.text('Reverse Engineering'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reverse Engineering'));
      await tester.pumpAndSettle();
      expect(find.text('Table Comments'), findsOneWidget);
      expect(find.text('Execution Log'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      languageChanged = false;
      themes.addListener(onLanguageChanged);
      await tester.tap(find.text('简体中文'));
      for (var i = 0; i < 100 && !languageChanged; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      themes.removeListener(onLanguageChanged);
      expect(languageChanged, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('帮助'), findsOneWidget);
      expect(find.text('执行日志'), findsOneWidget);
      expect(themes.locale.languageCode, 'zh');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
