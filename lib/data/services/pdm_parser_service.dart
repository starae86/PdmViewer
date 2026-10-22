import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

import '../../domain/models/pdm_models.dart';

class PdmParserService {
  Future<ParsedPdmFile> parseFile(String filePath) async {
    final result = await parseFileWithHash(filePath);
    return result.parsedFile;
  }

  Future<ParsedPdmImportResult> parseFileWithHash(String filePath) {
    return Isolate.run(() => _parseFileWithHashSync(filePath));
  }

  Future<String> computeFileHash(String filePath) {
    return Isolate.run(() => _computeFileHashSync(filePath));
  }
}

ParsedPdmImportResult _parseFileWithHashSync(String filePath) {
  final bytes = File(filePath).readAsBytesSync();
  final content = utf8.decode(bytes);
  final document = XmlDocument.parse(content);

  final model = document.descendants.whereType<XmlElement>().firstWhere(
    (element) => element.name.qualified == 'o:Model',
  );

  final modelName = _childText(model, 'a:Name').trim();
  final tableElements = model.descendants.whereType<XmlElement>().where(
    (element) =>
        element.name.qualified == 'o:Table' &&
        element.getAttribute('Id') != null,
  );

  final tables = tableElements
      .map(_parseTable)
      .whereType<ParsedPdmTable>()
      .toList(growable: false);

  return ParsedPdmImportResult(
    parsedFile: ParsedPdmFile(
      modelName: modelName.isEmpty
          ? path.basenameWithoutExtension(filePath)
          : modelName,
      sourcePath: filePath,
      sourceName: path.basename(filePath),
      tables: tables,
    ),
    fileHash: sha256.convert(bytes).toString(),
  );
}

String _computeFileHashSync(String filePath) {
  final bytes = File(filePath).readAsBytesSync();
  return sha256.convert(bytes).toString();
}

ParsedPdmTable? _parseTable(XmlElement tableElement) {
  final tableId = tableElement.getAttribute('Id');
  if (tableId == null || tableId.isEmpty) {
    return null;
  }

  final keyColumns = <String, Set<String>>{};
  final keyParent = _childElement(tableElement, 'c:Keys');
  if (keyParent != null) {
    for (final keyElement in keyParent.childElements.where(
      (e) => e.name.qualified == 'o:Key',
    )) {
      final keyId = keyElement.getAttribute('Id');
      if (keyId == null || keyId.isEmpty) {
        continue;
      }
      final refs = keyElement.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.qualified == 'o:Column')
          .map((e) => e.getAttribute('Ref'))
          .whereType<String>()
          .toSet();
      keyColumns[keyId] = refs;
    }
  }

  final primaryKeyRef = _childElement(tableElement, 'c:PrimaryKey')
      ?.childElements
      .where((e) => e.name.qualified == 'o:Key')
      .map((e) => e.getAttribute('Ref'))
      .whereType<String>()
      .firstOrNull;
  final primaryColumns = primaryKeyRef == null
      ? <String>{}
      : (keyColumns[primaryKeyRef] ?? <String>{});

  final columnsParent = _childElement(tableElement, 'c:Columns');
  final columns = columnsParent == null
      ? const <ParsedPdmColumn>[]
      : columnsParent.childElements
            .where((element) => element.name.qualified == 'o:Column')
            .map(
              (column) {
                final dataType = _normalizeText(_childText(column, 'a:DataType'));
                final length = _resolveLength(
                  dataType: dataType,
                  explicitLength: _normalizeText(_childText(column, 'a:Length')),
                );
                final precision = _resolvePrecision(
                  dataType: dataType,
                  explicitPrecision: _normalizeText(
                    _childText(column, 'a:Precision'),
                  ),
                );
                final mandatory = _normalizeText(
                  _childText(column, 'a:Column.Mandatory'),
                );
                return ParsedPdmColumn(
                  id: column.getAttribute('Id') ?? '',
                  name: _normalizeText(_childText(column, 'a:Name')),
                  code: _normalizeText(_childText(column, 'a:Code')),
                  comment: _normalizeText(_childText(column, 'a:Comment')),
                  dataType: dataType,
                  length: length,
                  precision: precision,
                  nullable: !_isMandatory(mandatory),
                  defaultValue: _normalizeText(
                    _childText(column, 'a:DefaultValue'),
                  ),
                  isPrimaryKey: primaryColumns.contains(column.getAttribute('Id')),
                );
              },
            )
            .where((column) => column.id.isNotEmpty)
            .toList(growable: false);

  return ParsedPdmTable(
    id: tableId,
    name: _normalizeText(_childText(tableElement, 'a:Name')),
    code: _normalizeText(_childText(tableElement, 'a:Code')),
    comment: _normalizeText(_childText(tableElement, 'a:Comment')),
    columns: columns,
  );
}

XmlElement? _childElement(XmlElement parent, String qualifiedName) {
  for (final child in parent.childElements) {
    if (child.name.qualified == qualifiedName) {
      return child;
    }
  }
  return null;
}

String _childText(XmlElement parent, String qualifiedName) {
  return _childElement(parent, qualifiedName)?.innerText ?? '';
}

String _normalizeText(String value) {
  return value.trim().replaceAll('\r', '').replaceAll('\n', ' ');
}

String _resolveLength({
  required String dataType,
  required String explicitLength,
}) {
  if (explicitLength.isNotEmpty) {
    return explicitLength;
  }
  final match = RegExp(r'\((\d+)(?:\s*,\s*\d+)?\)').firstMatch(dataType);
  return match?.group(1) ?? '';
}

String _resolvePrecision({
  required String dataType,
  required String explicitPrecision,
}) {
  if (explicitPrecision.isNotEmpty) {
    return explicitPrecision;
  }
  final match = RegExp(r'\((\d+)\s*,\s*(\d+)\)').firstMatch(dataType);
  return match?.group(2) ?? '';
}

bool _isMandatory(String value) {
  return value.trim() == '1';
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
