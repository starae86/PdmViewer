import 'jdbc_models.dart';

class JdbcReverseRequest {
  const JdbcReverseRequest({
    required this.driver,
    required this.dataSource,
    required this.adapterType,
    required this.schemaName,
    required this.catalogName,
    required this.tableFilter,
    required this.tableSql,
    required this.columnSql,
    required this.columnCommentSql,
    required this.primaryKeySql,
  });

  final JdbcDriverRecord driver;
  final DataSourceRecord dataSource;
  final ReverseAdapterType adapterType;
  final String schemaName;
  final String catalogName;
  final String tableFilter;
  final String tableSql;
  final String columnSql;
  final String columnCommentSql;
  final String primaryKeySql;
}

class JdbcConnectionTestResult {
  const JdbcConnectionTestResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

class JdbcReverseExecutionResult {
  const JdbcReverseExecutionResult({
    required this.schema,
    required this.logs,
  });

  final ReverseSchemaModel schema;
  final List<String> logs;
}

enum JavaRuntimeProblem {
  notFound,
  versionTooLow,
  missingCompiler,
}

class JavaRuntimeResolution {
  const JavaRuntimeResolution({
    required this.javaExecutablePath,
    required this.javacExecutablePath,
    required this.versionText,
    required this.majorVersion,
    this.jdkHome,
  });

  final String javaExecutablePath;
  final String javacExecutablePath;
  final String versionText;
  final int majorVersion;
  final String? jdkHome;
}

class JavaRuntimeResolutionException implements Exception {
  const JavaRuntimeResolutionException(this.problem, this.message);

  final JavaRuntimeProblem problem;
  final String message;

  @override
  String toString() => message;
}
