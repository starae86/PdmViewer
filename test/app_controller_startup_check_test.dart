import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pdm_viewer/app/state/app_controller.dart';
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
import 'package:pdm_viewer/domain/models/project.dart';
import 'package:pdm_viewer/domain/models/search_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('detects modified and baseline-missing pdm files on startup', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'pdm_viewer_controller_startup_test',
    );
    final database = await AppDatabase.open(
      databasePath: path.join(tempDir.path, 'state.json'),
    );
    addTearDown(() async {
      database.dispose();
      await tempDir.delete(recursive: true);
    });
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

    final trackedFile = File(path.join(tempDir.path, 'tracked.pdm'));
    await trackedFile.writeAsString(_buildPdmXml(tableComment: '初始注释'));
    final trackedProject = await projectRepository.createProject('项目A');
    final trackedRecord = await projectRepository.upsertProjectFile(
      projectId: trackedProject.id,
      filePath: trackedFile.path,
    );
    final parsedTracked = await parserService.parseFile(trackedFile.path);
    await projectRepository.replaceProjectIndex(
      projectId: trackedProject.id,
      fileId: trackedRecord.id,
      parsed: parsedTracked,
      lastImportedHash: _hashForFile(trackedFile),
    );

    final baselineMissingFile = File(
      path.join(tempDir.path, 'missing-base.pdm'),
    );
    await baselineMissingFile.writeAsString(_buildPdmXml(tableComment: '待导入'));
    final secondProject = await projectRepository.createProject('项目B');
    final baselineMissingRecord = await projectRepository.upsertProjectFile(
      projectId: secondProject.id,
      filePath: baselineMissingFile.path,
    );

    await trackedFile.writeAsString(_buildPdmXml(tableComment: '已更新注释'));

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
    await controller.checkForChangedPdmFilesOnStartup();

    expect(controller.hasPendingStartupReloadPrompt, isTrue);
    expect(controller.hasSeenUserGuide, isFalse);
    await controller.markUserGuideSeen();
    expect(controller.hasSeenUserGuide, isTrue);
    expect(
      (await RuntimeSettingsRepository(
        database,
      ).getSetting('hasSeenUserGuide'))?.value,
      'true',
    );
    expect(controller.pendingStartupFileChanges, hasLength(2));
    expect(
      controller.pendingStartupFileChanges.any(
        (item) =>
            item.fileId == trackedRecord.id &&
            item.status == StartupPdmChangeStatus.modified,
      ),
      isTrue,
    );
    expect(
      controller.pendingStartupFileChanges.any(
        (item) =>
            item.fileId == baselineMissingRecord.id &&
            item.status == StartupPdmChangeStatus.baselineMissing,
      ),
      isTrue,
    );
  });

  test(
    'reloadChangedPdmFiles reloads only changed files and clears prompt',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pdm_viewer_controller_reload_test',
      );
      final database = await AppDatabase.open(
        databasePath: path.join(tempDir.path, 'state.json'),
      );
      addTearDown(() async {
        database.dispose();
        await tempDir.delete(recursive: true);
      });
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

      final changedFile = File(path.join(tempDir.path, 'changed.pdm'));
      await changedFile.writeAsString(
        _buildPdmXml(tableComment: '旧注释', tableCode: 'T_CHANGED'),
      );
      final unchangedFile = File(path.join(tempDir.path, 'unchanged.pdm'));
      await unchangedFile.writeAsString(
        _buildPdmXml(tableComment: '稳定注释', tableCode: 'T_STABLE'),
      );

      final project = await projectRepository.createProject('项目A');
      final changedRecord = await projectRepository.upsertProjectFile(
        projectId: project.id,
        filePath: changedFile.path,
      );
      final unchangedRecord = await projectRepository.upsertProjectFile(
        projectId: project.id,
        filePath: unchangedFile.path,
      );

      await projectRepository.replaceProjectIndex(
        projectId: project.id,
        fileId: changedRecord.id,
        parsed: await parserService.parseFile(changedFile.path),
        lastImportedHash: _hashForFile(changedFile),
      );
      await projectRepository.replaceProjectIndex(
        projectId: project.id,
        fileId: unchangedRecord.id,
        parsed: await parserService.parseFile(unchangedFile.path),
        lastImportedHash: _hashForFile(unchangedFile),
      );

      await changedFile.writeAsString(
        _buildPdmXml(tableComment: '新注释', tableCode: 'T_CHANGED'),
      );

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
      await controller.checkForChangedPdmFilesOnStartup();

      expect(controller.pendingStartupFileChanges, hasLength(1));
      expect(
        controller.pendingStartupFileChanges.single.fileId,
        changedRecord.id,
      );

      await controller.reloadChangedPdmFiles();

      expect(controller.hasPendingStartupReloadPrompt, isFalse);
      expect(controller.pendingStartupFileChanges, isEmpty);

      final results = await searchRepository.search(
        projectId: project.id,
        keyword: 'T_CHANGED',
        scope: SearchScope.table,
      );
      expect(results, hasLength(1));

      final detail = await searchRepository.getTableDetail(
        projectId: project.id,
        pdmFileId: changedRecord.id,
        sourceTableId: 'table-1',
      );
      expect(detail, isNotNull);
      expect(detail!.comment, '新注释');

      final files = await projectRepository.getProjectFiles(project.id);
      final changedReloaded = files.firstWhere(
        (item) => item.id == changedRecord.id,
      );
      final unchangedReloaded = files.firstWhere(
        (item) => item.id == unchangedRecord.id,
      );
      expect(changedReloaded.lastImportedHash, _hashForFile(changedFile));
      expect(unchangedReloaded.lastImportedHash, _hashForFile(unchangedFile));
    },
  );
}

String _buildPdmXml({
  required String tableComment,
  String tableCode = 'T_DEMO',
}) {
  return '''
<?xml version="1.0" encoding="utf-8"?>
<Root xmlns:o="object" xmlns:c="collection" xmlns:a="attribute">
  <o:Model>
    <a:Name>DemoModel</a:Name>
    <c:Tables>
      <o:Table Id="table-1">
        <a:Name>示例表</a:Name>
        <a:Code>$tableCode</a:Code>
        <a:Comment>$tableComment</a:Comment>
        <c:Columns>
          <o:Column Id="column-1">
            <a:Name>ID</a:Name>
            <a:Code>ID</a:Code>
            <a:Comment>主键</a:Comment>
            <a:DataType>VARCHAR2(32)</a:DataType>
            <a:Column.Mandatory>1</a:Column.Mandatory>
          </o:Column>
        </c:Columns>
        <c:Keys>
          <o:Key Id="key-1">
            <c:Key.Columns>
              <o:Column Ref="column-1" />
            </c:Key.Columns>
          </o:Key>
        </c:Keys>
        <c:PrimaryKey>
          <o:Key Ref="key-1" />
        </c:PrimaryKey>
      </o:Table>
    </c:Tables>
  </o:Model>
</Root>
''';
}

String _hashForFile(File file) {
  return sha256.convert(utf8.encode(file.readAsStringSync())).toString();
}
