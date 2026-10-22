import 'pdm_models.dart';

class ProjectRecord {
  const ProjectRecord({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectRecord copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProjectRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ProjectPdmFileRecord {
  const ProjectPdmFileRecord({
    required this.id,
    required this.projectId,
    required this.path,
    required this.displayName,
    this.lastImportedAt,
    this.lastImportedHash,
    this.importError,
  });

  final String id;
  final String projectId;
  final String path;
  final String displayName;
  final DateTime? lastImportedAt;
  final String? lastImportedHash;
  final String? importError;

  bool get hasError => importError != null && importError!.trim().isNotEmpty;
}

enum StartupPdmChangeStatus {
  modified,
  missingOrUnreadable,
  baselineMissing,
}

class StartupPdmChange {
  const StartupPdmChange({
    required this.projectId,
    required this.projectName,
    required this.fileId,
    required this.displayName,
    required this.path,
    required this.status,
  });

  final String projectId;
  final String projectName;
  final String fileId;
  final String displayName;
  final String path;
  final StartupPdmChangeStatus status;
}

class ProjectPdmImportUpdate {
  const ProjectPdmImportUpdate({
    required this.projectId,
    required this.fileId,
    this.parsedFile,
    this.lastImportedHash,
    this.importError,
  });

  final String projectId;
  final String fileId;
  final ParsedPdmFile? parsedFile;
  final String? lastImportedHash;
  final String? importError;
}

class ProjectWorkspaceStats {
  const ProjectWorkspaceStats({
    required this.projectCount,
    required this.fileCount,
    required this.tableCount,
    required this.columnCount,
    required this.errorFileCount,
  });

  final int projectCount;
  final int fileCount;
  final int tableCount;
  final int columnCount;
  final int errorFileCount;
}
