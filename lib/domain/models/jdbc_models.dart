enum JdbcDatabaseType {
  mysql('mysql', 'MySQL'),
  obMySql('ob_mysql', 'OB MySQL'),
  oracle('oracle', 'Oracle'),
  obOracle('ob_oracle', 'OB Oracle'),
  postgresql('postgresql', 'PostgreSQL'),
  dameng('dameng', '达梦'),
  custom('custom', '自定义');

  const JdbcDatabaseType(this.value, this.label);

  final String value;
  final String label;

  static JdbcDatabaseType fromValue(String value) {
    for (final item in values) {
      if (item.value == value) {
        return item;
      }
    }
    return JdbcDatabaseType.custom;
  }
}

enum ReverseAdapterType {
  builtin('builtin', '内置适配器'),
  customSql('customSql', '自定义 SQL');

  const ReverseAdapterType(this.value, this.label);

  final String value;
  final String label;

  static ReverseAdapterType fromValue(String value) {
    for (final item in values) {
      if (item.value == value) {
        return item;
      }
    }
    return ReverseAdapterType.builtin;
  }
}

enum ConnectionHealthStatus {
  unknown('unknown', '未知'),
  success('success', '成功'),
  failed('failed', '失败');

  const ConnectionHealthStatus(this.value, this.label);

  final String value;
  final String label;

  static ConnectionHealthStatus fromValue(String value) {
    for (final item in values) {
      if (item.value == value) {
        return item;
      }
    }
    return ConnectionHealthStatus.unknown;
  }
}

class JdbcDriverRecord {
  const JdbcDriverRecord({
    required this.id,
    required this.name,
    required this.databaseType,
    required this.driverClass,
    required this.jdbcUrlTemplate,
    required this.jarPaths,
    required this.isBuiltInTemplate,
    required this.tableSql,
    required this.columnSql,
    required this.columnCommentSql,
    required this.primaryKeySql,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final JdbcDatabaseType databaseType;
  final String driverClass;
  final String jdbcUrlTemplate;
  final List<String> jarPaths;
  final bool isBuiltInTemplate;
  final String tableSql;
  final String columnSql;
  final String columnCommentSql;
  final String primaryKeySql;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get jarPathsText => jarPaths.join('\n');
  bool get hasCustomSql =>
      tableSql.trim().isNotEmpty &&
      columnSql.trim().isNotEmpty &&
      primaryKeySql.trim().isNotEmpty;
}

class DataSourceRecord {
  const DataSourceRecord({
    required this.id,
    required this.name,
    required this.databaseType,
    required this.driverId,
    required this.jdbcUrl,
    required this.username,
    required this.password,
    required this.schemaName,
    required this.catalogName,
    required this.lastConnectionStatus,
    required this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final JdbcDatabaseType databaseType;
  final String driverId;
  final String jdbcUrl;
  final String username;
  final String password;
  final String schemaName;
  final String catalogName;
  final ConnectionHealthStatus lastConnectionStatus;
  final String lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ReverseTaskPreset {
  const ReverseTaskPreset({
    required this.id,
    required this.name,
    required this.adapterType,
    required this.dataSourceId,
    required this.driverId,
    required this.outputPath,
    required this.includeTableComments,
    required this.includeColumnComments,
    required this.schemaName,
    required this.catalogName,
    required this.tableNames,
    required this.tableNamePrefix,
    required this.tableNameContains,
    required this.customTableSql,
    required this.customColumnSql,
    required this.customPrimaryKeySql,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final ReverseAdapterType adapterType;
  final String dataSourceId;
  final String driverId;
  final String outputPath;
  final bool includeTableComments;
  final bool includeColumnComments;
  final String schemaName;
  final String catalogName;
  final String tableNames;
  final String tableNamePrefix;
  final String tableNameContains;
  final String customTableSql;
  final String customColumnSql;
  final String customPrimaryKeySql;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class AppRuntimeSetting {
  const AppRuntimeSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  final String key;
  final String value;
  final DateTime updatedAt;
}

class ReverseColumnModel {
  const ReverseColumnModel({
    required this.name,
    required this.code,
    required this.dataType,
    required this.length,
    required this.precision,
    required this.nullable,
    required this.defaultValue,
    required this.isPrimaryKey,
    required this.comment,
    required this.ordinalPosition,
  });

  final String name;
  final String code;
  final String dataType;
  final String length;
  final String precision;
  final bool nullable;
  final String defaultValue;
  final bool isPrimaryKey;
  final String comment;
  final int ordinalPosition;
}

class ReverseTableModel {
  const ReverseTableModel({
    required this.name,
    required this.code,
    required this.comment,
    required this.schemaName,
    required this.rawIdentifier,
    required this.columns,
  });

  final String name;
  final String code;
  final String comment;
  final String schemaName;
  final String rawIdentifier;
  final List<ReverseColumnModel> columns;
}

class ReverseSchemaModel {
  const ReverseSchemaModel({
    required this.databaseType,
    required this.dataSourceName,
    required this.schemaName,
    required this.catalogName,
    required this.tables,
  });

  final JdbcDatabaseType databaseType;
  final String dataSourceName;
  final String schemaName;
  final String catalogName;
  final List<ReverseTableModel> tables;
}

class JdbcBuiltInDriverTemplate {
  const JdbcBuiltInDriverTemplate({
    required this.databaseType,
    required this.name,
    required this.driverClass,
    required this.jdbcUrlTemplate,
    required this.notes,
  });

  final JdbcDatabaseType databaseType;
  final String name;
  final String driverClass;
  final String jdbcUrlTemplate;
  final String notes;
}

const List<JdbcBuiltInDriverTemplate> kJdbcBuiltInDriverTemplates = [
  JdbcBuiltInDriverTemplate(
    databaseType: JdbcDatabaseType.mysql,
    name: 'MySQL',
    driverClass: 'com.mysql.cj.jdbc.Driver',
    jdbcUrlTemplate:
        'jdbc:mysql://{host}:{port}/{dbname}?useUnicode=true&characterEncoding=utf8&useSSL=false',
    notes: '常见驱动：mysql-connector-j',
  ),
  JdbcBuiltInDriverTemplate(
    databaseType: JdbcDatabaseType.obMySql,
    name: 'OceanBase_MySQL',
    driverClass: 'com.mysql.jdbc.Driver',
    jdbcUrlTemplate:
        'jdbc:mysql://{host}:{port}/{dbname}?useSSL=false',
    notes: 'OceanBase MySQL 模式，用户通常为 用户名@租户名#集群名',
  ),
  JdbcBuiltInDriverTemplate(
    databaseType: JdbcDatabaseType.oracle,
    name: 'Oracle',
    driverClass: 'oracle.jdbc.driver.OracleDriver',
    jdbcUrlTemplate: 'jdbc:oracle:thin:@{host}:{port}/{dbname}',
    notes: '常见驱动：ojdbc8 / ojdbc11',
  ),
  JdbcBuiltInDriverTemplate(
    databaseType: JdbcDatabaseType.obOracle,
    name: 'OceanBase_Oracle',
    driverClass: 'com.alipay.oceanbase.jdbc.Driver',
    jdbcUrlTemplate:
        'jdbc:oceanbase:oracle://{host}:{port}/{dbname}?useUnicode=true&characterEncoding=UTF-8&useCursorFetch=true&defaultFetchSize=1000&prepStmtCacheSize=25',
    notes: 'OceanBase Oracle 模式，用户通常为 用户名@租户名#集群名',
  ),
  JdbcBuiltInDriverTemplate(
    databaseType: JdbcDatabaseType.postgresql,
    name: 'PostgreSQL',
    driverClass: 'org.postgresql.Driver',
    jdbcUrlTemplate: 'jdbc:postgresql://{host}:{port}/{dbname}',
    notes: '常见驱动：postgresql',
  ),
  JdbcBuiltInDriverTemplate(
    databaseType: JdbcDatabaseType.dameng,
    name: 'DaMeng',
    driverClass: 'dm.jdbc.driver.DmDriver',
    jdbcUrlTemplate: 'jdbc:dm://{host}:{port}/{dbname}',
    notes: '常见驱动：DmJdbcDriver8 / DmJdbcDriver11',
  ),
];
