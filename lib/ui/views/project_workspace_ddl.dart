import '../../domain/models/pdm_models.dart';

enum DdlDialect { oracle, mysql, postgresql }

String buildTableDdl(
  TableDetail detail,
  DdlDialect dialect, {
  bool includeComments = true,
}) {
  final tableName = quotedIdentifier(
    detail.tableCode.trim().isNotEmpty ? detail.tableCode.trim() : detail.tableName.trim(),
    dialect,
  );
  final definitions = <String>[];
  final primaryKeys = <String>[];

  for (final column in detail.columns) {
    final rawCode = column.code.trim().isNotEmpty ? column.code.trim() : column.name.trim();
    final columnName = quotedIdentifier(rawCode, dialect);
    final type = mapColumnType(column, dialect);
    final nullable = column.nullable ? '' : ' NOT NULL';
    final defaultValue = buildDefaultClause(
      column.defaultValue.trim(),
      dialect,
      column: column,
    );
    final commentClause = includeComments &&
            dialect == DdlDialect.mysql &&
            column.comment.trim().isNotEmpty
        ? ' COMMENT ${sqlStringLiteral(column.comment.trim())}'
        : '';
    definitions.add('  $columnName $type$defaultValue$nullable$commentClause');
    if (column.isPrimaryKey) {
      primaryKeys.add(columnName);
    }
  }

  if (primaryKeys.isNotEmpty) {
    definitions.add('  PRIMARY KEY (${primaryKeys.join(', ')})');
  }

  final lines = <String>[
    'CREATE TABLE $tableName (',
    definitions.join(',\n'),
    ');',
  ];

  final tableComment = includeComments ? detail.comment.trim() : '';
  if (tableComment.isNotEmpty) {
    switch (dialect) {
      case DdlDialect.mysql:
        lines[0] = 'CREATE TABLE $tableName (';
        lines[lines.length - 1] =
            ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin COMMENT=${sqlStringLiteral(tableComment)};';
      case DdlDialect.oracle:
      case DdlDialect.postgresql:
        lines.add(
          'COMMENT ON TABLE $tableName IS ${sqlStringLiteral(tableComment)};',
        );
    }
  } else if (dialect == DdlDialect.mysql) {
    lines[lines.length - 1] =
        ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;';
  }

  for (final column in detail.columns) {
    if (!includeComments) {
      continue;
    }
    if (dialect == DdlDialect.mysql) {
      continue;
    }
    final rawCode = column.code.trim().isNotEmpty ? column.code.trim() : column.name.trim();
    final comment = column.comment.trim().isNotEmpty ? column.comment.trim() : column.name.trim();
    if (comment.isEmpty) {
      continue;
    }
    lines.add(
      'COMMENT ON COLUMN $tableName.${quotedIdentifier(rawCode, dialect)} IS ${sqlStringLiteral(comment)};',
    );
  }

  return lines.join('\n');
}

String buildTableCommentSql(TableDetail detail, DdlDialect dialect) {
  final tableName = quotedIdentifier(
    detail.tableCode.trim().isNotEmpty
        ? detail.tableCode.trim()
        : detail.tableName.trim(),
    dialect,
  );
  final lines = <String>[];
  final tableComment = detail.comment.trim();

  if (tableComment.isNotEmpty) {
    switch (dialect) {
      case DdlDialect.mysql:
        lines.add(
          'ALTER TABLE $tableName COMMENT=${sqlStringLiteral(tableComment)};',
        );
      case DdlDialect.oracle:
      case DdlDialect.postgresql:
        lines.add(
          'COMMENT ON TABLE $tableName IS ${sqlStringLiteral(tableComment)};',
        );
    }
  }

  for (final column in detail.columns) {
    final rawCode = column.code.trim().isNotEmpty
        ? column.code.trim()
        : column.name.trim();
    final comment = column.comment.trim().isNotEmpty
        ? column.comment.trim()
        : column.name.trim();
    if (rawCode.isEmpty || comment.isEmpty) {
      continue;
    }
    switch (dialect) {
      case DdlDialect.mysql:
        lines.add(
          '-- MySQL 字段注释需要结合字段类型执行 ALTER TABLE MODIFY COLUMN $rawCode COMMENT ${sqlStringLiteral(comment)};',
        );
      case DdlDialect.oracle:
      case DdlDialect.postgresql:
        lines.add(
          'COMMENT ON COLUMN $tableName.${quotedIdentifier(rawCode, dialect)} IS ${sqlStringLiteral(comment)};',
        );
    }
  }

  return lines.join('\n');
}

String buildTableDml(TableDetail detail, DdlDialect dialect) {
  final tableName = quotedIdentifier(
    detail.tableCode.trim().isNotEmpty ? detail.tableCode.trim() : detail.tableName.trim(),
    dialect,
  );
  final columns = detail.columns;
  final allColumnNames = columns.map((column) {
    final rawCode = column.code.trim().isNotEmpty ? column.code.trim() : column.name.trim();
    return quotedIdentifier(rawCode, dialect);
  }).toList(growable: false);
  final primaryKeyColumns = columns.where((column) => column.isPrimaryKey).toList(growable: false);
  final nonPrimaryKeyColumns = columns.where((column) => !column.isPrimaryKey).toList(growable: false);

  final sections = <String>[
    '-- SELECT',
    _buildSelectTemplate(tableName, primaryKeyColumns, columns, dialect),
    '',
    '-- INSERT',
    _buildInsertTemplate(tableName, columns, allColumnNames),
    '',
    '-- UPDATE',
    _buildUpdateTemplate(tableName, primaryKeyColumns, nonPrimaryKeyColumns, columns, dialect),
    '',
    '-- DELETE',
    _buildDeleteTemplate(tableName, primaryKeyColumns, columns, dialect),
  ];

  return sections.join('\n');
}

String _buildSelectTemplate(
  String tableName,
  List<TableDetailColumn> primaryKeyColumns,
  List<TableDetailColumn> allColumns,
  DdlDialect dialect,
) {
  final selectedColumns = allColumns.map((column) {
    final rawCode = column.code.trim().isNotEmpty ? column.code.trim() : column.name.trim();
    return quotedIdentifier(rawCode, dialect);
  }).join(', ');
  return 'SELECT $selectedColumns\nFROM $tableName\n${_buildWhereClause(primaryKeyColumns, allColumns, dialect)};';
}

String _buildInsertTemplate(
  String tableName,
  List<TableDetailColumn> columns,
  List<String> allColumnNames,
) {
  final insertColumns = allColumnNames.join(', ');
  final values = columns.map((column) {
    final code = column.code.trim().isNotEmpty ? column.code.trim() : column.name.trim();
    return ':$code';
  }).join(', ');
  return 'INSERT INTO $tableName ($insertColumns)\nVALUES ($values);';
}

String _buildUpdateTemplate(
  String tableName,
  List<TableDetailColumn> primaryKeyColumns,
  List<TableDetailColumn> nonPrimaryKeyColumns,
  List<TableDetailColumn> allColumns,
  DdlDialect dialect,
) {
  final updateColumns = nonPrimaryKeyColumns.isNotEmpty
      ? nonPrimaryKeyColumns
      : allColumns;
  final setClause = updateColumns.map((column) {
    final rawCode = column.code.trim().isNotEmpty ? column.code.trim() : column.name.trim();
    final name = quotedIdentifier(rawCode, dialect);
    return '  $name = :$rawCode';
  }).join(',\n');
  return 'UPDATE $tableName\nSET\n$setClause\n${_buildWhereClause(primaryKeyColumns, allColumns, dialect)};';
}

String _buildDeleteTemplate(
  String tableName,
  List<TableDetailColumn> primaryKeyColumns,
  List<TableDetailColumn> allColumns,
  DdlDialect dialect,
) {
  return 'DELETE FROM $tableName ${_buildWhereClause(primaryKeyColumns, allColumns, dialect)};';
}

String _buildWhereClause(
  List<TableDetailColumn> primaryKeyColumns,
  List<TableDetailColumn> allColumns,
  DdlDialect dialect,
) {
  final whereColumns = primaryKeyColumns.isNotEmpty
      ? primaryKeyColumns
      : <TableDetailColumn>[];
  if (whereColumns.isEmpty) {
    final fallbackColumn = allColumns.isEmpty ? null : allColumns.first;
    final fallbackCode = fallbackColumn == null
        ? '<请补充条件>'
        : (fallbackColumn.code.trim().isNotEmpty
              ? fallbackColumn.code.trim()
              : fallbackColumn.name.trim());
    return 'WHERE /* 请补充条件 */ ${fallbackCode.isEmpty ? '<请补充条件>' : '$fallbackCode = :$fallbackCode'}';
  }
  final conditions = whereColumns.map((column) {
    final rawCode = column.code.trim().isNotEmpty ? column.code.trim() : column.name.trim();
    return '${quotedIdentifier(rawCode, dialect)} = :$rawCode';
  }).join(' AND ');
  return 'WHERE $conditions';
}

String quotedIdentifier(String value, DdlDialect dialect) {
  final normalized = value.trim().isEmpty ? 'unnamed_table' : value.trim();
  return normalized;
}

String mapColumnType(TableDetailColumn column, DdlDialect dialect) {
  final rawType = column.dataType.trim();
  if (rawType.isEmpty) {
    return switch (dialect) {
      DdlDialect.oracle => 'VARCHAR2(255)',
      DdlDialect.mysql => 'VARCHAR(255)',
      DdlDialect.postgresql => 'VARCHAR(255)',
    };
  }

  final upper = rawType.toUpperCase();
  final base = upper.split('(').first.trim();
  final length = column.length.trim();
  final precision = column.precision.trim();

  bool isIn(List<String> values) => values.contains(base);
  if (base == 'XMLTYPE') {
    return switch (dialect) {
      DdlDialect.oracle => 'XMLTYPE',
      DdlDialect.mysql => 'LONGTEXT',
      DdlDialect.postgresql => 'XML',
    };
  }
  final integerSemantic = isIn(['INT', 'INTEGER', 'SMALLINT', 'BIGINT', 'TINYINT']) ||
      _isIntegerSemanticDecimal(base, precision);
  final useBigInt = _shouldUseBigInt(integerSemantic, length);

  if (isIn(['VARCHAR', 'VARCHAR2', 'CHAR', 'NCHAR', 'NVARCHAR', 'NVARCHAR2'])) {
    if (_shouldUseLargeText(base, length)) {
      return switch (dialect) {
        DdlDialect.oracle => 'CLOB',
        DdlDialect.mysql => 'LONGTEXT',
        DdlDialect.postgresql => 'TEXT',
      };
    }
    final resolvedLength = length.isNotEmpty ? length : '255';
    return switch (dialect) {
      DdlDialect.oracle => '${base == 'CHAR' || base == 'NCHAR' ? base : 'VARCHAR2'}($resolvedLength)',
      DdlDialect.mysql => '${base == 'CHAR' || base == 'NCHAR' ? 'CHAR' : 'VARCHAR'}($resolvedLength)',
      DdlDialect.postgresql => '${base == 'CHAR' || base == 'NCHAR' ? 'CHAR' : 'VARCHAR'}($resolvedLength)',
    };
  }

  if (isIn(['NUMBER', 'NUMERIC', 'DECIMAL'])) {
    if (useBigInt) {
      return switch (dialect) {
        DdlDialect.oracle => 'NUMBER(19)',
        DdlDialect.mysql => 'BIGINT',
        DdlDialect.postgresql => 'BIGINT',
      };
    }
    if (length.isNotEmpty && precision.isNotEmpty) {
      return switch (dialect) {
        DdlDialect.oracle => 'NUMBER($length,$precision)',
        DdlDialect.mysql => 'DECIMAL($length,$precision)',
        DdlDialect.postgresql => 'NUMERIC($length,$precision)',
      };
    }
    if (length.isNotEmpty) {
      return switch (dialect) {
        DdlDialect.oracle => 'NUMBER($length)',
        DdlDialect.mysql => 'DECIMAL($length)',
        DdlDialect.postgresql => 'NUMERIC($length)',
      };
    }
    return switch (dialect) {
      DdlDialect.oracle => 'NUMBER',
      DdlDialect.mysql => 'DECIMAL',
      DdlDialect.postgresql => 'NUMERIC',
    };
  }

  if (isIn(['INT', 'INTEGER', 'SMALLINT', 'BIGINT', 'TINYINT'])) {
    if (useBigInt) {
      return switch (dialect) {
        DdlDialect.oracle => 'NUMBER(19)',
        DdlDialect.mysql => 'BIGINT',
        DdlDialect.postgresql => 'BIGINT',
      };
    }
    return switch (dialect) {
      DdlDialect.oracle => base == 'BIGINT' ? 'NUMBER(19)' : 'NUMBER(10)',
      DdlDialect.mysql => base == 'INTEGER' ? 'INT' : base,
      DdlDialect.postgresql => base == 'TINYINT' ? 'SMALLINT' : base,
    };
  }

  if (isIn(['DATE', 'DATETIME', 'TIMESTAMP'])) {
    return switch (dialect) {
      DdlDialect.oracle => base == 'DATE' ? 'DATE' : 'TIMESTAMP',
      DdlDialect.mysql => base == 'DATE' ? 'DATE' : 'DATETIME',
      DdlDialect.postgresql => base == 'DATE' ? 'DATE' : 'TIMESTAMP',
    };
  }

  if (isIn(['CLOB', 'TEXT', 'LONGTEXT']) || _shouldUseLargeText(base, length)) {
    return switch (dialect) {
      DdlDialect.oracle => 'CLOB',
      DdlDialect.mysql => 'LONGTEXT',
      DdlDialect.postgresql => 'TEXT',
    };
  }

  if (isIn(['BLOB', 'RAW', 'BYTEA'])) {
    final useLargeBinary = _shouldUseLargeBinary(base, length);
    return switch (dialect) {
      DdlDialect.oracle => 'BLOB',
      DdlDialect.mysql => useLargeBinary ? 'LONGBLOB' : 'BLOB',
      DdlDialect.postgresql => 'BYTEA',
    };
  }

  return rawType;
}

String buildDefaultClause(
  String value,
  DdlDialect dialect, {
  TableDetailColumn? column,
}) {
  if (value.isEmpty) {
    return '';
  }

  if (value == "''") {
    return '';
  }

  final upper = value.toUpperCase();
  if (upper == 'NULL') {
    return ' DEFAULT NULL';
  }
  if (upper == 'SYSDATE') {
    return switch (dialect) {
      DdlDialect.oracle => ' DEFAULT SYSDATE',
      DdlDialect.mysql => ' DEFAULT CURRENT_TIMESTAMP',
      DdlDialect.postgresql => ' DEFAULT CURRENT_TIMESTAMP',
    };
  }
  if (upper == 'CURRENT_TIMESTAMP' || upper == 'NOW()') {
    return ' DEFAULT CURRENT_TIMESTAMP';
  }

  if (column != null && _isNumericColumnType(column)) {
    return ' DEFAULT ${_unquoteSqlLiteral(value)}';
  }

  final isNumeric = RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value);
  final isFunction = RegExp(r'^[A-Z_][A-Z0-9_]*(\(\))?$').hasMatch(upper);
  if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) {
    return ' DEFAULT $value';
  }
  if (isNumeric || isFunction) {
    return ' DEFAULT $value';
  }
  return ' DEFAULT ${sqlStringLiteral(value)}';
}

String sqlStringLiteral(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

bool _isIntegerSemanticDecimal(String base, String precision) {
  if (!['NUMBER', 'NUMERIC', 'DECIMAL'].contains(base)) {
    return false;
  }
  final parsedPrecision = _parsePositiveInt(precision);
  return precision.trim().isEmpty || parsedPrecision == null || parsedPrecision == 0;
}

bool _shouldUseBigInt(bool integerSemantic, String length) {
  if (!integerSemantic) {
    return false;
  }
  final parsedLength = _parsePositiveInt(length);
  return parsedLength != null && parsedLength > 10;
}

bool _shouldUseLargeText(String base, String length) {
  if (['CLOB', 'TEXT', 'LONGTEXT'].contains(base)) {
    return true;
  }
  if (![
    'VARCHAR',
    'VARCHAR2',
    'CHAR',
    'NCHAR',
    'NVARCHAR',
    'NVARCHAR2',
  ].contains(base)) {
    return false;
  }
  final parsedLength = _parsePositiveInt(length);
  return parsedLength != null && parsedLength > 4000;
}

bool _shouldUseLargeBinary(String base, String length) {
  if (base == 'BLOB') {
    return true;
  }
  if (!['RAW', 'BYTEA'].contains(base)) {
    return false;
  }
  final parsedLength = _parsePositiveInt(length);
  return parsedLength != null && parsedLength > 2000;
}

int? _parsePositiveInt(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return null;
  }
  final parsed = int.tryParse(normalized);
  if (parsed == null || parsed <= 0) {
    return null;
  }
  return parsed;
}

String _unquoteSqlLiteral(String value) {
  if (value.length < 2 || !value.startsWith("'") || !value.endsWith("'")) {
    return value;
  }
  return value.substring(1, value.length - 1).replaceAll("''", "'");
}

bool _isNumericColumnType(TableDetailColumn column) {
  final base = column.dataType.trim().toUpperCase().split('(').first.trim();
  return [
    'NUMBER',
    'NUMERIC',
    'DECIMAL',
    'INT',
    'INTEGER',
    'SMALLINT',
    'BIGINT',
    'TINYINT',
    'FLOAT',
    'DOUBLE',
    'REAL',
    'BINARY_FLOAT',
    'BINARY_DOUBLE',
  ].contains(base);
}
