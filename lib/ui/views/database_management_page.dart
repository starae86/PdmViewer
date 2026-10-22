import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../app/l10n/app_strings.dart';

import '../../app/state/app_controller.dart';
import '../../app/theme/app_theme.dart';
import '../widgets/chrome_surface.dart';
import '../../domain/models/jdbc_models.dart';
import '../../domain/models/reverse_models.dart';

enum DatabaseManagementSection {
  drivers('驱动管理'),
  dataSources('数据源管理'),
  reverse('逆向生成');

  const DatabaseManagementSection(this.label);
  final String label;
}

class DatabaseManagementPage extends StatefulWidget {
  const DatabaseManagementPage({
    super.key,
    required this.controller,
    required this.onBack,
    required this.initialSection,
  });

  final AppController controller;
  final VoidCallback onBack;
  final DatabaseManagementSection initialSection;

  @override
  State<DatabaseManagementPage> createState() => DatabaseManagementPageState();
}

class DatabaseManagementPageState extends State<DatabaseManagementPage> {
  static const double _minLeftPaneWidth = 220;
  static const double _maxLeftPaneWidth = 420;
  static const double _dividerThickness = 8;
  static const double _minReverseTopPaneHeight = 320;
  static const double _minReverseBottomPaneHeight = 140;
  static const double _sectionPadding = 10;
  static const double _fieldSpacing = 8;
  static const double _fieldLabelWidth = 112;

  List<JdbcDriverRecord> _drivers = const [];
  List<DataSourceRecord> _dataSources = const [];
  List<ReverseTaskPreset> _presets = const [];
  bool _loading = true;
  bool _savingDriver = false;
  bool _savingDataSource = false;
  bool _testingDataSource = false;
  bool _runningReverse = false;
  bool _confirmingLeave = false;
  bool _driverDraftPending = false;
  bool _dataSourceDraftPending = false;
  List<Object?> _driverBaseline = const [];
  List<Object?> _dataSourceBaseline = const [];
  String? _jdkHome;
  List<String> _reverseLogs = const [];

  String? _selectedDriverId;
  String? _selectedDataSourceId;
  DatabaseManagementSection _activeSection = DatabaseManagementSection.drivers;

  late final TextEditingController _driverNameController;
  late final TextEditingController _driverClassController;
  late final TextEditingController _driverJdbcUrlTemplateController;
  late final TextEditingController _driverNotesController;
  late final TextEditingController _driverTableSqlController;
  late final TextEditingController _driverColumnSqlController;
  late final TextEditingController _driverColumnCommentSqlController;
  late final TextEditingController _driverPrimaryKeySqlController;
  JdbcDatabaseType _driverDatabaseType = JdbcDatabaseType.mysql;
  List<String> _driverJarPaths = const [];

  late final TextEditingController _dataSourceNameController;
  late final TextEditingController _jdbcUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _schemaController;
  late final TextEditingController _catalogController;
  JdbcDatabaseType _dataSourceDatabaseType = JdbcDatabaseType.mysql;
  String _lastAppliedJdbcUrlTemplate = '';

  late final TextEditingController _reverseSchemaController;
  late final TextEditingController _reverseCatalogController;
  late final TextEditingController _tableFilterController;
  late final TextEditingController _outputPathController;
  late final TextEditingController _reverseLogTextController;
  late final ScrollController _reverseLogScrollController;
  bool _includeTableComments = true;
  bool _includeColumnComments = true;
  double _leftPaneWidth = 250;
  double _reverseTopPaneRatio = 0.62;

  @override
  void initState() {
    super.initState();
    _activeSection = widget.initialSection;
    _driverNameController = TextEditingController();
    _driverClassController = TextEditingController();
    _driverJdbcUrlTemplateController = TextEditingController();
    _driverNotesController = TextEditingController();
    _driverTableSqlController = TextEditingController();
    _driverColumnSqlController = TextEditingController();
    _driverColumnCommentSqlController = TextEditingController();
    _driverPrimaryKeySqlController = TextEditingController();
    _dataSourceNameController = TextEditingController();
    _jdbcUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _schemaController = TextEditingController();
    _catalogController = TextEditingController();
    _reverseSchemaController = TextEditingController();
    _reverseCatalogController = TextEditingController();
    _tableFilterController = TextEditingController();
    _outputPathController = TextEditingController();
    _reverseLogTextController = TextEditingController();
    _reverseLogScrollController = ScrollController();
    _reload();
  }

  @override
  void didUpdateWidget(covariant DatabaseManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      selectSection(widget.initialSection);
    }
  }

  @override
  void dispose() {
    _driverNameController.dispose();
    _driverClassController.dispose();
    _driverJdbcUrlTemplateController.dispose();
    _driverNotesController.dispose();
    _driverTableSqlController.dispose();
    _driverColumnSqlController.dispose();
    _driverColumnCommentSqlController.dispose();
    _driverPrimaryKeySqlController.dispose();
    _dataSourceNameController.dispose();
    _jdbcUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _schemaController.dispose();
    _catalogController.dispose();
    _reverseSchemaController.dispose();
    _reverseCatalogController.dispose();
    _tableFilterController.dispose();
    _outputPathController.dispose();
    _reverseLogTextController.dispose();
    _reverseLogScrollController.dispose();
    super.dispose();
  }

  JdbcDriverRecord? get _selectedDriver {
    final id = _selectedDriverId;
    if (id == null) {
      return null;
    }
    for (final driver in _drivers) {
      if (driver.id == id) {
        return driver;
      }
    }
    return null;
  }

  DataSourceRecord? get _selectedDataSource {
    final id = _selectedDataSourceId;
    if (id == null) {
      return null;
    }
    for (final item in _dataSources) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  Future<void> _reload() async {
    final drivers = await widget.controller.getJdbcDrivers();
    final dataSources = await widget.controller.getDataSources();
    final presets = await widget.controller.getReverseTaskPresets();
    final jdkHome = await widget.controller.getSavedJdkHome();
    if (!mounted) {
      return;
    }

    final sortedDrivers = List<JdbcDriverRecord>.from(drivers)
      ..sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
    final sortedDataSources = List<DataSourceRecord>.from(dataSources)
      ..sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );

    setState(() {
      _drivers = sortedDrivers;
      _dataSources = sortedDataSources;
      _presets = presets;
      _jdkHome = jdkHome;
      _loading = false;
    });

    if (_selectedDriverId == null && sortedDrivers.isNotEmpty) {
      _selectedDriverId = sortedDrivers.first.id;
    }
    if (_selectedDriver == null &&
        _activeSection == DatabaseManagementSection.drivers) {
      _createNewDriverDraft();
    } else {
      _syncSelectedDriverToForm();
    }
    final driverId = _selectedDriverId;
    _syncSelectedDataSourceAfterReload();
    if (_isDriverSection) _selectedDriverId = driverId;
    _ensureSectionSelection();
  }

  void _selectDriver(String driverId) {
    setState(() {
      _selectedDriverId = driverId;
    });
    _syncSelectedDriverToForm();
  }

  void _syncSelectedDriverToForm() {
    final driver = _selectedDriver;
    if (driver == null) {
      _createNewDriverDraft();
      return;
    }
    final defaultSql = widget.controller.buildReverseSqlPreview(
      driver.databaseType,
    );
    _driverNameController.text = driver.name;
    _driverClassController.text = driver.driverClass;
    _driverJdbcUrlTemplateController.text = driver.jdbcUrlTemplate;
    _driverNotesController.text = driver.notes;
    _driverTableSqlController.text = driver.tableSql.trim().isEmpty
        ? defaultSql.tableSql
        : driver.tableSql;
    _driverColumnSqlController.text = driver.columnSql.trim().isEmpty
        ? defaultSql.columnSql
        : driver.columnSql;
    _driverColumnCommentSqlController.text =
        driver.columnCommentSql.trim().isEmpty
        ? defaultSql.columnCommentSql
        : driver.columnCommentSql;
    _driverPrimaryKeySqlController.text = driver.primaryKeySql.trim().isEmpty
        ? defaultSql.primaryKeySql
        : driver.primaryKeySql;
    _driverDatabaseType = driver.databaseType;
    _driverJarPaths = List<String>.from(driver.jarPaths);
    _driverDraftPending = false;
    _driverBaseline = _driverValues;
  }

  void _createNewDriverDraft() {
    setState(() {
      _selectedDriverId = null;
      _driverDatabaseType = JdbcDatabaseType.mysql;
      _driverJarPaths = const [];
    });
    _driverNameController.clear();
    _driverClassController.clear();
    _driverJdbcUrlTemplateController.clear();
    _driverNotesController.clear();
    _driverTableSqlController.clear();
    _driverColumnSqlController.clear();
    _driverColumnCommentSqlController.clear();
    _driverPrimaryKeySqlController.clear();
    _driverDraftPending = false;
    _driverBaseline = _driverValues;
  }

  void _syncSelectedDataSourceAfterReload() {
    if (_dataSources.isEmpty) {
      _clearDataSourceDraft();
      return;
    }

    if (_selectedDataSourceId == null ||
        !_dataSources.any((item) => item.id == _selectedDataSourceId)) {
      _selectDataSource(_dataSources.first.id);
      return;
    }

    _syncSelectedDataSourceToForm();
  }

  void _selectDataSource(String dataSourceId) {
    final record = _dataSources.cast<DataSourceRecord?>().firstWhere(
      (item) => item?.id == dataSourceId,
      orElse: () => null,
    );
    setState(() {
      _selectedDataSourceId = dataSourceId;
      if (record != null) {
        _selectedDriverId = record.driverId;
      }
    });
    _syncSelectedDataSourceToForm();
  }

  void _clearDataSourceDraft() {
    setState(() {
      _selectedDataSourceId = null;
      _selectedDriverId ??= _drivers.isEmpty ? null : _drivers.first.id;
      _dataSourceDatabaseType =
          _selectedDriver?.databaseType ?? JdbcDatabaseType.mysql;
    });
    _dataSourceNameController.clear();
    _jdbcUrlController.clear();
    _lastAppliedJdbcUrlTemplate = '';
    _usernameController.clear();
    _passwordController.clear();
    _schemaController.clear();
    _catalogController.clear();
    _syncReverseFormFromDataSource(null);
    _dataSourceDraftPending = false;
    _dataSourceBaseline = _dataSourceValues;
  }

  void _syncSelectedDataSourceToForm() {
    final record = _selectedDataSource;
    if (record == null) {
      _clearDataSourceDraft();
      return;
    }
    final driver = _drivers.cast<JdbcDriverRecord?>().firstWhere(
      (item) => item?.id == record.driverId,
      orElse: () => null,
    );
    if (driver != null) {
      _selectedDriverId = driver.id;
    }
    _dataSourceNameController.text = record.name;
    _jdbcUrlController.text = record.jdbcUrl;
    _lastAppliedJdbcUrlTemplate = '';
    _usernameController.text = record.username;
    _passwordController.text = record.password;
    _schemaController.text = record.schemaName;
    _catalogController.text = record.catalogName;
    _dataSourceDatabaseType = record.databaseType;
    _syncReverseFormFromDataSource(record);
    _dataSourceDraftPending = false;
    _dataSourceBaseline = _dataSourceValues;
  }

  void _syncReverseFormFromDataSource(DataSourceRecord? record) {
    final preset = _presets.isEmpty ? null : _presets.first;
    _reverseSchemaController.text = record == null
        ? ''
        : (preset?.schemaName.isNotEmpty == true
              ? preset!.schemaName
              : record.schemaName);
    _reverseCatalogController.text = record == null
        ? ''
        : (preset?.catalogName.isNotEmpty == true
              ? preset!.catalogName
              : record.catalogName);
    _tableFilterController.text = preset?.tableNames ?? '';
    _outputPathController.text = preset?.outputPath ?? '';
    _includeTableComments = preset?.includeTableComments ?? true;
    _includeColumnComments = preset?.includeColumnComments ?? true;
  }

  void _applyJdbcUrlTemplateForSelectedDriver({bool force = false}) {
    final driver = _selectedDriver;
    if (driver == null) {
      return;
    }
    final template = driver.jdbcUrlTemplate.trim();
    final current = _jdbcUrlController.text.trim();
    if (template.isEmpty) {
      if (force && current == _lastAppliedJdbcUrlTemplate) {
        _jdbcUrlController.clear();
        _lastAppliedJdbcUrlTemplate = '';
      }
      return;
    }
    if (force || current.isEmpty || current == _lastAppliedJdbcUrlTemplate) {
      _jdbcUrlController.text = template;
      _lastAppliedJdbcUrlTemplate = template;
    }
  }

  Future<bool> selectSection(DatabaseManagementSection section) async {
    if (_activeSection == section) {
      return true;
    }
    if (!await _confirmLeave() || !mounted) return false;
    setState(() {
      _activeSection = section;
    });
    _ensureSectionSelection();
    return true;
  }

  List<Object?> get _driverValues => [
    _driverNameController.text,
    _driverClassController.text,
    _driverJdbcUrlTemplateController.text,
    _driverNotesController.text,
    _driverTableSqlController.text,
    _driverColumnSqlController.text,
    _driverColumnCommentSqlController.text,
    _driverPrimaryKeySqlController.text,
    _driverDatabaseType,
    ..._driverJarPaths,
  ];

  List<Object?> get _dataSourceValues => [
    _dataSourceNameController.text,
    _jdbcUrlController.text,
    _usernameController.text,
    _passwordController.text,
    _schemaController.text,
    _catalogController.text,
    _dataSourceDatabaseType,
    _selectedDriverId,
  ];

  bool get _hasUnsavedChanges =>
      !_loading &&
      switch (_activeSection) {
        DatabaseManagementSection.drivers =>
          _driverDraftPending || !listEquals(_driverBaseline, _driverValues),
        DatabaseManagementSection.dataSources =>
          _dataSourceDraftPending ||
              !listEquals(_dataSourceBaseline, _dataSourceValues),
        DatabaseManagementSection.reverse => false,
      };

  Future<bool> _confirmLeave() async {
    if (_confirmingLeave || _savingDriver || _savingDataSource) return false;
    if (!_hasUnsavedChanges) return true;
    _confirmingLeave = true;
    try {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const LText('未保存的更改'),
          content: const LText('当前配置尚未保存，是否保存后继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const LText('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'discard'),
              child: const LText('不保存'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: const LText('保存'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null || choice == 'cancel') return false;
      if (choice == 'save') {
        if (_isDriverSection) {
          await _saveDriver(showSuccess: false);
        } else {
          await _saveDataSource(showSuccess: false);
        }
        return mounted && !_hasUnsavedChanges;
      }
      if (_isDriverSection) {
        _syncSelectedDriverToForm();
      } else {
        _syncSelectedDataSourceToForm();
      }
      return true;
    } finally {
      _confirmingLeave = false;
    }
  }

  Future<void> _runGuarded(VoidCallback action) async {
    if (await _confirmLeave() && mounted) action();
  }

  void _newDriver() {
    _createNewDriverDraft();
    _driverDraftPending = true;
  }

  void _newDataSource() {
    _clearDataSourceDraft();
    _dataSourceDraftPending = true;
  }

  void _ensureSectionSelection() {
    if (_activeSection == DatabaseManagementSection.drivers) {
      if (_selectedDriverId == null && _drivers.isNotEmpty) {
        _selectDriver(_drivers.first.id);
      } else if (_selectedDriver == null) {
        _createNewDriverDraft();
      } else {
        _syncSelectedDriverToForm();
      }
      return;
    }

    if (_selectedDataSourceId == null && _dataSources.isNotEmpty) {
      _selectDataSource(_dataSources.first.id);
      return;
    }
    if (_selectedDataSource == null) {
      _clearDataSourceDraft();
      return;
    }
    _syncSelectedDataSourceToForm();
  }

  void _appendReverseLogs(Iterable<String> entries) {
    final nextEntries = entries
        .where((item) => item.trim().isNotEmpty)
        .map(_formatReverseLogLine)
        .toList(growable: false);
    if (nextEntries.isEmpty) {
      return;
    }
    setState(() {
      _reverseLogs = [..._reverseLogs, ...nextEntries];
      _reverseLogTextController.text = _reverseLogs.join('\n');
      _reverseLogTextController.selection = TextSelection.collapsed(
        offset: _reverseLogTextController.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_reverseLogScrollController.hasClients) {
        return;
      }
      _reverseLogScrollController.animateTo(
        _reverseLogScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _clearReverseLogs() {
    setState(() {
      _reverseLogs = const [];
      _reverseLogTextController.clear();
    });
  }

  String _formatReverseLogLine(String message) {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return '[$hour:$minute:$second] ${context.tr(message)}';
  }

  Future<void> _pickDriverJars() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['jar'],
      dialogTitle: context.tr('选择 JDBC 驱动 JAR'),
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    setState(() {
      _driverJarPaths = result.files
          .map((item) => item.path ?? '')
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
    });
  }

  Future<void> _saveDriver({bool showSuccess = true}) async {
    if (_savingDriver) {
      return;
    }
    final name = _driverNameController.text.trim();
    final driverClass = _driverClassController.text.trim();
    if (name.isEmpty || driverClass.isEmpty) {
      await _showBlockingMessageDialog(
        context,
        title: '无法保存驱动',
        message: context.tr('请填写驱动名称和驱动类名。'),
      );
      return;
    }
    final current = _selectedDriver;
    final duplicateNameExists = _drivers.any(
      (driver) =>
          driver.id != current?.id &&
          driver.name.trim().toLowerCase() == name.toLowerCase(),
    );
    if (duplicateNameExists) {
      await _showBlockingMessageDialog(
        context,
        title: '无法保存驱动',
        message: context.tr('驱动名称不能重复。'),
      );
      return;
    }

    setState(() => _savingDriver = true);
    try {
      if (current == null) {
        final record = await widget.controller.createJdbcDriver(
          name: name,
          databaseType: _driverDatabaseType,
          driverClass: driverClass,
          jdbcUrlTemplate: _driverJdbcUrlTemplateController.text,
          jarPaths: _driverJarPaths,
          tableSql: _driverTableSqlController.text,
          columnSql: _driverColumnSqlController.text,
          columnCommentSql: _driverColumnCommentSqlController.text,
          primaryKeySql: _driverPrimaryKeySqlController.text,
          notes: _driverNotesController.text,
        );
        await _reload();
        if (mounted) {
          _selectDriver(record.id);
        }
      } else {
        await widget.controller.updateJdbcDriver(
          id: current.id,
          name: name,
          databaseType: _driverDatabaseType,
          driverClass: driverClass,
          jdbcUrlTemplate: _driverJdbcUrlTemplateController.text,
          jarPaths: _driverJarPaths,
          tableSql: _driverTableSqlController.text,
          columnSql: _driverColumnSqlController.text,
          columnCommentSql: _driverColumnCommentSqlController.text,
          primaryKeySql: _driverPrimaryKeySqlController.text,
          notes: _driverNotesController.text,
        );
        await _reload();
      }
      if (!mounted) {
        return;
      }
      if (showSuccess) {
        await _showBlockingMessageDialog(
          context,
          title: '保存成功',
          message: context.tr('驱动已保存。'),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showBlockingMessageDialog(
        context,
        title: '保存失败',
        message: error.toString(),
      );
    } finally {
      if (mounted) {
        setState(() => _savingDriver = false);
      }
    }
  }

  Future<void> _deleteSelectedDriver() async {
    final driver = _selectedDriver;
    if (driver == null || driver.isBuiltInTemplate) {
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const LText('删除驱动'),
            content: LText('确认删除“${driver.name}”吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const LText('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const LText('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }
    try {
      await widget.controller.deleteJdbcDriver(driver.id);
      await _reload();
      if (mounted && _drivers.isNotEmpty) {
        _selectDriver(_drivers.first.id);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showBlockingMessageDialog(
        context,
        title: '删除失败',
        message: error.toString().replaceFirst('Bad state: ', ''),
      );
    }
  }

  JdbcBuiltInDriverTemplate? _currentBuiltInTemplate() {
    final driver = _selectedDriver;
    if (driver == null || !driver.isBuiltInTemplate) {
      return null;
    }
    for (final template in kJdbcBuiltInDriverTemplates) {
      if (template.name == driver.name) {
        return template;
      }
    }
    return null;
  }

  void _restoreBuiltInDriverDefaults() {
    final template = _currentBuiltInTemplate();
    if (template == null) {
      return;
    }
    final defaultSql = widget.controller.buildReverseSqlPreview(
      template.databaseType,
    );
    setState(() {
      _driverDatabaseType = template.databaseType;
      _driverClassController.text = template.driverClass;
      _driverJdbcUrlTemplateController.text = template.jdbcUrlTemplate;
      _driverTableSqlController.text = defaultSql.tableSql;
      _driverColumnSqlController.text = defaultSql.columnSql;
      _driverColumnCommentSqlController.text = defaultSql.columnCommentSql;
      _driverPrimaryKeySqlController.text = defaultSql.primaryKeySql;
      _driverJarPaths = const [];
    });
  }

  void _duplicateDriver() {
    final sourceName = _driverNameController.text.trim();
    final name = _nextCopyName(sourceName, _drivers.map((item) => item.name));
    setState(() {
      _selectedDriverId = null;
      _driverNameController.text = name;
      _driverDraftPending = true;
    });
  }

  void _duplicateDataSource() {
    final name = _nextCopyName(
      _dataSourceNameController.text.trim(),
      _dataSources.map((item) => item.name),
    );
    setState(() {
      _selectedDataSourceId = null;
      _dataSourceNameController.text = name;
      _dataSourceDraftPending = true;
    });
  }

  String _nextCopyName(String baseName, Iterable<String> names) {
    final existing = names.map((name) => name.trim().toLowerCase()).toSet();
    final base = '${baseName}_${context.tr('副本')}';
    var candidate = base;
    var index = 2;
    while (existing.contains(candidate.toLowerCase())) {
      candidate = '$base${index++}';
    }
    return candidate;
  }

  Future<void> _saveDataSource({bool showSuccess = true}) async {
    if (_savingDataSource) {
      return;
    }
    final driver = _selectedDriver;
    if (driver == null) {
      await _showBlockingMessageDialog(
        context,
        title: '无法保存数据源',
        message: context.tr('请先选择一个驱动。'),
      );
      return;
    }
    final name = _dataSourceNameController.text.trim();
    if (name.isEmpty) {
      await _showBlockingMessageDialog(
        context,
        title: '无法保存数据源',
        message: context.tr('请填写数据源名称。'),
      );
      return;
    }
    final validationMessage = _validateDataSourceBeforeSave(driver);
    if (_dataSources.any(
      (item) =>
          item.id != _selectedDataSourceId &&
          item.name.trim().toLowerCase() == name.toLowerCase(),
    )) {
      await _showBlockingMessageDialog(
        context,
        title: '无法保存数据源',
        message: context.tr('数据源名称不能重复。'),
      );
      return;
    }
    if (validationMessage != null) {
      await _showBlockingMessageDialog(
        context,
        title: '无法保存数据源',
        message: validationMessage,
      );
      return;
    }

    setState(() => _savingDataSource = true);
    try {
      final current = _selectedDataSource;
      if (current == null) {
        final record = await widget.controller.createDataSource(
          name: name,
          databaseType: _dataSourceDatabaseType,
          driverId: driver.id,
          jdbcUrl: _jdbcUrlController.text,
          username: _usernameController.text,
          password: _passwordController.text,
          schemaName: _schemaController.text,
          catalogName: _catalogController.text,
        );
        await _reload();
        if (mounted) {
          _selectDataSource(record.id);
        }
      } else {
        await widget.controller.updateDataSource(
          id: current.id,
          name: name,
          databaseType: _dataSourceDatabaseType,
          driverId: driver.id,
          jdbcUrl: _jdbcUrlController.text,
          username: _usernameController.text,
          password: _passwordController.text,
          schemaName: _schemaController.text,
          catalogName: _catalogController.text,
        );
        await _reload();
      }
      if (!mounted) {
        return;
      }
      if (showSuccess) {
        await _showBlockingMessageDialog(
          context,
          title: '保存成功',
          message: context.tr('数据源已保存。'),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showBlockingMessageDialog(
        context,
        title: '保存失败',
        message: error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _savingDataSource = false);
      }
    }
  }

  String? _validateDataSourceBeforeSave(JdbcDriverRecord driver) {
    if (_jdbcUrlController.text.trim().isEmpty) {
      return '请填写 JDBC URL。';
    }
    if (_usernameController.text.trim().isEmpty) {
      return '请填写用户名。';
    }
    if (_passwordController.text.isEmpty) {
      return '请填写密码。';
    }
    final jarPaths = driver.jarPaths
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (jarPaths.isEmpty) {
      return '当前驱动未配置 JDBC JAR 包。';
    }
    for (final jarPath in jarPaths) {
      if (!File(jarPath).existsSync()) {
        return '驱动 JAR 包不存在：$jarPath';
      }
    }
    return null;
  }

  Future<void> _deleteSelectedDataSource() async {
    final dataSource = _selectedDataSource;
    if (dataSource == null) {
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const LText('删除数据源'),
            content: LText('确认删除“${dataSource.name}”吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const LText('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const LText('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }
    await widget.controller.deleteDataSource(dataSource.id);
    await _reload();
  }

  Future<void> _testDraftDataSource() async {
    if (_testingDataSource) {
      return;
    }
    final driver = _selectedDriver;
    if (driver == null || _jdbcUrlController.text.trim().isEmpty) {
      await _showBlockingMessageDialog(
        context,
        title: '无法测试连接',
        message: context.tr('请先选择驱动并填写 JDBC URL。'),
      );
      return;
    }
    setState(() => _testingDataSource = true);
    try {
      final result = await widget.controller.testDataSourceDraftConnection(
        databaseType: _dataSourceDatabaseType,
        driverId: driver.id,
        jdbcUrl: _jdbcUrlController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        schemaName: _schemaController.text,
        catalogName: _catalogController.text,
      );
      if (!mounted) {
        return;
      }
      await _showBlockingMessageDialog(
        context,
        title: result.success ? '连接测试成功' : '连接测试失败',
        message: result.message,
      );
    } on JavaRuntimeResolutionException catch (error) {
      if (!mounted) {
        return;
      }
      await _showBlockingMessageDialog(
        context,
        title: '连接测试失败',
        message: error.message,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showBlockingMessageDialog(
        context,
        title: '连接测试失败',
        message: error.toString(),
      );
    } finally {
      if (mounted) {
        setState(() => _testingDataSource = false);
      }
    }
  }

  Future<void> _pickJdkHome() async {
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: context.tr('选择 JDK 8+ 目录'),
    );
    if (directory == null || directory.trim().isEmpty) {
      return;
    }
    final resolution = await widget.controller.validateAndSaveJdkHome(
      directory,
    );
    if (!mounted) {
      return;
    }
    setState(() => _jdkHome = resolution.jdkHome ?? directory);
  }

  Future<void> _pickOutputPath() async {
    final dataSource = _selectedDataSource;
    final suggestedName = dataSource == null
        ? 'reverse_output.pdm'
        : '${dataSource.name}.pdm';
    final output = await FilePicker.platform.saveFile(
      dialogTitle: context.tr('选择导出 PDM 路径'),
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: const ['pdm'],
    );
    if (output == null || output.trim().isEmpty) {
      return;
    }
    setState(() => _outputPathController.text = output);
  }

  Future<void> _runReverse() async {
    if (_runningReverse) {
      return;
    }
    final dataSource = _selectedDataSource;
    if (dataSource == null || _outputPathController.text.trim().isEmpty) {
      await _showBlockingMessageDialog(
        context,
        title: '无法开始生成',
        message: context.tr('请先选择一个数据源并填写输出路径。'),
      );
      return;
    }
    final effectiveSchema = _reverseSchemaController.text.trim();
    final effectiveCatalog = _reverseCatalogController.text.trim();
    setState(() {
      _runningReverse = true;
      _reverseLogs = [
        '准备开始逆向...',
        '数据源：${dataSource.name}',
        'Schema：${effectiveSchema.isEmpty ? '(未填写，执行时自动回退)' : effectiveSchema}',
        'Catalog：${effectiveCatalog.isEmpty ? '(未填写)' : effectiveCatalog}',
      ].map(_formatReverseLogLine).toList(growable: false);
    });
    try {
      await widget.controller.saveReverseTaskPreset(
        id: _presets.isEmpty ? null : _presets.first.id,
        name: '默认逆向配置',
        adapterType: ReverseAdapterType.builtin,
        dataSourceId: dataSource.id,
        driverId: dataSource.driverId,
        outputPath: _outputPathController.text,
        includeTableComments: _includeTableComments,
        includeColumnComments: _includeColumnComments,
        schemaName: _reverseSchemaController.text,
        catalogName: _reverseCatalogController.text,
        tableNames: _tableFilterController.text,
        tableNamePrefix: '',
        tableNameContains: '',
        customTableSql: '',
        customColumnSql: '',
        customPrimaryKeySql: '',
      );
      final result = await widget.controller.reverseDatabaseToPdm(
        dataSourceId: dataSource.id,
        outputPath: _outputPathController.text,
        includeTableComments: _includeTableComments,
        includeColumnComments: _includeColumnComments,
        schemaName: _reverseSchemaController.text,
        catalogName: _reverseCatalogController.text,
        tableFilter: _tableFilterController.text,
        onLog: (message) {
          if (!mounted) {
            return;
          }
          _appendReverseLogs([message]);
        },
      );
      if (!mounted) {
        return;
      }
      _appendReverseLogs(result.logs);
      await _showBlockingMessageDialog(
        context,
        title: '生成完成',
        message: context.tr(
          '已生成 ${result.tableCount} 张表，输出到 ${result.outputPath}',
        ),
      );
    } on JavaRuntimeResolutionException catch (error) {
      if (!mounted) {
        return;
      }
      _appendReverseLogs(['执行失败：${error.message}']);
      await _showBlockingMessageDialog(
        context,
        title: '生成失败',
        message: error.message,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _appendReverseLogs(['执行失败：$error']);
      await _showBlockingMessageDialog(
        context,
        title: '生成失败',
        message: error.toString(),
      );
    } finally {
      if (mounted) {
        setState(() => _runningReverse = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (AppTheme.componentsOf(context).isWorkbench) {
      return _buildPage(context);
    }
    final scheme = theme.colorScheme;
    final height = AppTheme.componentsOf(context).controlHeight;
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style?.copyWith(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? scheme.onSurface.withValues(alpha: 0.12)
                  : scheme.primaryContainer,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? scheme.onSurface.withValues(alpha: 0.38)
                  : scheme.onSurface,
            ),
            textStyle: WidgetStatePropertyAll(theme.textTheme.labelLarge),
            minimumSize: WidgetStatePropertyAll(Size(64, height)),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12),
            ),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            iconSize: const WidgetStatePropertyAll(16),
          ),
        ),
      ),
      child: Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _leftPaneWidth + 960;
        final maxAllowedLeftWidth = (maxWidth * 0.45)
            .clamp(_minLeftPaneWidth, _maxLeftPaneWidth)
            .toDouble();
        final leftPaneWidth = _leftPaneWidth
            .clamp(_minLeftPaneWidth, maxAllowedLeftWidth)
            .toDouble();
        if (leftPaneWidth != _leftPaneWidth) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _leftPaneWidth = leftPaneWidth;
            });
          });
        }

        return Stack(
          children: [
            Row(
              children: [
                SizedBox(
                  width: leftPaneWidth,
                  child: ChromeSurface(
                    border: const Border(),
                    child: Column(
                      children: [
                        _PageHeader(
                          title: _leftPaneTitle,
                          trailing: _buildLeftPaneAction(),
                        ),
                        Expanded(child: _buildLeftPaneList(context)),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _PanelCard(
                    border: const Border(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _DatabaseSecondaryButton.icon(
                                  onPressed: () => _runGuarded(widget.onBack),
                                  icon: const Icon(Icons.arrow_back),
                                  label: const LText('返回主页'),
                                ),
                                const SizedBox(width: 12),
                                SegmentedButton<DatabaseManagementSection>(
                                  showSelectedIcon: false,
                                  segments: DatabaseManagementSection.values
                                      .map(
                                        (item) => ButtonSegment(
                                          value: item,
                                          label: LText(item.label),
                                        ),
                                      )
                                      .toList(growable: false),
                                  selected: {_activeSection},
                                  onSelectionChanged: (selection) {
                                    selectSection(selection.first);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(child: _buildActiveEditor(context)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: leftPaneWidth - _dividerThickness / 2,
              top: 0,
              bottom: 0,
              width: _dividerThickness,
              child: _DragDivider(
                axis: Axis.horizontal,
                onDragDelta: (delta) {
                  setState(() {
                    _leftPaneWidth = (_leftPaneWidth + delta).clamp(
                      _minLeftPaneWidth,
                      maxAllowedLeftWidth,
                    );
                  });
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String get _leftPaneTitle {
    return _isDriverSection ? '驱动列表' : '数据源列表';
  }

  Widget? _buildLeftPaneAction() {
    if (_isDriverSection) {
      return IconButton(
        onPressed: () => _runGuarded(_newDriver),
        tooltip: context.tr('新增'),
        icon: const Icon(Icons.add),
      );
    }
    return IconButton(
      onPressed: () => _runGuarded(_newDataSource),
      tooltip: context.tr('新增'),
      icon: const Icon(Icons.add),
    );
  }

  Widget _buildLeftPaneList(BuildContext context) {
    if (_isDriverSection) {
      if (_drivers.isEmpty) {
        return const Center(child: LText('还没有驱动'));
      }
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _drivers.length,
        itemBuilder: (context, index) {
          final driver = _drivers[index];
          final selected = driver.id == _selectedDriverId;
          return _DatabaseListTile(
            selected: selected,
            title: driver.name,
            subtitle: driver.databaseType.label,
            onTap: () {
              if (_selectedDriverId != driver.id) {
                _runGuarded(() => _selectDriver(driver.id));
              }
            },
          );
        },
      );
    }
    if (_dataSources.isEmpty) {
      return const Center(child: LText('还没有数据源'));
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _dataSources.length,
      itemBuilder: (context, index) {
        final item = _dataSources[index];
        return _DatabaseListTile(
          selected: item.id == _selectedDataSourceId,
          title: item.name,
          subtitle: item.databaseType.label,
          onTap: () {
            if (_selectedDataSourceId != item.id) {
              _runGuarded(() => _selectDataSource(item.id));
            }
          },
        );
      },
    );
  }

  bool get _isDriverSection =>
      _activeSection == DatabaseManagementSection.drivers;

  Widget _buildActiveEditor(BuildContext context) {
    switch (_activeSection) {
      case DatabaseManagementSection.drivers:
        return _buildDriverEditor(context);
      case DatabaseManagementSection.dataSources:
        return _buildDataSourceEditor(context);
      case DatabaseManagementSection.reverse:
        return _buildReverseEditor(context);
    }
  }

  Widget _buildDriverEditor(BuildContext context) {
    final selectedDriver = _selectedDriver;
    final isBuiltIn = selectedDriver?.isBuiltInTemplate == true;
    return _SectionCard(
      title: '驱动配置',
      actions: [
        _DatabaseSecondaryButton(
          onPressed: () => _runGuarded(_newDriver),
          child: const LText('新增'),
        ),
        _DatabaseSecondaryButton(
          onPressed: selectedDriver == null
              ? null
              : () => _runGuarded(_duplicateDriver),
          child: const LText('复制'),
        ),
        if (isBuiltIn)
          _DatabaseSecondaryButton(
            onPressed: _restoreBuiltInDriverDefaults,
            child: const LText('恢复默认值'),
          ),
        if (selectedDriver != null && !selectedDriver.isBuiltInTemplate)
          _DatabaseSecondaryButton(
            onPressed: _deleteSelectedDriver,
            child: const LText('删除'),
          ),
        FilledButton(
          onPressed: _savingDriver ? null : _saveDriver,
          child: LText(_savingDriver ? '保存中...' : '保存'),
        ),
      ],
      expandBody: true,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _FormFieldRow(
              label: '驱动名称',
              child: TextField(
                key: const ValueKey('database-driver-name'),
                controller: _driverNameController,
                readOnly: isBuiltIn,
                decoration: InputDecoration(hintText: context.tr('驱动名称')),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: '数据库类型',
              child: DropdownButtonFormField<JdbcDatabaseType>(
                borderRadius: AppTheme.menuRadiusOf(context),
                initialValue: _driverDatabaseType,
                items: JdbcDatabaseType.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: LText(item.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _driverDatabaseType = value;
                  });
                },
                decoration: InputDecoration(hintText: context.tr('数据库类型')),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: '驱动类名',
              child: TextField(
                key: const ValueKey('database-driver-class'),
                controller: _driverClassController,
                decoration: InputDecoration(),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: 'JDBC URL 模版',
              child: TextField(
                controller: _driverJdbcUrlTemplateController,
                decoration: InputDecoration(
                  hintText: context.tr('可选，保存后可在数据源管理中自动带出'),
                ),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: '驱动 JAR 包',
              alignTop: true,
              child: _JarSelectorRow(
                jarPaths: _driverJarPaths,
                onPressed: _pickDriverJars,
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: '占位符',
              alignTop: true,
              child: _SqlPlaceholderHintCard(
                schemaFallbackHint:
                    '执行时会优先使用逆向配置里的 Schema；为空时再回退到当前数据源的 Schema。',
                catalogFallbackHint:
                    '执行时会优先使用逆向配置里的 Catalog；为空时再回退到当前数据源的 Catalog。',
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: '表查询 SQL',
              alignTop: true,
              child: TextField(
                controller: _driverTableSqlController,
                minLines: 4,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: context.tr(
                    '至少返回：table_name, table_code, table_comment',
                  ),
                ),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: '字段查询 SQL',
              alignTop: true,
              child: TextField(
                controller: _driverColumnSqlController,
                minLines: 5,
                maxLines: 7,
                decoration: InputDecoration(
                  hintText: context.tr(
                    '至少返回：table_name, column_name, column_code, data_type, length, precision, nullable, default_value, column_comment, ordinal_position',
                  ),
                ),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: '字段注释 SQL',
              alignTop: true,
              child: TextField(
                controller: _driverColumnCommentSqlController,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: context.tr(
                    '可选返回：table_name, column_name, column_comment',
                  ),
                ),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: '主键查询 SQL',
              alignTop: true,
              child: TextField(
                controller: _driverPrimaryKeySqlController,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: context.tr('至少返回：table_name, column_name'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataSourceEditor(BuildContext context) {
    final selectedDriver = _selectedDriver;
    return _SectionCard(
      title: '数据源配置',
      actions: [
        _DatabaseSecondaryButton(
          onPressed: () => _runGuarded(_newDataSource),
          child: const LText('新增'),
        ),
        _DatabaseSecondaryButton(
          onPressed: _selectedDataSource == null
              ? null
              : () => _runGuarded(_duplicateDataSource),
          child: const LText('复制'),
        ),
        _DatabaseSecondaryButton(
          onPressed: (_savingDataSource || _testingDataSource)
              ? null
              : _testDraftDataSource,
          child: LText(_testingDataSource ? '测试中...' : '测试连接'),
        ),
        if (_selectedDataSource != null)
          _DatabaseSecondaryButton(
            onPressed: _deleteSelectedDataSource,
            child: const LText('删除'),
          ),
        FilledButton(
          onPressed: _savingDataSource ? null : _saveDataSource,
          child: LText(_savingDataSource ? '保存中...' : '保存'),
        ),
      ],
      expandBody: true,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _FormFieldRow(
              label: '数据源名称',
              child: TextField(
                key: const ValueKey('database-source-name'),
                controller: _dataSourceNameController,
                decoration: InputDecoration(),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: '驱动',
              child: DropdownButtonFormField<String>(
                borderRadius: AppTheme.menuRadiusOf(context),
                initialValue: _selectedDriverId,
                items: _drivers
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedDriverId = value;
                    _dataSourceDatabaseType =
                        _selectedDriver?.databaseType ??
                        _dataSourceDatabaseType;
                  });
                  _applyJdbcUrlTemplateForSelectedDriver();
                },
                decoration: InputDecoration(),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: '数据库类型',
              child: DropdownButtonFormField<JdbcDatabaseType>(
                borderRadius: AppTheme.menuRadiusOf(context),
                initialValue: _dataSourceDatabaseType,
                items: JdbcDatabaseType.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: LText(item.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  final matchingDrivers = _drivers
                      .where(
                        (item) =>
                            item.databaseType == value ||
                            item.databaseType == JdbcDatabaseType.custom,
                      )
                      .toList(growable: false);
                  setState(() {
                    _dataSourceDatabaseType = value;
                    _selectedDriverId = matchingDrivers.isEmpty
                        ? null
                        : matchingDrivers.first.id;
                  });
                  _applyJdbcUrlTemplateForSelectedDriver(force: true);
                },
                decoration: InputDecoration(),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: 'JDBC URL',
              child: TextField(
                controller: _jdbcUrlController,
                decoration: InputDecoration(),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            if (selectedDriver != null)
              _FormFieldRow(
                label: '当前驱动',
                child: Text(
                  '${selectedDriver.name} / ${selectedDriver.driverClass}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (selectedDriver != null) const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: '用户名',
              child: TextField(
                controller: _usernameController,
                decoration: InputDecoration(),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: '密码',
              child: TextField(
                controller: _passwordController,
                decoration: InputDecoration(),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: 'Schema',
              child: TextField(
                controller: _schemaController,
                decoration: InputDecoration(),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _FormFieldRow(
              label: 'Catalog',
              child: TextField(
                controller: _catalogController,
                decoration: InputDecoration(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReverseEditor(BuildContext context) {
    final dataSource = _selectedDataSource;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 720.0;
        final maxTopHeight = (availableHeight - _minReverseBottomPaneHeight)
            .clamp(0.0, availableHeight);
        final minTopHeight = _minReverseTopPaneHeight
            .clamp(0, maxTopHeight)
            .toDouble();
        final effectiveTopPaneRatio = maxTopHeight <= 0
            ? 0.0
            : _reverseTopPaneRatio.clamp(0.0, 1.0);
        final topHeight = (availableHeight * effectiveTopPaneRatio)
            .clamp(minTopHeight, maxTopHeight)
            .toDouble();

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: topHeight,
                  child: _SectionCard(
                    title: '逆向配置',
                    actions: [
                      _DatabaseToggleButton(
                        selected: _includeTableComments,
                        label: '包含表注释',
                        onSelected: (value) {
                          setState(() {
                            _includeTableComments = value;
                          });
                        },
                      ),
                      _DatabaseToggleButton(
                        selected: _includeColumnComments,
                        label: '包含字段注释',
                        onSelected: (value) {
                          setState(() {
                            _includeColumnComments = value;
                          });
                        },
                      ),
                      _DatabaseSecondaryButton.icon(
                        onPressed: _pickJdkHome,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const LText('选择 JDK'),
                      ),
                      FilledButton(
                        onPressed: _runningReverse ? null : _runReverse,
                        child: LText(_runningReverse ? '生成中...' : '开始生成'),
                      ),
                    ],
                    expandBody: true,
                    child: LayoutBuilder(
                      builder: (context, bodyConstraints) {
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: bodyConstraints.maxHeight,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _FormFieldRow(
                                  label: '当前数据源',
                                  child: Text(
                                    dataSource == null
                                        ? context.tr('请先在左侧选择一个数据源。')
                                        : dataSource.name,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _FormFieldRow(
                                  label: 'JDK',
                                  child: Text(
                                    _jdkHome == null || _jdkHome!.trim().isEmpty
                                        ? context.tr(
                                            '未配置，将优先尝试 JAVA_HOME / PATH',
                                          )
                                        : _jdkHome!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: _fieldSpacing),
                                _FormFieldRow(
                                  label: 'Schema',
                                  child: TextField(
                                    controller: _reverseSchemaController,
                                    decoration: InputDecoration(),
                                  ),
                                ),
                                const SizedBox(height: _fieldSpacing),
                                _FormFieldRow(
                                  label: 'Catalog',
                                  child: TextField(
                                    controller: _reverseCatalogController,
                                    decoration: InputDecoration(),
                                  ),
                                ),
                                const SizedBox(height: _fieldSpacing),
                                _FormFieldRow(
                                  label: '表名过滤',
                                  alignTop: true,
                                  child: TextField(
                                    controller: _tableFilterController,
                                    minLines: 2,
                                    maxLines: 3,
                                    decoration: InputDecoration(
                                      hintText: context.tr(
                                        '留空导出全部；多个表名用逗号分隔；单个表达式按正则匹配表名或表编码',
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: _fieldSpacing),
                                _FormFieldRow(
                                  label: '输出路径',
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _outputPathController,
                                          decoration: InputDecoration(),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      _DatabaseSecondaryButton.icon(
                                        onPressed: _pickOutputPath,
                                        icon: const Icon(
                                          Icons.save_alt_outlined,
                                        ),
                                        label: const LText('选择'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: _SectionCard(
                    title: '执行日志',
                    backgroundColor: AppTheme.menuStripFill(context),
                    actions: [
                      _DatabaseSecondaryButton(
                        onPressed: _clearReverseLogs,
                        child: const LText('清除日志'),
                      ),
                    ],
                    expandBody: true,
                    child: TextField(
                      controller: _reverseLogTextController,
                      scrollController: _reverseLogScrollController,
                      readOnly: true,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        hintText: context.tr('还没有执行日志。'),
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: topHeight - _dividerThickness / 2,
              left: 0,
              right: 0,
              height: _dividerThickness,
              child: _DragDivider(
                axis: Axis.vertical,
                onDragDelta: (delta) {
                  if (availableHeight <= 0) return;
                  final nextTopHeight = (topHeight + delta)
                      .clamp(minTopHeight, maxTopHeight)
                      .toDouble();
                  setState(() {
                    _reverseTopPaneRatio = (nextTopHeight / availableHeight)
                        .clamp(0.0, 1.0);
                  });
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DatabaseSecondaryButton extends StatelessWidget {
  const _DatabaseSecondaryButton({required this.onPressed, required this.child})
    : icon = null;

  const _DatabaseSecondaryButton.icon({
    required this.onPressed,
    required this.icon,
    required Widget label,
  }) : child = label;

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final neutral = AppTheme.componentsOf(context).isWorkbench;
    if (icon case final buttonIcon?) {
      return neutral
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: buttonIcon,
              label: child,
            )
          : FilledButton.icon(
              onPressed: onPressed,
              icon: buttonIcon,
              label: child,
            );
    }
    return neutral
        ? OutlinedButton(onPressed: onPressed, child: child)
        : FilledButton(onPressed: onPressed, child: child);
  }
}

class _DatabaseToggleButton extends StatelessWidget {
  const _DatabaseToggleButton({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      toggled: selected,
      child: FilledButton.icon(
        onPressed: () => onSelected(!selected),
        icon: Icon(selected ? Icons.check_box : Icons.check_box_outline_blank),
        label: LText(label),
        style: FilledButton.styleFrom(
          backgroundColor: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHigh,
          foregroundColor: scheme.onSurface,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}

class _DatabaseListTile extends StatelessWidget {
  const _DatabaseListTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Keep the ink above the opaque sidebar background.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: selected
            ? AppTheme.treeSelectionFill(context)
            : Colors.transparent,
        borderRadius: AppTheme.controlRadiusOf(context),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          minLeadingWidth: 0,
          selected: selected,
          selectedColor: AppTheme.treeSelectionForeground(context),
          selectedTileColor: Colors.transparent,
          hoverColor: AppTheme.treeNodeHoverFill(context),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            context.tr(subtitle),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _DragDivider extends StatelessWidget {
  const _DragDivider({required this.axis, required this.onDragDelta});

  final Axis axis;
  final ValueChanged<double> onDragDelta;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = axis == Axis.horizontal;
    final cursor = isHorizontal
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.resizeUpDown;

    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: isHorizontal
            ? (details) => onDragDelta(details.delta.dx)
            : null,
        onVerticalDragUpdate: isHorizontal
            ? null
            : (details) => onDragDelta(details.delta.dy),
        child: SizedBox(
          width: isHorizontal
              ? DatabaseManagementPageState._dividerThickness
              : null,
          height: isHorizontal
              ? null
              : DatabaseManagementPageState._dividerThickness,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _JarSelectorRow extends StatelessWidget {
  const _JarSelectorRow({required this.jarPaths, required this.onPressed});

  final List<String> jarPaths;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final hasJarSelection = jarPaths.isNotEmpty;
    final displayText = jarPaths.isEmpty
        ? context.tr('未选择 JAR 文件')
        : jarPaths.join(' ; ');
    final baseTextStyle = Theme.of(context).textTheme.bodySmall;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: AppTheme.controlRadiusOf(context),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText(
                  '驱动 JAR 包',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 2),
                SelectableText(
                  displayText,
                  maxLines: 2,
                  style: hasJarSelection
                      ? baseTextStyle
                      : baseTextStyle?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _DatabaseSecondaryButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.attach_file),
            label: const LText('选择'),
          ),
        ],
      ),
    );
  }
}

class _FormFieldRow extends StatelessWidget {
  const _FormFieldRow({
    required this.label,
    required this.child,
    this.alignTop = false,
  });

  final String label;
  final Widget child;
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: alignTop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: DatabaseManagementPageState._fieldLabelWidth,
          child: Padding(
            padding: EdgeInsets.only(top: alignTop ? 10 : 0),
            child: LText(label, style: Theme.of(context).textTheme.labelMedium),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    );
  }
}

class _SqlPlaceholderHintCard extends StatelessWidget {
  const _SqlPlaceholderHintCard({
    required this.schemaFallbackHint,
    required this.catalogFallbackHint,
  });

  final String schemaFallbackHint;
  final String catalogFallbackHint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: AppTheme.controlRadiusOf(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText('自定义 SQL 可用占位符', style: textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(
            context.tr('%SCHEMA%  Schema 名称。${context.tr(schemaFallbackHint)}'),
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          SelectableText(
            context.tr(
              '%CATALOG%  Catalog 名称。${context.tr(catalogFallbackHint)}',
            ),
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child, this.border});

  final Widget child;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        border: border ?? Border.all(color: AppTheme.outlineSoft(context)),
      ),
      child: child,
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.actions = const [],
    this.expandBody = false,
    this.backgroundColor,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool expandBody;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.surfaceOf(context),
      ),
      child: Padding(
        padding: const EdgeInsets.all(
          DatabaseManagementPageState._sectionPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: LText(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DatabaseManagementPageState._fieldSpacing),
            if (expandBody) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: LText(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          trailing ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}

Future<void> _showBlockingMessageDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: LText(title),
      content: SelectableText(context.tr(message)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const LText('知道了'),
        ),
      ],
    ),
  );
}
