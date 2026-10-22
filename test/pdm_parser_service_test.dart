import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/data/services/pdm_parser_service.dart';
import 'package:pdm_viewer/domain/models/pdm_models.dart';

void main() {
  const samplePath = 'examples/sample.pdm';
  final parser = PdmParserService();
  late ParsedPdmFile parsed;

  setUpAll(() async {
    parsed = await parser.parseFile(samplePath);
  });

  ParsedPdmTable table(String code) =>
      parsed.tables.firstWhere((table) => table.code == code);

  test('parses sample model metadata and all three tables', () {
    expect(parsed.modelName, '订单管理示例');
    expect(parsed.sourceName, 'sample.pdm');
    expect(parsed.sourcePath, samplePath);
    expect(
      parsed.tables.map((table) => table.code),
      unorderedEquals(['SYS_USER', 'BIZ_ORDER', 'BIZ_ORDER_ITEM']),
    );
    expect(parsed.tables.map((table) => table.columns.length), everyElement(5));
    expect(table('BIZ_ORDER').name, '订单');
    expect(table('BIZ_ORDER').comment, '订单');
  });

  test('extracts single and composite primary keys and mandatory columns', () {
    for (final code in ['SYS_USER', 'BIZ_ORDER', 'BIZ_ORDER_ITEM']) {
      final keys = table(code).columns.where((column) => column.isPrimaryKey);
      expect(keys.map((column) => column.code), switch (code) {
        'SYS_USER' => ['USER_ID'],
        'BIZ_ORDER' => ['ORDER_ID'],
        _ => ['ORDER_ID', 'LINE_NO'],
      });
      expect(keys.map((column) => column.nullable), everyElement(false));
    }
    final order = table('BIZ_ORDER');
    expect(
      order.columns
          .firstWhere((column) => column.code == 'USER_ID')
          .isPrimaryKey,
      false,
    );
    expect(
      order.columns.firstWhere((column) => column.code == 'USER_ID').nullable,
      false,
    );
  });

  test(
    'preserves column order, names, comments, types and numeric precision',
    () {
      final order = table('BIZ_ORDER');
      expect(order.columns.map((column) => column.code), [
        'ORDER_ID',
        'USER_ID',
        'TOTAL_AMOUNT',
        'REMARK',
        'CREATED_AT',
      ]);
      final amount = order.columns[2];
      expect(amount.name, '订单金额');
      expect(amount.comment, '订单金额');
      expect(amount.dataType, 'NUMBER(12,2)');
      expect(amount.length, '12');
      expect(amount.precision, '2');
      final remark = order.columns[3];
      expect(remark.dataType, 'VARCHAR2(200)');
      expect(remark.length, '200');
      expect(remark.nullable, true);
    },
  );

  test(
    'preserves numeric and date defaults without inventing absent defaults',
    () {
      final order = table('BIZ_ORDER');
      expect(order.columns[2].defaultValue, '0');
      expect(order.columns[3].defaultValue, isEmpty);
      expect(order.columns[4].dataType, 'DATE');
      expect(order.columns[4].length, isEmpty);
      expect(order.columns[4].defaultValue, 'SYSDATE');
      expect(
        table(
          'SYS_USER',
        ).columns.firstWhere((column) => column.code == 'STATUS').defaultValue,
        '1',
      );
    },
  );

  test(
    'returns the same file hash when parsing and hashing the sample',
    () async {
      final result = await parser.parseFileWithHash(samplePath);
      expect(result.fileHash, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(result.fileHash, await parser.computeFileHash(samplePath));
      expect(result.parsedFile.modelName, parsed.modelName);
      expect(result.parsedFile.tables.length, 3);
    },
  );
}
