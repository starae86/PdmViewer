import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../../domain/models/jdbc_models.dart';
import '../../domain/models/reverse_models.dart';
import 'java_runtime_resolver.dart';

class JdbcReverseService {
  JdbcReverseService({
    required Directory workspaceDirectory,
    required JavaRuntimeResolver javaRuntimeResolver,
  }) : _workspaceDirectory = workspaceDirectory,
       _javaRuntimeResolver = javaRuntimeResolver;

  final Directory _workspaceDirectory;
  final JavaRuntimeResolver _javaRuntimeResolver;
  String? _cachedHelperSource;

  Future<JdbcConnectionTestResult> testConnection({
    required JdbcDriverRecord driver,
    required DataSourceRecord dataSource,
    required String? preferredJdkHome,
    void Function(String message)? onLog,
  }) async {
    final request = <String, Object?>{
      'mode': 'testConnection',
      'databaseType': dataSource.databaseType.value,
      'dataSourceName': dataSource.name,
      'driverClass': driver.driverClass,
      'jdbcUrl': dataSource.jdbcUrl,
      'username': dataSource.username,
      'password': dataSource.password,
      'schemaName': dataSource.schemaName,
      'catalogName': dataSource.catalogName,
      'tableSql': '',
      'columnSql': '',
      'columnCommentSql': '',
      'primaryKeySql': '',
    };
    final response = await _invokeHelper(
      driver: driver,
      preferredJdkHome: preferredJdkHome,
      request: request,
      onLog: onLog,
    );
    if (response['success'] == true) {
      return const JdbcConnectionTestResult(success: true, message: '连接成功');
    }
    return JdbcConnectionTestResult(
      success: false,
      message: (response['errorMessage'] as String? ?? '连接失败').trim(),
    );
  }

  Future<JdbcReverseExecutionResult> reverse({
    required JdbcReverseRequest request,
    required String? preferredJdkHome,
    void Function(String message)? onLog,
  }) async {
    final response = await _invokeHelper(
      driver: request.driver,
      preferredJdkHome: preferredJdkHome,
      request: <String, Object?>{
        'mode': 'reverse',
        'databaseType': request.dataSource.databaseType.value,
        'dataSourceName': request.dataSource.name,
        'driverClass': request.driver.driverClass,
        'jdbcUrl': request.dataSource.jdbcUrl,
        'username': request.dataSource.username,
        'password': request.dataSource.password,
        'schemaName': request.schemaName,
        'catalogName': request.catalogName,
        'tableSql': request.tableSql,
        'columnSql': request.columnSql,
        'columnCommentSql': request.columnCommentSql,
        'primaryKeySql': request.primaryKeySql,
      },
      onLog: onLog,
    );
    if (response['success'] != true) {
      throw Exception((response['errorMessage'] as String?) ?? '逆向失败');
    }

    final payload = response['payload'] as Map<String, dynamic>;
    final tables = (payload['tables'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => _mapTable(item as Map<String, dynamic>))
        .toList(growable: false);

    final schema = ReverseSchemaModel(
      databaseType: JdbcDatabaseType.fromValue(
        payload['databaseType'] as String? ?? request.dataSource.databaseType.value,
      ),
      dataSourceName: payload['dataSourceName'] as String? ?? request.dataSource.name,
      schemaName: payload['schemaName'] as String? ?? request.schemaName,
      catalogName: payload['catalogName'] as String? ?? request.catalogName,
      tables: tables,
    );
    return JdbcReverseExecutionResult(
      schema: schema,
      logs: const [],
    );
  }

  BuiltInReverseSqlSet buildBuiltInSql({
    required JdbcDatabaseType databaseType,
    required String schemaName,
    required String catalogName,
    bool includeTableComments = true,
    bool includeColumnComments = true,
  }) {
    switch (databaseType) {
      case JdbcDatabaseType.mysql:
      case JdbcDatabaseType.obMySql:
        return _buildMySqlSql(
          schemaName: schemaName,
          catalogName: catalogName,
        );
      case JdbcDatabaseType.oracle:
      case JdbcDatabaseType.obOracle:
      case JdbcDatabaseType.dameng:
        return _buildOracleSql(
          schemaName: schemaName,
          includeTableComments: includeTableComments,
          includeColumnComments: includeColumnComments,
        );
      case JdbcDatabaseType.postgresql:
        return _buildPostgreSqlSql(
          schemaName: schemaName,
        );
      case JdbcDatabaseType.custom:
        return const BuiltInReverseSqlSet(
          tableSql: '',
          columnSql: '',
          columnCommentSql: '',
          primaryKeySql: '',
        );
    }
  }

  Future<Map<String, dynamic>> _invokeHelper({
    required JdbcDriverRecord driver,
    required String? preferredJdkHome,
    required Map<String, Object?> request,
    void Function(String message)? onLog,
  }) async {
    onLog?.call('开始解析 Java 运行时...');
    final java = await _javaRuntimeResolver.resolve(preferredJdkHome: preferredJdkHome);
    onLog?.call('Java 运行时：${java.javaExecutablePath}');
    final runtimeDir = Directory(path.join(_workspaceDirectory.path, 'JdbcReverseRuntime'));
    if (!runtimeDir.existsSync()) {
      runtimeDir.createSync(recursive: true);
    }
    final compileDir = Directory(path.join(runtimeDir.path, 'classes'));
    if (!compileDir.existsSync()) {
      compileDir.createSync(recursive: true);
    }

    final sourceFile = File(path.join(runtimeDir.path, 'ReverseJdbcTool.java'));
    final mainClassFile = File(path.join(compileDir.path, 'ReverseJdbcTool.class'));
    final helperSource = await _loadHelperSource();
    final needsCompile =
        !sourceFile.existsSync() ||
        sourceFile.readAsStringSync() != helperSource ||
        !mainClassFile.existsSync();
    if (needsCompile) {
      onLog?.call('开始编译 JDBC helper...');
      sourceFile.writeAsStringSync(helperSource);
      if (compileDir.existsSync()) {
        for (final entity in compileDir.listSync()) {
          entity.deleteSync(recursive: true);
        }
      }
      final compileResult = await Process.run(
        java.javacExecutablePath,
        ['-encoding', 'UTF-8', '-d', compileDir.path, sourceFile.path],
      );
      if (compileResult.exitCode != 0) {
        throw Exception('JDBC helper 编译失败：${compileResult.stderr}\n${compileResult.stdout}');
      }
      if (!mainClassFile.existsSync()) {
        throw Exception('JDBC helper 编译后未找到主类产物：${mainClassFile.path}');
      }
      onLog?.call('JDBC helper 编译完成。');
    } else {
      onLog?.call('复用已编译的 JDBC helper。');
    }

    final requestFile = File(
      path.join(runtimeDir.path, 'request_${DateTime.now().microsecondsSinceEpoch}.json'),
    );
    final outputFile = File(
      path.join(runtimeDir.path, 'output_${DateTime.now().microsecondsSinceEpoch}.json'),
    );
    requestFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(request),
      flush: true,
    );

    final classpathEntries = <String>[
      compileDir.path,
      ...driver.jarPaths.where((item) => item.trim().isNotEmpty),
    ];
    final separator = Platform.isWindows ? ';' : ':';
    onLog?.call('开始启动 JDBC helper...');
    final process = await Process.start(
      java.javaExecutablePath,
      [
        '-cp',
        classpathEntries.join(separator),
        'ReverseJdbcTool',
        requestFile.path,
        outputFile.path,
      ],
      workingDirectory: runtimeDir.path,
    );
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = _pipeProcessOutput(
      process.stdout,
      stdoutBuffer,
      onLine: onLog,
    );
    final stderrDone = _pipeProcessOutput(
      process.stderr,
      stderrBuffer,
      onLine: (line) => onLog?.call('stderr: $line'),
    );
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);

    if (!outputFile.existsSync()) {
      throw Exception('JDBC helper 未生成输出：${stderrBuffer.toString()}\n${stdoutBuffer.toString()}');
    }

    if (exitCode != 0) {
      onLog?.call('JDBC helper 以非零状态退出：$exitCode');
    }

    final response = jsonDecode(outputFile.readAsStringSync()) as Map<String, dynamic>;
    requestFile.deleteSync();
    outputFile.deleteSync();
    return response;
  }

  Future<void> _pipeProcessOutput(
    Stream<List<int>> stream,
    StringBuffer buffer, {
    void Function(String line)? onLine,
  }) async {
    final lines = systemEncoding.decoder.bind(stream).transform(const LineSplitter());
    await for (final line in lines) {
      buffer.writeln(line);
      if (line.trim().isNotEmpty) {
        onLine?.call(line);
      }
    }
  }

  ReverseTableModel _mapTable(Map<String, dynamic> json) {
    final columns = (json['columns'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => _mapColumn(item as Map<String, dynamic>))
        .toList(growable: false);
    return ReverseTableModel(
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      comment: json['comment'] as String? ?? '',
      schemaName: json['schemaName'] as String? ?? '',
      rawIdentifier: json['rawIdentifier'] as String? ?? '',
      columns: columns,
    );
  }

  ReverseColumnModel _mapColumn(Map<String, dynamic> json) {
    return ReverseColumnModel(
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      dataType: json['dataType'] as String? ?? '',
      length: '${json['length'] ?? ''}',
      precision: '${json['precision'] ?? ''}',
      nullable: json['nullable'] == true,
      defaultValue: json['defaultValue'] as String? ?? '',
      isPrimaryKey: json['isPrimaryKey'] == true,
      comment: json['comment'] as String? ?? '',
      ordinalPosition: json['ordinalPosition'] is int
          ? json['ordinalPosition'] as int
          : int.tryParse('${json['ordinalPosition'] ?? ''}') ?? 0,
    );
  }

  BuiltInReverseSqlSet _buildMySqlSql({
    required String schemaName,
    required String catalogName,
    bool includeColumnComments = true,
  }) {
    final schemaFilter = _buildInlinedFilters(
      baseSql: '''
SELECT TABLE_NAME AS table_name,
       TABLE_NAME AS table_code,
       COALESCE(TABLE_COMMENT, '') AS table_comment
FROM information_schema.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
  AND TABLE_SCHEMA = '${_escapeSqlLiteral(schemaName.isNotEmpty ? schemaName : catalogName)}'
''',
      orderBy: ' ORDER BY TABLE_NAME',
    );
    final columnSql = _buildInlinedFilters(
      baseSql: '''
SELECT TABLE_NAME AS table_name,
       COLUMN_NAME AS column_name,
       COLUMN_NAME AS column_code,
       DATA_TYPE AS data_type,
       COALESCE(CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, 0) AS length,
       COALESCE(NUMERIC_SCALE, 0) AS precision,
       IS_NULLABLE AS nullable,
       COALESCE(COLUMN_DEFAULT, '') AS default_value,
       '' AS column_comment,
       ORDINAL_POSITION AS ordinal_position
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = '${_escapeSqlLiteral(schemaName.isNotEmpty ? schemaName : catalogName)}'
''',
      orderBy: ' ORDER BY TABLE_NAME, ORDINAL_POSITION',
    );
    final columnCommentSql = includeColumnComments
        ? _buildInlinedFilters(
            baseSql: '''
SELECT TABLE_NAME AS table_name,
       COLUMN_NAME AS column_name,
       COALESCE(COLUMN_COMMENT, '') AS column_comment
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = '${_escapeSqlLiteral(schemaName.isNotEmpty ? schemaName : catalogName)}'
''',
            orderBy: ' ORDER BY TABLE_NAME, ORDINAL_POSITION',
          )
        : '';
    final pkSql = _buildInlinedFilters(
      baseSql: '''
SELECT k.TABLE_NAME AS table_name,
       k.COLUMN_NAME AS column_name
FROM information_schema.TABLE_CONSTRAINTS t
JOIN information_schema.KEY_COLUMN_USAGE k
  ON k.CONSTRAINT_NAME = t.CONSTRAINT_NAME
 AND k.TABLE_SCHEMA = t.TABLE_SCHEMA
 AND k.TABLE_NAME = t.TABLE_NAME
WHERE t.CONSTRAINT_TYPE = 'PRIMARY KEY'
  AND t.TABLE_SCHEMA = '${_escapeSqlLiteral(schemaName.isNotEmpty ? schemaName : catalogName)}'
''',
      orderBy: ' ORDER BY k.TABLE_NAME, k.ORDINAL_POSITION',
    );
    return BuiltInReverseSqlSet(
      tableSql: schemaFilter,
      columnSql: columnSql,
      columnCommentSql: columnCommentSql,
      primaryKeySql: pkSql,
    );
  }

  BuiltInReverseSqlSet _buildPostgreSqlSql({
    required String schemaName,
    bool includeColumnComments = true,
  }) {
    final resolvedSchema = schemaName.isEmpty ? 'public' : schemaName;
    final tableSql = _buildInlinedFilters(
      baseSql: '''
SELECT t.table_name AS table_name,
       t.table_name AS table_code,
       COALESCE(obj_description((quote_ident(t.table_schema) || '.' || quote_ident(t.table_name))::regclass), '') AS table_comment
FROM information_schema.tables t
WHERE t.table_type = 'BASE TABLE'
  AND t.table_schema = '${_escapeSqlLiteral(resolvedSchema)}'
''',
      orderBy: ' ORDER BY t.table_name',
    );
    final columnSql = _buildInlinedFilters(
      baseSql: '''
SELECT c.table_name AS table_name,
       c.column_name AS column_name,
       c.column_name AS column_code,
       c.data_type AS data_type,
       COALESCE(c.character_maximum_length, c.numeric_precision, 0) AS length,
       COALESCE(c.numeric_scale, 0) AS precision,
       c.is_nullable AS nullable,
       COALESCE(c.column_default, '') AS default_value,
       '' AS column_comment,
       c.ordinal_position AS ordinal_position
FROM information_schema.columns c
JOIN pg_catalog.pg_class cls ON cls.relname = c.table_name
JOIN pg_catalog.pg_namespace ns ON ns.oid = cls.relnamespace AND ns.nspname = c.table_schema
WHERE c.table_schema = '${_escapeSqlLiteral(resolvedSchema)}'
''',
      orderBy: ' ORDER BY c.table_name, c.ordinal_position',
    );
    final columnCommentSql = includeColumnComments
        ? _buildInlinedFilters(
            baseSql: '''
SELECT c.table_name AS table_name,
       c.column_name AS column_name,
       COALESCE(pg_catalog.col_description(cls.oid, c.ordinal_position), '') AS column_comment
FROM information_schema.columns c
JOIN pg_catalog.pg_class cls ON cls.relname = c.table_name
JOIN pg_catalog.pg_namespace ns ON ns.oid = cls.relnamespace AND ns.nspname = c.table_schema
WHERE c.table_schema = '${_escapeSqlLiteral(resolvedSchema)}'
''',
            orderBy: ' ORDER BY c.table_name, c.ordinal_position',
          )
        : '';
    final pkSql = _buildInlinedFilters(
      baseSql: '''
SELECT tc.table_name AS table_name,
       kcu.column_name AS column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON kcu.constraint_name = tc.constraint_name
 AND kcu.table_schema = tc.table_schema
 AND kcu.table_name = tc.table_name
WHERE tc.constraint_type = 'PRIMARY KEY'
  AND tc.table_schema = '${_escapeSqlLiteral(resolvedSchema)}'
''',
      orderBy: ' ORDER BY tc.table_name, kcu.ordinal_position',
    );
    return BuiltInReverseSqlSet(
      tableSql: tableSql,
      columnSql: columnSql,
      columnCommentSql: columnCommentSql,
      primaryKeySql: pkSql,
    );
  }

  BuiltInReverseSqlSet _buildOracleSql({
    required String schemaName,
    required bool includeTableComments,
    required bool includeColumnComments,
  }) {
    final owner = schemaName.trim().toUpperCase();
    final tableSql = _buildInlinedFilters(
      baseSql: '''
SELECT t.TABLE_NAME AS table_name,
       t.TABLE_NAME AS table_code,
       ${includeTableComments ? "COALESCE(c.COMMENTS, '')" : "''"} AS table_comment
FROM ALL_TABLES t
${includeTableComments ? '''
LEFT JOIN ALL_TAB_COMMENTS c
  ON c.OWNER = t.OWNER
 AND c.TABLE_NAME = t.TABLE_NAME
''' : ''}
WHERE t.OWNER = '${_escapeSqlLiteral(owner)}'
''',
      orderBy: ' ORDER BY t.TABLE_NAME',
    );
    final columnSql = _buildInlinedFilters(
      baseSql: '''
SELECT c.TABLE_NAME AS table_name,
       c.COLUMN_NAME AS column_name,
       c.COLUMN_NAME AS column_code,
       c.DATA_TYPE AS data_type,
       COALESCE(c.DATA_LENGTH, c.DATA_PRECISION, 0) AS length,
       COALESCE(c.DATA_SCALE, 0) AS precision,
       CASE WHEN c.NULLABLE = 'Y' THEN 'YES' ELSE 'NO' END AS nullable,
       c.DATA_DEFAULT AS default_value,
       '' AS column_comment,
       c.COLUMN_ID AS ordinal_position
FROM ALL_TAB_COLUMNS c
WHERE c.OWNER = '${_escapeSqlLiteral(owner)}'
''',
      orderBy: ' ORDER BY c.TABLE_NAME, c.COLUMN_ID',
    );
    final columnCommentSql = includeColumnComments
        ? _buildInlinedFilters(
            baseSql: '''
SELECT cm.TABLE_NAME AS table_name,
       cm.COLUMN_NAME AS column_name,
       COALESCE(cm.COMMENTS, '') AS column_comment
FROM ALL_COL_COMMENTS cm
WHERE cm.OWNER = '${_escapeSqlLiteral(owner)}'
''',
            orderBy: ' ORDER BY cm.TABLE_NAME, cm.COLUMN_NAME',
          )
        : '';
    final pkSql = _buildInlinedFilters(
      baseSql: '''
SELECT acc.TABLE_NAME AS table_name,
       acc.COLUMN_NAME AS column_name
FROM ALL_CONSTRAINTS ac
JOIN ALL_CONS_COLUMNS acc
  ON acc.OWNER = ac.OWNER
 AND acc.CONSTRAINT_NAME = ac.CONSTRAINT_NAME
WHERE ac.CONSTRAINT_TYPE = 'P'
  AND ac.OWNER = '${_escapeSqlLiteral(owner)}'
''',
      orderBy: ' ORDER BY acc.TABLE_NAME, acc.POSITION',
    );
    return BuiltInReverseSqlSet(
      tableSql: tableSql,
      columnSql: columnSql,
      columnCommentSql: columnCommentSql,
      primaryKeySql: pkSql,
    );
  }

  String _buildInlinedFilters({
    required String baseSql,
    required String orderBy,
  }) {
    final buffer = StringBuffer(baseSql.trim());
    buffer.write(orderBy);
    return buffer.toString();
  }

  String _escapeSqlLiteral(String value) {
    return value.replaceAll("'", "''");
  }

  Future<String> _loadHelperSource() async {
    final cached = _cachedHelperSource;
    if (cached != null) {
      return cached;
    }
    final loaded = await rootBundle.loadString('tooling/jdbc/ReverseJdbcTool.java');
    _cachedHelperSource = loaded;
    return loaded;
  }
}

class BuiltInReverseSqlSet {
  const BuiltInReverseSqlSet({
    required this.tableSql,
    required this.columnSql,
    required this.columnCommentSql,
    required this.primaryKeySql,
  });

  final String tableSql;
  final String columnSql;
  final String columnCommentSql;
  final String primaryKeySql;
}
