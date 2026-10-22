import '../../domain/models/pdm_models.dart';
import '../../domain/models/search_models.dart';

class FieldTableCellPosition {
  const FieldTableCellPosition({
    required this.rowIndex,
    required this.columnIndex,
  });

  final int rowIndex;
  final int columnIndex;
}

class FieldTableSelection {
  const FieldTableSelection({required this.anchor, required this.focus});

  final FieldTableCellPosition anchor;
  final FieldTableCellPosition focus;

  int get startRow =>
      anchor.rowIndex <= focus.rowIndex ? anchor.rowIndex : focus.rowIndex;
  int get endRow =>
      anchor.rowIndex >= focus.rowIndex ? anchor.rowIndex : focus.rowIndex;
  int get startColumn => anchor.columnIndex <= focus.columnIndex
      ? anchor.columnIndex
      : focus.columnIndex;
  int get endColumn => anchor.columnIndex >= focus.columnIndex
      ? anchor.columnIndex
      : focus.columnIndex;

  bool contains(FieldTableCellPosition position) {
    return position.rowIndex >= startRow &&
        position.rowIndex <= endRow &&
        position.columnIndex >= startColumn &&
        position.columnIndex <= endColumn;
  }

  FieldTableSelection copyWith({
    FieldTableCellPosition? anchor,
    FieldTableCellPosition? focus,
  }) {
    return FieldTableSelection(
      anchor: anchor ?? this.anchor,
      focus: focus ?? this.focus,
    );
  }
}

String buildTableResultCopyText({
  required SearchResultItem item,
  required String projectLabel,
  required bool includeProject,
}) {
  final fields = <String>[
    (item.tableCode?.trim().isNotEmpty == true ? item.tableCode! : item.title)
        .trim(),
    item.comment.trim(),
    item.sourcePdm.trim(),
    if (includeProject) projectLabel.trim(),
  ];
  return fields.join('\t');
}

String buildTableResultsSelectionCopyText({
  required List<SearchResultItem> items,
  required FieldTableSelection selection,
  required String Function(SearchResultItem item) projectLabelFor,
}) {
  if (items.isEmpty) {
    return '';
  }
  final startRow = selection.startRow.clamp(0, items.length - 1);
  final endRow = selection.endRow.clamp(0, items.length - 1);
  final startColumn = selection.startColumn.clamp(0, 3);
  final endColumn = selection.endColumn.clamp(0, 3);
  final lines = <String>[];
  for (var rowIndex = startRow; rowIndex <= endRow; rowIndex++) {
    final item = items[rowIndex];
    final values = <String>[
      (item.tableCode?.trim().isNotEmpty == true ? item.tableCode! : item.title)
          .trim(),
      item.displayTableLabel.trim(),
      item.sourcePdm.trim(),
      projectLabelFor(item).trim(),
    ];
    lines.add(values.sublist(startColumn, endColumn + 1).join('\t'));
  }
  return lines.join('\n');
}

String toLowerCamelCase(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final words = RegExp(
    r'[A-Za-z0-9]+',
  ).allMatches(trimmed).map((match) => match.group(0)!).toList(growable: false);
  if (words.isEmpty) {
    return trimmed;
  }
  if (words.length == 1) {
    final word = words.single;
    if (word == word.toUpperCase()) {
      return word.toLowerCase();
    }
    return '${word[0].toLowerCase()}${word.substring(1)}';
  }

  final buffer = StringBuffer(words.first.toLowerCase());
  for (final word in words.skip(1)) {
    final normalized = word.toLowerCase();
    buffer
      ..write(normalized[0].toUpperCase())
      ..write(normalized.substring(1));
  }
  return buffer.toString();
}

String buildFieldSelectionCopyText({
  required List<String> headers,
  required List<TableDetailColumn> columns,
  required FieldTableSelection selection,
  bool camelCaseFieldNames = false,
}) {
  final lines = <String>[];
  for (
    var rowIndex = selection.startRow;
    rowIndex <= selection.endRow;
    rowIndex++
  ) {
    final row = <String>[];
    for (
      var columnIndex = selection.startColumn;
      columnIndex <= selection.endColumn;
      columnIndex++
    ) {
      row.add(
        _fieldTableValueForCell(
          headers: headers,
          columns: columns,
          rowIndex: rowIndex,
          columnIndex: columnIndex,
          camelCaseFieldNames: camelCaseFieldNames,
        ),
      );
    }
    lines.add(row.join('\t'));
  }
  return lines.join('\n');
}

String _fieldTableValueForCell({
  required List<String> headers,
  required List<TableDetailColumn> columns,
  required int rowIndex,
  required int columnIndex,
  required bool camelCaseFieldNames,
}) {
  if (rowIndex == 0) {
    return headers[columnIndex];
  }

  final column = columns[rowIndex - 1];
  switch (columnIndex) {
    case 0:
      return column.isPrimaryKey ? 'PK' : '';
    case 1:
      final code = column.code.trim();
      return camelCaseFieldNames ? toLowerCamelCase(code) : code;
    case 2:
      return column.name.trim();
    case 3:
      return column.dataType.trim();
    case 4:
      return column.length.trim();
    case 5:
      return column.precision.trim();
    case 6:
      return column.nullable ? '是' : '';
    case 7:
      return column.defaultValue.trim();
    case 8:
      return column.comment.trim();
    default:
      return '';
  }
}
