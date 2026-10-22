import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../../data/repositories/data_source_repository.dart';
import '../../data/repositories/driver_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/reverse_task_preset_repository.dart';
import '../../data/repositories/runtime_settings_repository.dart';
import '../../data/services/java_runtime_resolver.dart';
import '../../data/services/jdbc_reverse_service.dart';
import '../../data/repositories/search_repository.dart';
import '../../data/services/pdm_parser_service.dart';
import '../../data/services/pdm_writer_service.dart';
import '../../domain/models/jdbc_models.dart';
import '../../domain/models/pdm_models.dart';
import '../../domain/models/project.dart';
import '../../domain/models/reverse_models.dart';
import '../../domain/models/search_models.dart';

class AppController extends ChangeNotifier {
  AppController({
    required ProjectRepository projectRepository,
    required SearchRepository searchRepository,
    required PdmParserService parserService,
    required DriverRepository driverRepository,
    required DataSourceRepository dataSourceRepository,
    required ReverseTaskPresetRepository reverseTaskPresetRepository,
    required RuntimeSettingsRepository runtimeSettingsRepository,
    required JavaRuntimeResolver javaRuntimeResolver,
    required JdbcReverseService jdbcReverseService,
    required PdmWriterService pdmWriterService,
  }) : _projectRepository = projectRepository,
       _searchRepository = searchRepository,
       _parserService = parserService,
       _driverRepository = driverRepository,
       _dataSourceRepository = dataSourceRepository,
       _reverseTaskPresetRepository = reverseTaskPresetRepository,
       _runtimeSettingsRepository = runtimeSettingsRepository,
       _javaRuntimeResolver = javaRuntimeResolver,
       _jdbcReverseService = jdbcReverseService,
       _pdmWriterService = pdmWriterService;

  static const Duration _searchDebounce = Duration(milliseconds: 300);

  final ProjectRepository _projectRepository;
  final SearchRepository _searchRepository;
  final PdmParserService _parserService;
  final DriverRepository _driverRepository;
  final DataSourceRepository _dataSourceRepository;
  final ReverseTaskPresetRepository _reverseTaskPresetRepository;
  final RuntimeSettingsRepository _runtimeSettingsRepository;
  final JavaRuntimeResolver _javaRuntimeResolver;
  final JdbcReverseService _jdbcReverseService;
  final PdmWriterService _pdmWriterService;

  List<ProjectRecord> _projects = const [];
  List<ProjectPdmFileRecord> _projectFiles = const [];
  Map<String, List<ProjectPdmFileRecord>> _projectFilesByProjectId = const {};
  List<SearchResultItem> _results = const [];
  ProjectWorkspaceStats _stats = const ProjectWorkspaceStats(
    projectCount: 0,
    fileCount: 0,
    tableCount: 0,
    columnCount: 0,
    errorFileCount: 0,
  );
  ProjectRecord? _selectedProject;
  SearchResultItem? _selectedResult;
  TableDetail? _selectedTableDetail;
  List<TableDetailTab> _openTableTabs = const [];
  String? _activeTableTabId;
  SearchScope _scope = SearchScope.table;
  SearchTarget _searchTarget = SearchTarget.allProjects;
  String _draftQuery = '';
  String _activeQuery = '';
  String? _selectedPdmFileId;
  List<StartupPdmChange> _pendingStartupFileChanges = const [];
  bool _hasPendingStartupReloadPrompt = false;
  bool _hasSeenUserGuide = false;
  bool _isRootExpanded = true;
  final Set<String> _expandedProjectIds = <String>{};
  bool _isBusy = false;
  bool _isSearching = false;
  String? _busyLabel;
  Timer? _searchDebounceTimer;
  int _searchGeneration = 0;
  int _startupCheckGeneration = 0;
  int _detailLoadGeneration = 0;
  int _tableActivationVersion = 0;
  int _treeLocationVersion = 0;

  List<ProjectRecord> get projects => _projects;
  List<ProjectPdmFileRecord> get projectFiles => _projectFiles;
  List<ProjectPdmFileRecord> projectFilesFor(String projectId) =>
      _projectFilesByProjectId[projectId] ?? const [];
  List<SearchResultItem> get results => _results;
  ProjectWorkspaceStats get stats => _stats;
  ProjectRecord? get selectedProject => _selectedProject;
  SearchResultItem? get selectedResult => _selectedResult;
  TableDetail? get selectedTableDetail => _selectedTableDetail;
  List<TableDetailTab> get openTableTabs => _openTableTabs;
  String? get activeTableTabId => _activeTableTabId;
  TableDetailTab? get activeTableTab {
    final activeId = _activeTableTabId;
    if (activeId == null) {
      return null;
    }
    for (final tab in _openTableTabs) {
      if (tab.id == activeId) {
        return tab;
      }
    }
    return null;
  }

  SearchScope get scope => _scope;
  SearchTarget get searchTarget => _searchTarget;
  String get draftQuery => _draftQuery;
  String get activeQuery => _activeQuery;
  String? get selectedPdmFileId => _selectedPdmFileId;
  List<StartupPdmChange> get pendingStartupFileChanges =>
      List.unmodifiable(_pendingStartupFileChanges);
  bool get hasPendingStartupReloadPrompt => _hasPendingStartupReloadPrompt;
  bool get hasSeenUserGuide => _hasSeenUserGuide;
  bool get isRootExpanded => _isRootExpanded;
  Set<String> get expandedProjectIds => Set.unmodifiable(_expandedProjectIds);
  bool get isBusy => _isBusy;
  bool get isSearching => _isSearching;
  String? get busyLabel => _busyLabel;
  List<String> get highlightedColumnIds =>
      activeTableTab?.highlightedColumnIds ?? const [];
  int get tableActivationVersion => _tableActivationVersion;
  int get treeLocationVersion => _treeLocationVersion;

  bool isProjectExpanded(String projectId) =>
      _expandedProjectIds.contains(projectId);

  Future<void> initialize() async {
    _hasSeenUserGuide =
        (await _runtimeSettingsRepository.getSetting(
          'hasSeenUserGuide',
        ))?.value ==
        'true';
    await _driverRepository.ensureBuiltInTemplates();
    await _reloadProjects();
    unawaited(checkForChangedPdmFilesOnStartup());
  }

  Future<void> markUserGuideSeen() async {
    await _runtimeSettingsRepository.setSetting('hasSeenUserGuide', 'true');
    _hasSeenUserGuide = true;
  }

  Future<List<JdbcDriverRecord>> getJdbcDrivers() {
    return _driverRepository.getDrivers();
  }

  Future<List<DataSourceRecord>> getDataSources() {
    return _dataSourceRepository.getDataSources();
  }

  Future<List<ReverseTaskPreset>> getReverseTaskPresets() {
    return _reverseTaskPresetRepository.getPresets();
  }

  Future<String?> getSavedJdkHome() {
    return _runtimeSettingsRepository.getJdkHome();
  }

  Future<JavaRuntimeResolution> validateAndSaveJdkHome(String jdkHome) async {
    final resolution = await _javaRuntimeResolver.validateJdkHome(jdkHome);
    await _runtimeSettingsRepository.setJdkHome(jdkHome);
    return resolution;
  }

  Future<void> clearSavedJdkHome() {
    return _runtimeSettingsRepository.setJdkHome(null);
  }

  Future<JdbcDriverRecord> createJdbcDriver({
    required String name,
    required JdbcDatabaseType databaseType,
    required String driverClass,
    String jdbcUrlTemplate = '',
    required List<String> jarPaths,
    String tableSql = '',
    String columnSql = '',
    String columnCommentSql = '',
    String primaryKeySql = '',
    required String notes,
  }) {
    return _driverRepository.createDriver(
      name: name.trim(),
      databaseType: databaseType,
      driverClass: driverClass.trim(),
      jdbcUrlTemplate: jdbcUrlTemplate.trim(),
      jarPaths: jarPaths,
      tableSql: tableSql,
      columnSql: columnSql,
      columnCommentSql: columnCommentSql,
      primaryKeySql: primaryKeySql,
      notes: notes.trim(),
    );
  }

  Future<void> updateJdbcDriver({
    required String id,
    required String name,
    required JdbcDatabaseType databaseType,
    required String driverClass,
    String jdbcUrlTemplate = '',
    required List<String> jarPaths,
    String tableSql = '',
    String columnSql = '',
    String columnCommentSql = '',
    String primaryKeySql = '',
    required String notes,
  }) {
    return _driverRepository.updateDriver(
      id: id,
      name: name.trim(),
      databaseType: databaseType,
      driverClass: driverClass.trim(),
      jdbcUrlTemplate: jdbcUrlTemplate.trim(),
      jarPaths: jarPaths,
      tableSql: tableSql,
      columnSql: columnSql,
      columnCommentSql: columnCommentSql,
      primaryKeySql: primaryKeySql,
      notes: notes.trim(),
    );
  }

  BuiltInReverseSqlSet buildReverseSqlPreview(JdbcDatabaseType databaseType) {
    return _jdbcReverseService.buildBuiltInSql(
      databaseType: databaseType,
      schemaName: '%SCHEMA%',
      catalogName: '%CATALOG%',
      includeTableComments: true,
      includeColumnComments: true,
    );
  }

  Future<void> deleteJdbcDriver(String id) {
    return _driverRepository.deleteDriver(id);
  }

  Future<DataSourceRecord> createDataSource({
    required String name,
    required JdbcDatabaseType databaseType,
    required String driverId,
    required String jdbcUrl,
    required String username,
    required String password,
    required String schemaName,
    required String catalogName,
  }) async {
    await _validateDataSourceDraft(
      driverId: driverId,
      jdbcUrl: jdbcUrl,
      username: username,
      password: password,
    );
    return _dataSourceRepository.createDataSource(
      name: name.trim(),
      databaseType: databaseType,
      driverId: driverId,
      jdbcUrl: jdbcUrl.trim(),
      username: username.trim(),
      password: password,
      schemaName: schemaName.trim(),
      catalogName: catalogName.trim(),
    );
  }

  Future<void> updateDataSource({
    required String id,
    required String name,
    required JdbcDatabaseType databaseType,
    required String driverId,
    required String jdbcUrl,
    required String username,
    required String password,
    required String schemaName,
    required String catalogName,
  }) async {
    await _validateDataSourceDraft(
      driverId: driverId,
      jdbcUrl: jdbcUrl,
      username: username,
      password: password,
    );
    return _dataSourceRepository.updateDataSource(
      id: id,
      name: name.trim(),
      databaseType: databaseType,
      driverId: driverId,
      jdbcUrl: jdbcUrl.trim(),
      username: username.trim(),
      password: password,
      schemaName: schemaName.trim(),
      catalogName: catalogName.trim(),
    );
  }

  Future<void> deleteDataSource(String id) {
    return _dataSourceRepository.deleteDataSource(id);
  }

  Future<JdbcConnectionTestResult> testDataSourceConnection({
    required String dataSourceId,
  }) async {
    final dataSource = await _dataSourceRepository.getDataSourceById(
      dataSourceId,
    );
    if (dataSource == null) {
      throw Exception('数据源不存在。');
    }
    final driver = await _driverRepository.getDriverById(dataSource.driverId);
    if (driver == null) {
      throw Exception('数据源未关联有效驱动。');
    }
    final savedJdkHome = await _runtimeSettingsRepository.getJdkHome();
    final result = await _jdbcReverseService.testConnection(
      driver: driver,
      dataSource: dataSource,
      preferredJdkHome: savedJdkHome,
    );
    await _dataSourceRepository.updateConnectionStatus(
      id: dataSourceId,
      status: result.success
          ? ConnectionHealthStatus.success
          : ConnectionHealthStatus.failed,
      errorMessage: result.success ? '' : result.message,
    );
    return result;
  }

  Future<JdbcConnectionTestResult> testDataSourceDraftConnection({
    required JdbcDatabaseType databaseType,
    required String driverId,
    required String jdbcUrl,
    required String username,
    required String password,
    required String schemaName,
    required String catalogName,
  }) async {
    final driver = await _validateDataSourceDraft(
      driverId: driverId,
      jdbcUrl: jdbcUrl,
      username: username,
      password: password,
    );
    final savedJdkHome = await _runtimeSettingsRepository.getJdkHome();
    return _jdbcReverseService.testConnection(
      driver: driver,
      dataSource: DataSourceRecord(
        id: '__draft__',
        name: '临时测试',
        databaseType: databaseType,
        driverId: driverId,
        jdbcUrl: jdbcUrl.trim(),
        username: username.trim(),
        password: password,
        schemaName: schemaName.trim(),
        catalogName: catalogName.trim(),
        lastConnectionStatus: ConnectionHealthStatus.unknown,
        lastError: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      preferredJdkHome: savedJdkHome,
    );
  }

  Future<JdbcDriverRecord> _validateDataSourceDraft({
    required String driverId,
    required String jdbcUrl,
    required String username,
    required String password,
  }) async {
    final driver = await _driverRepository.getDriverById(driverId);
    if (driver == null) {
      throw Exception('请选择有效的 JDBC 驱动。');
    }
    if (jdbcUrl.trim().isEmpty) {
      throw Exception('请填写 JDBC URL。');
    }
    if (username.trim().isEmpty) {
      throw Exception('请填写用户名。');
    }
    if (password.isEmpty) {
      throw Exception('请填写密码。');
    }

    final jarPaths = driver.jarPaths
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (jarPaths.isEmpty) {
      throw Exception('当前驱动未配置 JDBC JAR 包。');
    }
    for (final jarPath in jarPaths) {
      if (!File(jarPath).existsSync()) {
        throw Exception('驱动 JAR 包不存在：$jarPath');
      }
    }
    return driver;
  }

  Future<ReverseTaskPreset> saveReverseTaskPreset({
    String? id,
    required String name,
    required ReverseAdapterType adapterType,
    required String dataSourceId,
    required String driverId,
    required String outputPath,
    required bool includeTableComments,
    required bool includeColumnComments,
    required String schemaName,
    required String catalogName,
    required String tableNames,
    required String tableNamePrefix,
    required String tableNameContains,
    required String customTableSql,
    required String customColumnSql,
    required String customPrimaryKeySql,
  }) {
    return _reverseTaskPresetRepository.savePreset(
      id: id,
      name: name.trim(),
      adapterType: adapterType,
      dataSourceId: dataSourceId,
      driverId: driverId,
      outputPath: outputPath.trim(),
      includeTableComments: includeTableComments,
      includeColumnComments: includeColumnComments,
      schemaName: schemaName.trim(),
      catalogName: catalogName.trim(),
      tableNames: tableNames,
      tableNamePrefix: tableNamePrefix.trim(),
      tableNameContains: tableNameContains.trim(),
      customTableSql: customTableSql,
      customColumnSql: customColumnSql,
      customPrimaryKeySql: customPrimaryKeySql,
    );
  }

  Future<void> deleteReverseTaskPreset(String id) {
    return _reverseTaskPresetRepository.deletePreset(id);
  }

  Future<ReverseExecutionOutcome> reverseDatabaseToPdm({
    required String dataSourceId,
    required String outputPath,
    required bool includeTableComments,
    required bool includeColumnComments,
    required String schemaName,
    required String catalogName,
    required String tableFilter,
    void Function(String message)? onLog,
  }) async {
    final dataSource = await _dataSourceRepository.getDataSourceById(
      dataSourceId,
    );
    if (dataSource == null) {
      throw Exception('数据源不存在。');
    }
    final driver = await _driverRepository.getDriverById(dataSource.driverId);
    if (driver == null) {
      throw Exception('未找到关联驱动。');
    }

    final effectiveSchemaName = schemaName.trim().isEmpty
        ? dataSource.schemaName
        : schemaName.trim();
    final effectiveCatalogName = catalogName.trim().isEmpty
        ? dataSource.catalogName
        : catalogName.trim();

    final hasDriverSql = driver.hasCustomSql;
    final sqlSet = hasDriverSql
        ? BuiltInReverseSqlSet(
            tableSql: driver.tableSql.trim(),
            columnSql: driver.columnSql.trim(),
            columnCommentSql: driver.columnCommentSql.trim(),
            primaryKeySql: driver.primaryKeySql.trim(),
          )
        : _jdbcReverseService.buildBuiltInSql(
            databaseType: dataSource.databaseType,
            schemaName: effectiveSchemaName,
            catalogName: effectiveCatalogName,
            includeTableComments: includeTableComments,
            includeColumnComments: includeColumnComments,
          );

    if (sqlSet.tableSql.trim().isEmpty ||
        sqlSet.columnSql.trim().isEmpty ||
        sqlSet.primaryKeySql.trim().isEmpty) {
      throw Exception('请补充完整的逆向 SQL 配置。');
    }

    final savedJdkHome = await _runtimeSettingsRepository.getJdkHome();
    onLog?.call('开始准备逆向任务...');
    onLog?.call('正在调用 JDBC helper 查询元数据...');
    late JdbcReverseExecutionResult reverseResult;
    reverseResult = await _jdbcReverseService.reverse(
      request: JdbcReverseRequest(
        driver: driver,
        dataSource: dataSource,
        adapterType: hasDriverSql
            ? ReverseAdapterType.customSql
            : ReverseAdapterType.builtin,
        schemaName: effectiveSchemaName,
        catalogName: effectiveCatalogName,
        tableFilter: tableFilter,
        tableSql: sqlSet.tableSql,
        columnSql: sqlSet.columnSql,
        columnCommentSql: sqlSet.columnCommentSql,
        primaryKeySql: sqlSet.primaryKeySql,
      ),
      preferredJdkHome: savedJdkHome,
      onLog: onLog,
    );
    onLog?.call('元数据查询完成，开始过滤结果...');

    final schema = reverseResult.schema;
    final filteredSchema = _filterSchemaForComments(
      schema: _filterSchemaByTableFilter(
        schema: schema,
        tableFilter: tableFilter,
      ),
      includeTableComments: includeTableComments,
      includeColumnComments: includeColumnComments,
    );
    onLog?.call('结果过滤完成，开始生成 PDM XML...');
    final outputFile = File(outputPath);
    if (!outputFile.parent.existsSync()) {
      outputFile.parent.createSync(recursive: true);
    }
    final modelName = filteredSchema.dataSourceName.trim().isEmpty
        ? path.basenameWithoutExtension(outputFile.path)
        : filteredSchema.dataSourceName.trim();
    final xml = _pdmWriterService.buildPdmXml(
      schema: filteredSchema,
      modelName: modelName,
      sourcePath: outputFile.path,
    );
    onLog?.call('PDM XML 生成完成，开始写入文件...');
    await outputFile.writeAsString(xml);
    onLog?.call('文件写入完成。');

    if ((savedJdkHome ?? '').trim().isNotEmpty) {
      await _runtimeSettingsRepository.setJdkHome(savedJdkHome);
    }

    return ReverseExecutionOutcome(
      outputPath: outputFile.path,
      tableCount: filteredSchema.tables.length,
      logs: [
        '过滤后的表数量：${filteredSchema.tables.length}',
        'PDM 输出路径：${outputFile.path}',
      ],
    );
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchGeneration++;
    super.dispose();
  }

  Future<String?> createProject(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '项目名称不能为空。';
    }

    await _runBusy('正在新建项目...', () async {
      final project = await _projectRepository.createProject(trimmed);
      await _reloadProjects(selectedProjectId: project.id);
    });
    return null;
  }

  Future<String?> renameProject(String projectId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '项目名称不能为空。';
    }

    await _runBusy('正在更新项目...', () async {
      await _projectRepository.renameProject(projectId, trimmed);
      await _reloadProjects(selectedProjectId: projectId);
    });
    return null;
  }

  Future<String?> deleteProject(String projectId) async {
    await _runBusy('正在删除项目...', () async {
      await _projectRepository.deleteProject(projectId);
      _expandedProjectIds.remove(projectId);
      await _reloadProjects();
    });
    return null;
  }

  Future<void> selectProject(ProjectRecord project) async {
    _selectedProject = project;
    _selectedPdmFileId = null;
    _selectedResult = null;
    if (_searchTarget == SearchTarget.currentProject) {
      notifyListeners();
    }
    await _loadWorkspace();
  }

  Future<void> selectProjectFile(ProjectRecord project, String fileId) async {
    if (_selectedProject?.id != project.id) {
      _selectedProject = project;
      _projectFiles = await _projectRepository.getProjectFiles(project.id);
      _stats = await _projectRepository.getWorkspaceStats(project.id);
    }
    _selectedPdmFileId = fileId;
    _selectedResult = null;
    notifyListeners();
    await _refreshResults();
  }

  void toggleRootExpansion() {
    _isRootExpanded = !_isRootExpanded;
    notifyListeners();
  }

  void toggleProjectExpansion(String projectId) {
    if (_expandedProjectIds.contains(projectId)) {
      _expandedProjectIds.remove(projectId);
    } else {
      _expandedProjectIds.add(projectId);
    }
    notifyListeners();
  }

  void expandAllProjectNodes() {
    _isRootExpanded = true;
    _expandedProjectIds
      ..clear()
      ..addAll(_projects.map((project) => project.id));
    notifyListeners();
  }

  void collapseAllProjectNodes() {
    _isRootExpanded = true;
    _expandedProjectIds.clear();
    notifyListeners();
  }

  Future<String?> locateActiveTablePdm() async {
    final tab = activeTableTab;
    if (tab == null) {
      return null;
    }
    final projects = _projects.where((project) => project.id == tab.projectId);
    if (projects.isEmpty) {
      return null;
    }

    _isRootExpanded = true;
    _expandedProjectIds.add(tab.projectId);
    _selectedProject = projects.first;
    _selectedPdmFileId = tab.pdmFileId;
    _selectedResult = null;
    _treeLocationVersion++;
    notifyListeners();
    await _loadWorkspace();
    return tab.pdmFileId;
  }

  Future<String?> importPdmFilesForProject(
    String projectId, {
    String dialogTitle = '选择一个或多个 PDM 文件',
  }) async {
    final selection = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdm'],
      dialogTitle: dialogTitle,
    );
    if (selection == null || selection.files.isEmpty) {
      return null;
    }

    final filePaths = selection.files
        .map((file) => file.path?.trim() ?? '')
        .where((filePath) => filePath.isNotEmpty)
        .toList(growable: false);
    if (filePaths.isEmpty) {
      return null;
    }

    final projectFiles = await _projectRepository.upsertProjectFiles(
      projectId: projectId,
      filePaths: filePaths,
    );
    final fileByPath = {for (final file in projectFiles) file.path: file};

    final totalCount = filePaths.length;
    await _runBusy('正在导入 PDM...', () async {
      final updates = <ProjectPdmImportUpdate>[];
      for (var index = 0; index < filePaths.length; index++) {
        final filePath = filePaths[index];
        _setBusyLabel('正在导入 PDM（${index + 1}/$totalCount）...');
        final projectFile = fileByPath[filePath];
        if (projectFile == null) {
          continue;
        }

        try {
          final parsedResult = await _parserService.parseFileWithHash(filePath);
          updates.add(
            ProjectPdmImportUpdate(
              projectId: projectId,
              fileId: projectFile.id,
              lastImportedHash: parsedResult.fileHash,
              parsedFile: parsedResult.parsedFile,
            ),
          );
        } catch (error) {
          updates.add(
            ProjectPdmImportUpdate(
              projectId: projectId,
              fileId: projectFile.id,
              importError: error.toString(),
            ),
          );
        }
      }

      await _projectRepository.applyProjectImportUpdates(updates: updates);

      _expandedProjectIds.add(projectId);
      final matchedProject = _projects.cast<ProjectRecord?>().firstWhere(
        (item) => item?.id == projectId,
        orElse: () => null,
      );
      if (matchedProject != null) {
        _selectedProject = matchedProject;
      }
      await _loadWorkspace();
    });
    return null;
  }

  Future<void> checkForChangedPdmFilesOnStartup() async {
    final generation = ++_startupCheckGeneration;
    final projectNames = {
      for (final project in _projects) project.id: project.name,
    };
    final changes = <StartupPdmChange>[];

    for (final entry in _projectFilesByProjectId.entries) {
      final projectId = entry.key;
      final projectName = projectNames[projectId] ?? '未命名项目';
      for (final file in entry.value) {
        final status = await _detectStartupChangeStatus(file);
        if (status == null) {
          continue;
        }
        changes.add(
          StartupPdmChange(
            projectId: projectId,
            projectName: projectName,
            fileId: file.id,
            displayName: file.displayName,
            path: file.path,
            status: status,
          ),
        );
      }
    }

    if (generation != _startupCheckGeneration) {
      return;
    }
    _pendingStartupFileChanges = changes;
    _hasPendingStartupReloadPrompt = changes.isNotEmpty;
    notifyListeners();
  }

  Future<void> reloadChangedPdmFiles() async {
    final changes = List<StartupPdmChange>.from(_pendingStartupFileChanges);
    if (changes.isEmpty) {
      _startupCheckGeneration++;
      _hasPendingStartupReloadPrompt = false;
      notifyListeners();
      return;
    }

    _startupCheckGeneration++;
    _pendingStartupFileChanges = const [];
    _hasPendingStartupReloadPrompt = false;
    notifyListeners();

    final filesById = {
      for (final file in _projectFilesByProjectId.values.expand(
        (files) => files,
      ))
        file.id: file,
    };

    final totalCount = changes.length;
    await _runBusy('正在重新加载已变更的 PDM...', () async {
      final updates = <ProjectPdmImportUpdate>[];
      for (var index = 0; index < changes.length; index++) {
        final change = changes[index];
        _setBusyLabel('正在重新加载 PDM（${index + 1}/$totalCount）...');
        final file = filesById[change.fileId];
        if (file == null) {
          continue;
        }

        try {
          final parsedResult = await _parserService.parseFileWithHash(
            file.path,
          );
          updates.add(
            ProjectPdmImportUpdate(
              projectId: change.projectId,
              fileId: change.fileId,
              lastImportedHash: parsedResult.fileHash,
              parsedFile: parsedResult.parsedFile,
            ),
          );
        } catch (error) {
          updates.add(
            ProjectPdmImportUpdate(
              projectId: change.projectId,
              fileId: change.fileId,
              importError: error.toString(),
            ),
          );
        }
      }

      await _projectRepository.applyProjectImportUpdates(updates: updates);

      await _reloadProjectFilesMap();
      if (_selectedProject != null) {
        _projectFiles = projectFilesFor(_selectedProject!.id);
      }
      await _loadWorkspace();
    });
  }

  void dismissStartupReloadPrompt() {
    if (!_hasPendingStartupReloadPrompt && _pendingStartupFileChanges.isEmpty) {
      return;
    }
    _startupCheckGeneration++;
    _pendingStartupFileChanges = const [];
    _hasPendingStartupReloadPrompt = false;
    notifyListeners();
  }

  Future<String?> removePdmFile(
    String projectId,
    ProjectPdmFileRecord file,
  ) async {
    await _runBusy('正在移除 PDM...', () async {
      await _projectRepository.removeProjectFile(
        projectId: projectId,
        fileId: file.id,
      );
      if (_selectedPdmFileId == file.id) {
        _selectedPdmFileId = null;
      }
      _openTableTabs = _openTableTabs
          .where((tab) => tab.pdmFileId != file.id)
          .toList(growable: false);
      if (_activeTableTabId != null &&
          !_openTableTabs.any((tab) => tab.id == _activeTableTabId)) {
        _activeTableTabId = _openTableTabs.isEmpty
            ? null
            : _openTableTabs.last.id;
      }
      _syncActiveTabState();
      final matchedProject = _projects.cast<ProjectRecord?>().firstWhere(
        (item) => item?.id == projectId,
        orElse: () => null,
      );
      if (matchedProject != null) {
        _selectedProject = matchedProject;
      }
      await _loadWorkspace();
    });
    return null;
  }

  Future<String?> openPdmFolder(String filePath) async {
    final directory = path.dirname(filePath);
    if (!Directory(directory).existsSync()) {
      return '打开目录失败：$directory';
    }
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [
          directory,
        ], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [
          directory,
        ], mode: ProcessStartMode.detached);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [
          directory,
        ], mode: ProcessStartMode.detached);
      } else {
        return '当前平台暂不支持直接打开目录：$directory';
      }
      return null;
    } catch (_) {
      return '打开目录失败：$directory';
    }
  }

  void scheduleQueryUpdate(String value) {
    _draftQuery = value;
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounce, flushQueryNow);
  }

  Future<void> flushQueryNow() async {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = null;
    if (_draftQuery == _activeQuery) {
      return;
    }
    _activeQuery = _draftQuery;
    await _refreshResults();
  }

  Future<void> setScope(SearchScope value) async {
    if (_scope == value) {
      return;
    }
    _scope = value;
    notifyListeners();
    await _refreshResults();
  }

  Future<void> setSearchTarget(SearchTarget value) async {
    if (_searchTarget == value) {
      return;
    }
    _searchTarget = value;
    _selectedResult = null;
    _selectedTableDetail = null;
    notifyListeners();
    await _refreshResults();
  }

  Future<void> selectResult(SearchResultItem result) async {
    if (_selectedProject?.id != result.projectId) {
      final targetProject = _projects.where(
        (item) => item.id == result.projectId,
      );
      if (targetProject.isNotEmpty) {
        _selectedProject = targetProject.first;
        _projectFiles = await _projectRepository.getProjectFiles(
          result.projectId,
        );
        _stats = await _projectRepository.getWorkspaceStats(result.projectId);
      }
    }

    _selectedPdmFileId = result.pdmFileId;
    _selectedResult = result;
    final detail = await _searchRepository.getTableDetail(
      projectId: result.projectId,
      pdmFileId: result.pdmFileId,
      sourceTableId: result.sourceTableId,
    );
    if (detail == null) {
      _selectedTableDetail = null;
      notifyListeners();
      return;
    }
    final tabId = _buildTableTabId(
      projectId: result.projectId,
      pdmFileId: result.pdmFileId,
      sourceTableId: result.sourceTableId,
    );
    final nextTab = TableDetailTab(
      id: tabId,
      projectId: result.projectId,
      projectName: result.projectName,
      pdmFileId: result.pdmFileId,
      sourceTableId: result.sourceTableId,
      sourcePdm: detail.sourcePdm,
      tableName: detail.tableName,
      tableCode: detail.tableCode,
      comment: detail.comment,
      highlightedColumnIds: result.matchedColumnIds,
    );
    final existingIndex = _openTableTabs.indexWhere((tab) => tab.id == tabId);
    if (existingIndex >= 0) {
      final mutableTabs = _openTableTabs.toList(growable: true);
      mutableTabs[existingIndex] = nextTab;
      _openTableTabs = mutableTabs;
    } else {
      _openTableTabs = [..._openTableTabs, nextTab];
    }
    _activeTableTabId = tabId;
    _tableActivationVersion++;
    await _syncActiveTabState(preloadedDetail: detail, preferredResult: result);
    notifyListeners();
  }

  Future<TableDetail?> loadTableDetailForResult(SearchResultItem result) {
    return _searchRepository.getTableDetail(
      projectId: result.projectId,
      pdmFileId: result.pdmFileId,
      sourceTableId: result.sourceTableId,
    );
  }

  Future<Map<String, TableDetail>> loadTableDetailsForResults(
    List<SearchResultItem> results,
  ) {
    return _searchRepository.getTableDetailsForResults(results);
  }

  Future<List<SearchResultItem>> loadPreviewTargetsForProject(
    String projectId,
  ) {
    return _searchRepository.browse(projectId: projectId);
  }

  Future<List<SearchResultItem>> loadPreviewTargetsForPdmFile({
    required String projectId,
    required String pdmFileId,
  }) {
    return _searchRepository.browse(projectId: projectId, pdmFileId: pdmFileId);
  }

  Future<void> selectTableTab(String tabId) async {
    if (_activeTableTabId == tabId) {
      return;
    }
    _activeTableTabId = tabId;
    await _syncActiveTabState();
    notifyListeners();
  }

  void closeTableTab(String tabId) {
    final existingIndex = _openTableTabs.indexWhere((tab) => tab.id == tabId);
    if (existingIndex < 0) {
      return;
    }
    final mutableTabs = _openTableTabs.toList(growable: true)
      ..removeAt(existingIndex);
    _openTableTabs = mutableTabs;
    if (_activeTableTabId == tabId) {
      if (_openTableTabs.isEmpty) {
        _activeTableTabId = null;
      } else {
        final nextIndex = existingIndex == 0 ? 0 : existingIndex - 1;
        _activeTableTabId = _openTableTabs[nextIndex].id;
      }
    }
    unawaited(_syncActiveTabState());
    notifyListeners();
  }

  void closeAllTableTabs() {
    if (_openTableTabs.isEmpty) {
      return;
    }
    _openTableTabs = const [];
    _activeTableTabId = null;
    _selectedTableDetail = null;
    notifyListeners();
  }

  void closeLeftTableTabs(String tabId) {
    final existingIndex = _openTableTabs.indexWhere((tab) => tab.id == tabId);
    if (existingIndex <= 0) {
      return;
    }
    _openTableTabs = _openTableTabs
        .sublist(existingIndex)
        .toList(growable: false);
    unawaited(_syncActiveTabState());
    notifyListeners();
  }

  void closeRightTableTabs(String tabId) {
    final existingIndex = _openTableTabs.indexWhere((tab) => tab.id == tabId);
    if (existingIndex < 0 || existingIndex >= _openTableTabs.length - 1) {
      return;
    }
    _openTableTabs = _openTableTabs
        .sublist(0, existingIndex + 1)
        .toList(growable: false);
    unawaited(_syncActiveTabState());
    notifyListeners();
  }

  void closeOtherTableTabs(String tabId) {
    final existingIndex = _openTableTabs.indexWhere((tab) => tab.id == tabId);
    if (existingIndex < 0 || _openTableTabs.length <= 1) {
      return;
    }
    _openTableTabs = [_openTableTabs[existingIndex]];
    _activeTableTabId = tabId;
    _syncActiveTabState();
    notifyListeners();
  }

  Future<void> _reloadProjects({String? selectedProjectId}) async {
    _projects = await _projectRepository.getProjects();
    final resolvedSelection = selectedProjectId ?? _selectedProject?.id;
    final shouldSelectFirstProjectByDefault =
        resolvedSelection == null && _selectedProject == null;

    if (_projects.isEmpty) {
      _selectedProject = null;
      _selectedPdmFileId = null;
      _projectFiles = const [];
      _projectFilesByProjectId = const {};
      _results = const [];
      _selectedResult = null;
      _selectedTableDetail = null;
      _openTableTabs = const [];
      _activeTableTabId = null;
      _stats = await _projectRepository.getWorkspaceStats(null);
      notifyListeners();
      return;
    }

    _selectedProject = _projects.firstWhere(
      (project) => project.id == resolvedSelection,
      orElse: () => _projects.first,
    );
    if (shouldSelectFirstProjectByDefault) {
      _expandedProjectIds.add(_selectedProject!.id);
    }
    await _reloadProjectFilesMap();
    await _loadWorkspace();
  }

  Future<void> _loadWorkspace() async {
    final project = _selectedProject;
    if (project == null) {
      _projectFiles = const [];
      _results = const [];
      _selectedResult = null;
      _selectedTableDetail = null;
      _openTableTabs = const [];
      _activeTableTabId = null;
      _stats = await _projectRepository.getWorkspaceStats(null);
      notifyListeners();
      return;
    }

    await _reloadProjectFilesMap();
    _projectFiles = projectFilesFor(project.id);
    if (_selectedPdmFileId != null &&
        !_projectFiles.any((file) => file.id == _selectedPdmFileId)) {
      _selectedPdmFileId = null;
    }
    _stats = await _projectRepository.getWorkspaceStats(project.id);
    await _refreshResults();
  }

  Future<void> _refreshResults() async {
    final generation = ++_searchGeneration;
    final project = _selectedProject;
    final useGlobalSearch = _searchTarget == SearchTarget.allProjects;
    final scopedProjectId = useGlobalSearch ? null : project?.id;
    final scopedPdmId = useGlobalSearch ? null : _selectedPdmFileId;

    if (project == null) {
      _results = const [];
      _selectedResult = null;
      _selectedTableDetail = null;
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    late final List<SearchResultItem> results;
    try {
      results = await _searchRepository.search(
        projectId: scopedProjectId,
        keyword: _activeQuery,
        scope: _scope,
        pdmFileId: scopedPdmId,
      );
    } catch (_) {
      if (generation != _searchGeneration) return;
      _isSearching = false;
      notifyListeners();
      rethrow;
    }

    if (generation != _searchGeneration) {
      return;
    }

    _results = _sortResultsByCode(results);
    _isSearching = false;

    if (_results.isEmpty) {
      _selectedResult = null;
      unawaited(_syncActiveTabState());
      notifyListeners();
      return;
    }

    if (_selectedResult != null) {
      final existing = _results.where((item) => item.id == _selectedResult!.id);
      if (existing.isNotEmpty) {
        _selectedResult = existing.first;
        notifyListeners();
        return;
      }
    }

    _selectedResult = null;
    unawaited(_syncActiveTabState());
    notifyListeners();
  }

  List<SearchResultItem> _sortResultsByCode(List<SearchResultItem> results) {
    final sorted = List<SearchResultItem>.from(results);
    sorted.sort((left, right) {
      final leftCode = _normalizedResultCode(left);
      final rightCode = _normalizedResultCode(right);
      final codeCompare = leftCode.compareTo(rightCode);
      if (codeCompare != 0) {
        return codeCompare;
      }

      final commentCompare = left.comment.trim().compareTo(
        right.comment.trim(),
      );
      if (commentCompare != 0) {
        return commentCompare;
      }

      final pdmCompare = left.sourcePdm.compareTo(right.sourcePdm);
      if (pdmCompare != 0) {
        return pdmCompare;
      }

      return left.id.compareTo(right.id);
    });
    return sorted;
  }

  String _normalizedResultCode(SearchResultItem item) {
    final code = (item.tableCode ?? '').trim();
    if (code.isNotEmpty) {
      return code.toUpperCase();
    }
    return item.title.trim().toUpperCase();
  }

  Future<void> _syncActiveTabState({
    TableDetail? preloadedDetail,
    SearchResultItem? preferredResult,
  }) async {
    final activeTab = activeTableTab;
    if (activeTab == null) {
      _selectedTableDetail = null;
      return;
    }

    final generation = ++_detailLoadGeneration;
    final detail =
        preloadedDetail ??
        await _searchRepository.getTableDetail(
          projectId: activeTab.projectId,
          pdmFileId: activeTab.pdmFileId,
          sourceTableId: activeTab.sourceTableId,
        );
    if (generation != _detailLoadGeneration) {
      return;
    }

    _selectedTableDetail = detail;
    _selectedResult =
        preferredResult ??
        _results.cast<SearchResultItem?>().firstWhere(
          (item) =>
              item?.projectId == activeTab.projectId &&
              item?.pdmFileId == activeTab.pdmFileId &&
              item?.sourceTableId == activeTab.sourceTableId,
          orElse: () => _selectedResult,
        );
  }

  String _buildTableTabId({
    required String projectId,
    required String pdmFileId,
    required String sourceTableId,
  }) {
    return '$projectId:$pdmFileId:$sourceTableId';
  }

  Future<void> _reloadProjectFilesMap() async {
    final filesByProjectId = <String, List<ProjectPdmFileRecord>>{};
    for (final project in _projects) {
      filesByProjectId[project.id] = await _projectRepository.getProjectFiles(
        project.id,
      );
    }
    _projectFilesByProjectId = filesByProjectId;
  }

  Future<StartupPdmChangeStatus?> _detectStartupChangeStatus(
    ProjectPdmFileRecord file,
  ) async {
    if ((file.lastImportedHash ?? '').trim().isEmpty) {
      return StartupPdmChangeStatus.baselineMissing;
    }

    try {
      final currentHash = await _parserService.computeFileHash(file.path);
      if (currentHash != file.lastImportedHash) {
        return StartupPdmChangeStatus.modified;
      }
      return null;
    } catch (_) {
      return StartupPdmChangeStatus.missingOrUnreadable;
    }
  }

  Future<void> _runBusy(String label, Future<void> Function() action) async {
    _isBusy = true;
    _busyLabel = label;
    notifyListeners();
    try {
      await action();
    } finally {
      _isBusy = false;
      _busyLabel = null;
      notifyListeners();
    }
  }

  void _setBusyLabel(String label) {
    if (_busyLabel == label) {
      return;
    }
    _busyLabel = label;
    notifyListeners();
  }

  ReverseSchemaModel _filterSchemaForComments({
    required ReverseSchemaModel schema,
    required bool includeTableComments,
    required bool includeColumnComments,
  }) {
    return ReverseSchemaModel(
      databaseType: schema.databaseType,
      dataSourceName: schema.dataSourceName,
      schemaName: schema.schemaName,
      catalogName: schema.catalogName,
      tables: schema.tables
          .map(
            (table) => ReverseTableModel(
              name: table.name,
              code: table.code,
              comment: includeTableComments ? table.comment : '',
              schemaName: table.schemaName,
              rawIdentifier: table.rawIdentifier,
              columns: table.columns
                  .map(
                    (column) => ReverseColumnModel(
                      name: column.name,
                      code: column.code,
                      dataType: column.dataType,
                      length: column.length,
                      precision: column.precision,
                      nullable: column.nullable,
                      defaultValue: column.defaultValue,
                      isPrimaryKey: column.isPrimaryKey,
                      comment: includeColumnComments ? column.comment : '',
                      ordinalPosition: column.ordinalPosition,
                    ),
                  )
                  .toList(growable: false),
            ),
          )
          .toList(growable: false),
    );
  }

  ReverseSchemaModel _filterSchemaByTableFilter({
    required ReverseSchemaModel schema,
    required String tableFilter,
  }) {
    final rawFilter = tableFilter.trim();
    if (rawFilter.isEmpty) {
      return schema;
    }

    final explicitNames = rawFilter
        .split(RegExp(r'[\r\n,，;；]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final isExplicitList =
        explicitNames.length > 1 || RegExp(r'[\r\n,，;；]').hasMatch(rawFilter);

    late final List<ReverseTableModel> tables;
    if (isExplicitList) {
      final nameSet = explicitNames.map((item) => item.toUpperCase()).toSet();
      tables = schema.tables
          .where((table) {
            final code = table.code.trim().toUpperCase();
            final name = table.name.trim().toUpperCase();
            return nameSet.contains(code) || nameSet.contains(name);
          })
          .toList(growable: false);
    } else {
      late final RegExp expression;
      try {
        expression = RegExp(rawFilter, caseSensitive: false);
      } on FormatException catch (error) {
        throw Exception('表名过滤正则无效：${error.message}');
      }
      tables = schema.tables
          .where((table) {
            return expression.hasMatch(table.code) ||
                expression.hasMatch(table.name);
          })
          .toList(growable: false);
    }

    return ReverseSchemaModel(
      databaseType: schema.databaseType,
      dataSourceName: schema.dataSourceName,
      schemaName: schema.schemaName,
      catalogName: schema.catalogName,
      tables: tables,
    );
  }
}

class ReverseExecutionOutcome {
  const ReverseExecutionOutcome({
    required this.outputPath,
    required this.tableCount,
    required this.logs,
  });

  final String outputPath;
  final int tableCount;
  final List<String> logs;
}
