import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pdm_viewer/data/services/pdm_parser_service.dart';
import 'package:pdm_viewer/data/services/pdm_writer_service.dart';
import 'package:pdm_viewer/domain/models/jdbc_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('writes reverse schema to parseable pdm xml', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'pdm_viewer_writer_test',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    const schema = ReverseSchemaModel(
      databaseType: JdbcDatabaseType.mysql,
      dataSourceName: 'Reverse Demo',
      schemaName: 'demo',
      catalogName: 'demo',
      tables: [
        ReverseTableModel(
          name: '用户表',
          code: 'T_USER',
          comment: '用户信息',
          schemaName: 'demo',
          rawIdentifier: 'demo.T_USER',
          columns: [
            ReverseColumnModel(
              name: '主键',
              code: 'ID',
              dataType: 'NUMBER',
              length: '18',
              precision: '0',
              nullable: false,
              defaultValue: '',
              isPrimaryKey: true,
              comment: '主键',
              ordinalPosition: 1,
            ),
            ReverseColumnModel(
              name: '姓名',
              code: 'USER_NAME',
              dataType: 'VARCHAR2',
              length: '64',
              precision: '',
              nullable: true,
              defaultValue: '',
              isPrimaryKey: false,
              comment: '姓名',
              ordinalPosition: 2,
            ),
          ],
        ),
      ],
    );

    final writer = PdmWriterService();
    final parser = PdmParserService();
    final outputPath = path.join(tempDir.path, 'reverse_demo.pdm');
    final xml = writer.buildPdmXml(
      schema: schema,
      modelName: 'Reverse Demo',
      sourcePath: outputPath,
    );
    expect(
      xml,
      contains(
        '<?PowerDesigner AppLocale="UTF16" ',
      ),
    );
    expect(xml, contains('<a:SessionID>00000000-0000-0000-0000-000000000000</a:SessionID>'));
    expect(xml, contains('<c:DefaultGroups>'));
    expect(xml, contains('<a:Name>PUBLIC</a:Name>'));
    expect(xml, contains('<c:DBMS>'));
    expect(xml, contains('<a:TargetID>BAE632F3-AC04-4059-9893-259ABA89351C</a:TargetID>'));
    expect(xml, contains('<c:TargetModels>'));
    expect(xml, contains('<a:Name>ORACLE Version 11g</a:Name>'));
    expect(xml, contains('<c:SessionShortcuts>'));
    expect(xml, contains('<o:Shortcut Ref="o1"/>'));
    expect(xml, contains('<c:ExtendedCollections>'));
    expect(xml, contains('<a:ExtendedBaseCollection.CollectionName>Related Columns</a:ExtendedBaseCollection.CollectionName>'));
    final outputFile = File(outputPath);
    await outputFile.writeAsString(xml);

    final parsed = await parser.parseFile(outputFile.path);

    expect(parsed.modelName, 'Reverse Demo');
    expect(parsed.tables, hasLength(1));
    expect(parsed.tables.single.code, 'T_USER');
    expect(parsed.tables.single.comment, '用户信息');
    expect(parsed.tables.single.columns, hasLength(2));
    expect(parsed.tables.single.columns.first.isPrimaryKey, isTrue);
    expect(parsed.tables.single.columns.last.code, 'USER_NAME');
  });
}
