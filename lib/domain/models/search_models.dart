enum SearchScope { all, table, column }

enum SearchTarget { currentProject, allProjects }

class SearchResultItem {
  const SearchResultItem({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.title,
    required this.subtitle,
    required this.comment,
    required this.sourcePdm,
    required this.sourceTableId,
    required this.pdmFileId,
    required this.matchedColumnIds,
    this.tableName,
    this.tableCode,
  });

  final String id;
  final String projectId;
  final String projectName;
  final String title;
  final String subtitle;
  final String comment;
  final String sourcePdm;
  final String sourceTableId;
  final String pdmFileId;
  final List<String> matchedColumnIds;
  final String? tableName;
  final String? tableCode;

  bool get hasHighlightedColumns => matchedColumnIds.isNotEmpty;

  String get displayTableLabel {
    final normalizedComment = comment.trim();
    if (normalizedComment.isNotEmpty) {
      return normalizedComment;
    }
    final normalizedTableName = (tableName ?? '').trim();
    if (normalizedTableName.isNotEmpty) {
      return normalizedTableName;
    }
    return title.trim();
  }
}
