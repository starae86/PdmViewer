import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/app/state/app_controller.dart';
import 'package:pdm_viewer/app/app.dart';
import 'package:pdm_viewer/app/state/theme_controller.dart';
import 'package:pdm_viewer/app/theme/app_theme.dart';
import 'package:pdm_viewer/app/theme/theme_preset.dart';
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
import 'package:pdm_viewer/domain/models/pdm_models.dart';
import 'package:pdm_viewer/ui/views/project_list_view.dart';
import 'package:pdm_viewer/ui/views/project_workspace_view.dart';

void main() {
  const captureDir = String.fromEnvironment('UI_CAPTURE_DIR');

  testWidgets(
    'workspace home and detail render in all styles and compact windows',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = (await tester.runAsync(() async {
        final temp = await Directory.systemTemp.createTemp('pdm_ui_test');
        final db = await AppDatabase.open(
          databasePath: '${temp.path}/state.db',
        );
        final repository = ProjectRepository(db);
        final project = await repository.createProject('示例项目');
        final file = await repository.upsertProjectFile(
          projectId: project.id,
          filePath: '${temp.path}/model.pdm',
        );
        await repository.replaceProjectIndex(
          projectId: project.id,
          fileId: file.id,
          lastImportedHash: 'preview',
          parsed: ParsedPdmFile(
            modelName: '业务模型',
            sourcePath: file.path,
            sourceName: 'model.pdm',
            tables: [
              for (final name in ['CUSTOMER', 'ORDER', 'PRODUCT'])
                ParsedPdmTable(
                  id: name,
                  name: name,
                  code: name,
                  comment: '$name 业务表',
                  columns: [
                    for (final code in [
                      'ID',
                      'NAME',
                      'STATUS',
                      'CREATED_AT',
                      'UPDATED_AT',
                    ])
                      ParsedPdmColumn(
                        id: '$name.$code',
                        name: code,
                        code: code,
                        comment: '字段说明',
                        dataType: 'VARCHAR2(32)',
                        length: '32',
                        isPrimaryKey: code == 'ID',
                        nullable: code != 'ID',
                      ),
                  ],
                ),
            ],
          ),
        );
        final resolver = JavaRuntimeResolver();
        final controller = AppController(
          projectRepository: repository,
          searchRepository: SearchRepository(db),
          parserService: PdmParserService(),
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
        await controller.initialize();
        await controller.checkForChangedPdmFilesOnStartup();
        addTearDown(() async {
          controller.dispose();
          db.dispose();
          await temp.delete(recursive: true);
        });
        if (captureDir.isNotEmpty && Platform.isWindows) {
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          for (final font in {
            'Segoe UI': 'segoeui.ttf',
            'Microsoft YaHei': 'msyh.ttc',
          }.entries) {
            final source = File('C:/Windows/Fonts/${font.value}');
            if (await source.exists()) {
              final loader = FontLoader(font.key)
                ..addFont(
                  Future.value(
                    ByteData.sublistView(await source.readAsBytes()),
                  ),
                );
              await loader.load();
            }
          }
        }
        return controller;
      }))!;
      final boundaryKey = GlobalKey();
      Future<void> capture(String name) async {
        if (captureDir.isEmpty) return;
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(captureDir).create(recursive: true);
          await File(
            '$captureDir/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      for (final preset in ThemePreset.values) {
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(
                presetId: preset.id,
                brightness: brightness,
              ),
              home: RepaintBoundary(
                key: boundaryKey,
                child: Scaffold(
                  body: AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) => Row(
                      children: [
                        SizedBox(
                          width: 240,
                          child: ProjectListView(controller: controller),
                        ),
                        Expanded(
                          child: ProjectWorkspaceView(controller: controller),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final homeSurface = tester.widget<DecoratedBox>(
            find.byKey(const ValueKey('workspace-content-surface')),
          );
          final homeDecoration = homeSurface.decoration as BoxDecoration;
          expect(homeDecoration.borderRadius, isNull);
          expect(
            homeDecoration.color,
            AppTheme.surfaceOf(
              tester.element(find.byType(ProjectWorkspaceView)),
            ),
          );
          await capture('${preset.id}-${brightness.name}-home');
          final projectNode = find.descendant(
            of: find.byType(ProjectListView),
            matching: find.text('示例项目'),
          );
          await tester.tap(projectNode, buttons: kSecondaryMouseButton);
          await tester.pumpAndSettle();
          for (final label in ['新增 PDM', '修改项目', '预览 SQL', '删除项目']) {
            expect(
              find.widgetWithText(PopupMenuItem<String>, label),
              findsOneWidget,
            );
          }
          await tester.tap(find.text('修改项目'));
          await tester.pumpAndSettle();
          expect(find.text('修改项目名称'), findsOneWidget);
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          final fileNode = find.descendant(
            of: find.byType(ProjectListView),
            matching: find.text('model.pdm'),
          );
          if (fileNode.evaluate().isEmpty) {
            await tester.tap(projectNode);
            await tester.pumpAndSettle();
          }
          await tester.tap(fileNode, buttons: kSecondaryMouseButton);
          await tester.pumpAndSettle();
          for (final label in ['打开所在文件夹', '预览 SQL', '删除 PDM']) {
            expect(
              find.widgetWithText(PopupMenuItem<String>, label),
              findsOneWidget,
            );
          }
          await tester.tap(find.text('删除 PDM'));
          await tester.pumpAndSettle();
          expect(find.text('移除'), findsOneWidget);
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          await tester.runAsync(
            () => controller.selectResult(controller.results.first),
          );
          await tester.pumpAndSettle();
          expect(find.text('字段视图'), findsOneWidget);
          final pk = find.text('PK');
          final pkTheme = Theme.of(tester.element(pk));
          expect(
            tester.widget<Text>(pk).style?.color,
            pkTheme.colorScheme.onPrimary,
          );
          final pkBadge = tester.widget<Container>(
            find.ancestor(of: pk, matching: find.byType(Container)).first,
          );
          expect(
            (pkBadge.decoration! as BoxDecoration).color,
            pkTheme.colorScheme.primary,
          );
          final summary = tester
              .widgetList<SelectableText>(find.byType(SelectableText))
              .firstWhere((widget) => widget.data?.contains('业务表') == true);
          expect(summary.style?.fontWeight, FontWeight.w400);
          expect(
            summary.style?.fontFamily,
            AppTheme.build(
              presetId: preset.id,
            ).textTheme.bodyMedium?.fontFamily,
          );
          expect(tester.takeException(), isNull);
          await capture('${preset.id}-${brightness.name}-detail');
          await tester.tap(find.byType(FloatingActionButton));
          await tester.pumpAndSettle();
          final searchBar = find.byKey(const ValueKey('detail-search-bar'));
          expect(searchBar, findsOneWidget);
          expect(
            find.descendant(of: searchBar, matching: find.byIcon(Icons.search)),
            findsNothing,
          );
          expect(
            find.descendant(of: searchBar, matching: find.byType(FilterChip)),
            findsNothing,
          );
          expect(find.text('无匹配'), findsNothing);
          final input = find.descendant(
            of: searchBar,
            matching: find.byType(TextField),
          );
          await tester.enterText(input, 'ID');
          await tester.pumpAndSettle(const Duration(milliseconds: 400));
          expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
          expect(
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (widget) => widget is IconButton && widget.tooltip == '下一个',
                  ),
                )
                .onPressed,
            isNotNull,
          );
          for (final tooltip in ['区分大小写', '全字匹配']) {
            final toggle = find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == tooltip,
            );
            expect(tester.widget<IconButton>(toggle).isSelected, false);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            expect(tester.widget<IconButton>(toggle).isSelected, true);
          }
          final previous = tester.getCenter(find.byTooltip('上一个'));
          final next = tester.getCenter(find.byTooltip('下一个'));
          final close = tester.getCenter(find.byTooltip('关闭搜索'));
          expect(previous.dy, next.dy);
          expect(next.dy, close.dy);
          expect(previous.dx, lessThan(next.dx));
          expect(next.dx, lessThan(close.dx));
          expect(tester.takeException(), isNull);
          await capture('${preset.id}-${brightness.name}-search');
          await tester.tap(find.byTooltip('关闭搜索'));
          await tester.pumpAndSettle();
          expect(searchBar, findsNothing);
          for (final view in ['DDL 视图', 'DML 视图']) {
            await tester.tap(find.text(view));
            await tester.pumpAndSettle();
            await tester.tap(find.byType(FloatingActionButton));
            await tester.pumpAndSettle();
            final sqlSearchInput = find.descendant(
              of: find.byKey(const ValueKey('detail-search-bar')),
              matching: find.byType(TextField),
            );
            await tester.enterText(sqlSearchInput, 'ID');
            await tester.pumpAndSettle(const Duration(milliseconds: 400));
            final inputWidget = tester.widget<TextField>(sqlSearchInput);
            expect(inputWidget.focusNode!.hasFocus, isTrue);
            await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
            await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
            expect(
              inputWidget.controller!.selection,
              const TextSelection(baseOffset: 0, extentOffset: 2),
            );
            await tester.tap(find.byTooltip('清空搜索'));
            await tester.pumpAndSettle();
            expect(inputWidget.controller!.text, isEmpty);
            await tester.tap(find.byTooltip('关闭搜索'));
            await tester.pumpAndSettle();
            await tester.tap(find.byType(FloatingActionButton));
            await tester.pumpAndSettle();
            expect(searchBar, findsOneWidget);
            expect(find.byTooltip('区分大小写'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.tap(find.byTooltip('关闭搜索'));
            await tester.pumpAndSettle();
          }
          await tester.binding.setSurfaceSize(const Size(800, 500));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(FloatingActionButton));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.binding.setSurfaceSize(const Size(1100, 680));
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          controller.closeAllTableTabs();
        }
      }
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('window_manager'),
            (call) async => call.method == 'isMaximized' ? false : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('window_manager'),
              null,
            ),
      );
      final themeController = ThemeController();
      addTearDown(themeController.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(presetId: 'material'),
          home: RepaintBoundary(
            key: boundaryKey,
            child: ProjectShell(
              controller: controller,
              themeController: themeController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sidebar = find.byType(ProjectListView);
      final workspace = find.byType(ProjectWorkspaceView);
      expect(
        find.byKey(const ValueKey('user-guide-highlight')),
        findsOneWidget,
      );
      expect(find.text('检测到 PDM 文件变更'), findsNothing);
      await capture('guide-create-project');
      await tester.tap(find.text('跳过向导'));
      await tester.pumpAndSettle();
      expect(controller.hasSeenUserGuide, isTrue);
      expect(find.text('检测到 PDM 文件变更'), findsOneWidget);
      await tester.tap(find.text('暂不处理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('帮助'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用向导'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('user-guide-highlight')),
        findsOneWidget,
      );
      expect(find.text('1 / 5'), findsOneWidget);
      await tester.tap(find.text('跳过向导'));
      await tester.pumpAndSettle();
      expect(tester.getTopRight(sidebar).dx, tester.getTopLeft(workspace).dx);
      final boundary = tester.getTopRight(sidebar);
      await tester.dragFrom(
        Offset(boundary.dx, boundary.dy + 180),
        const Offset(30, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopRight(sidebar).dx, greaterThan(boundary.dx));
      expect(tester.getTopRight(sidebar).dx, tester.getTopLeft(workspace).dx);
      expect(tester.takeException(), isNull);
      await tester.runAsync(
        () => controller.deleteProject(controller.selectedProject!.id),
      );
      await tester.pumpAndSettle();
      expect(find.text('请选择一张表'), findsOneWidget);
      expect(
        find.descendant(of: workspace, matching: find.byType(Card)),
        findsNothing,
      );
      final emptyDecoration =
          tester
                  .widget<DecoratedBox>(
                    find.byKey(const ValueKey('workspace-content-surface')),
                  )
                  .decoration
              as BoxDecoration;
      expect(emptyDecoration.borderRadius, isNull);
      expect(
        emptyDecoration.color,
        AppTheme.surfaceOf(tester.element(workspace)),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('workspace-content-surface'))),
        tester.getSize(workspace),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: ProjectShell(
            controller: controller,
            themeController: themeController,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('user-guide-highlight')), findsNothing);
      await tester.tap(find.text('帮助'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用向导'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('新增'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('user-guide-highlight')), findsNothing);
      expect(find.text('新建项目'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '向导演示项目');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('导入 PDM'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('user-guide-highlight'))),
        tester.getRect(find.byTooltip('新增 PDM')).inflate(4),
      );
      await tester.tap(find.text('跳过向导'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
