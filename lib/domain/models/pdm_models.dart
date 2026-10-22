class ParsedPdmFile {
  const ParsedPdmFile({
    required this.modelName,
    required this.sourcePath,
    required this.sourceName,
    required this.tables,
  });

  final String modelName;
  final String sourcePath;
  final String sourceName;
  final List<ParsedPdmTable> tables;
}

class ParsedPdmImportResult {
  const ParsedPdmImportResult({
    required this.parsedFile,
    required this.fileHash,
  });

  final ParsedPdmFile parsedFile;
  final String fileHash;
}

class ParsedPdmTable {
  const ParsedPdmTable({
    required this.id,
    required this.name,
    required this.code,
    required this.comment,
    required this.columns,
  });

  final String id;
  final String name;
  final String code;
  final String comment;
  final List<ParsedPdmColumn> columns;
}

class ParsedPdmColumn {
  const ParsedPdmColumn({
    required this.id,
    required this.name,
    required this.code,
    required this.comment,
    required this.dataType,
    this.length = '',
    this.precision = '',
    this.nullable = true,
    this.defaultValue = '',
    required this.isPrimaryKey,
  });

  final String id;
  final String name;
  final String code;
  final String comment;
  final String dataType;
  final String length;
  final String precision;
  final bool nullable;
  final String defaultValue;
  final bool isPrimaryKey;
}

class TableDetail {
  const TableDetail({
    required this.tableName,
    required this.tableCode,
    required this.comment,
    required this.sourcePdm,
    required this.columns,
  });

  final String tableName;
  final String tableCode;
  final String comment;
  final String sourcePdm;
  final List<TableDetailColumn> columns;
}

class TableDetailColumn {
  const TableDetailColumn({
    required this.id,
    required this.name,
    required this.code,
    required this.dataType,
    this.length = '',
    this.precision = '',
    this.nullable = true,
    this.defaultValue = '',
    required this.isPrimaryKey,
    required this.comment,
  });

  final String id;
  final String name;
  final String code;
  final String dataType;
  final String length;
  final String precision;
  final bool nullable;
  final String defaultValue;
  final bool isPrimaryKey;
  final String comment;
}

class TableDetailTab {
  const TableDetailTab({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.pdmFileId,
    required this.sourceTableId,
    required this.sourcePdm,
    required this.tableName,
    required this.tableCode,
    required this.comment,
    required this.highlightedColumnIds,
  });

  final String id;
  final String projectId;
  final String projectName;
  final String pdmFileId;
  final String sourceTableId;
  final String sourcePdm;
  final String tableName;
  final String tableCode;
  final String comment;
  final List<String> highlightedColumnIds;

  String get displayCode => tableCode.trim().isEmpty ? tableName : tableCode;

  String get displayTableLabel {
    final normalizedComment = comment.trim();
    if (normalizedComment.isNotEmpty) {
      return normalizedComment;
    }
    final normalizedTableName = tableName.trim();
    if (normalizedTableName.isNotEmpty) {
      return normalizedTableName;
    }
    return '-';
  }
}
