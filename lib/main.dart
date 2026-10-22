import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/state/app_controller.dart';
import 'app/state/theme_controller.dart';
import 'data/database/app_database.dart';
import 'data/repositories/data_source_repository.dart';
import 'data/repositories/driver_repository.dart';
import 'data/repositories/project_repository.dart';
import 'data/repositories/reverse_task_preset_repository.dart';
import 'data/repositories/runtime_settings_repository.dart';
import 'data/repositories/search_repository.dart';
import 'data/services/java_runtime_resolver.dart';
import 'data/services/jdbc_reverse_service.dart';
import 'data/services/pdm_parser_service.dart';
import 'data/services/pdm_writer_service.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final themeController = ThemeController();
  await themeController.initialize();
  final windowOptions = WindowOptions(
    size: Platform.isMacOS ? null : const Size(1300, 720),
    minimumSize: const Size(800, 500),
    center: !Platform.isMacOS,
    backgroundColor: themeController.resolvedBackgroundColor,
    titleBarStyle: Platform.isMacOS ? null : TitleBarStyle.hidden,
  );
  if (Platform.isMacOS) {
    await windowManager.waitUntilReadyToShow(windowOptions);
    await const MethodChannel('pdm_viewer/startup').invokeMethod<void>(
      'prepare',
      themeController.resolvedBackgroundColor.toARGB32(),
    );
  }

  final startup = _loadController();
  final controller = Platform.isMacOS ? null : await startup;
  runApp(
    PdmReaderApp(
      controller: controller,
      startup: Platform.isMacOS ? startup : null,
      themeController: themeController,
    ),
  );
  if (Platform.isMacOS) {
    binding.waitUntilFirstFrameRasterized.then((_) async {
      await const MethodChannel(
        'pdm_viewer/startup',
      ).invokeMethod<void>('firstFrameReady');
    });
  } else {
    binding.addPostFrameCallback((_) {
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    });
  }
}

Future<AppController> _loadController() async {
  final database = await AppDatabase.open();
  final projectRepository = ProjectRepository(database);
  final searchRepository = SearchRepository(database);
  final parserService = PdmParserService();
  final driverRepository = DriverRepository(database);
  final dataSourceRepository = DataSourceRepository(database);
  final reverseTaskPresetRepository = ReverseTaskPresetRepository(database);
  final runtimeSettingsRepository = RuntimeSettingsRepository(database);
  final javaRuntimeResolver = JavaRuntimeResolver();
  final jdbcReverseService = JdbcReverseService(
    workspaceDirectory: database.rootDirectory,
    javaRuntimeResolver: javaRuntimeResolver,
  );
  final pdmWriterService = PdmWriterService();

  final controller = AppController(
    projectRepository: projectRepository,
    searchRepository: searchRepository,
    parserService: parserService,
    driverRepository: driverRepository,
    dataSourceRepository: dataSourceRepository,
    reverseTaskPresetRepository: reverseTaskPresetRepository,
    runtimeSettingsRepository: runtimeSettingsRepository,
    javaRuntimeResolver: javaRuntimeResolver,
    jdbcReverseService: jdbcReverseService,
    pdmWriterService: pdmWriterService,
  );
  await controller.initialize();
  return controller;
}
