import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/domain/models/pdm_models.dart';
import 'package:pdm_viewer/ui/views/project_workspace_ddl.dart';

void main() {
  group('mapColumnType', () {
    test('maps mysql large text and long binary fields', () {
      const clobColumn = TableDetailColumn(
        id: 'c1',
        name: '内容',
        code: 'CONTENT',
        dataType: 'CLOB',
        isPrimaryKey: false,
        comment: '',
      );
      const longVarcharColumn = TableDetailColumn(
        id: 'c2',
        name: '说明',
        code: 'DESCRIPTION',
        dataType: 'VARCHAR',
        length: '8000',
        isPrimaryKey: false,
        comment: '',
      );
      const blobColumn = TableDetailColumn(
        id: 'c3',
        name: '附件',
        code: 'ATTACHMENT',
        dataType: 'BLOB',
        isPrimaryKey: false,
        comment: '',
      );

      expect(mapColumnType(clobColumn, DdlDialect.mysql), 'LONGTEXT');
      expect(mapColumnType(longVarcharColumn, DdlDialect.mysql), 'LONGTEXT');
      expect(mapColumnType(blobColumn, DdlDialect.mysql), 'LONGBLOB');
    });

    test('promotes integer semantic fields to bigint for mysql and pgsql', () {
      const intColumn = TableDetailColumn(
        id: 'c1',
        name: '编号',
        code: 'ID',
        dataType: 'INT',
        length: '11',
        precision: '0',
        isPrimaryKey: false,
        comment: '',
      );
      const numericIntegerColumn = TableDetailColumn(
        id: 'c2',
        name: '流水号',
        code: 'SERIAL_NO',
        dataType: 'NUMBER',
        length: '18',
        precision: '0',
        isPrimaryKey: false,
        comment: '',
      );

      expect(mapColumnType(intColumn, DdlDialect.mysql), 'BIGINT');
      expect(mapColumnType(intColumn, DdlDialect.postgresql), 'BIGINT');
      expect(mapColumnType(numericIntegerColumn, DdlDialect.mysql), 'BIGINT');
      expect(mapColumnType(numericIntegerColumn, DdlDialect.postgresql), 'BIGINT');
    });

    test('keeps decimal semantics and default integer mappings when in range', () {
      const decimalColumn = TableDetailColumn(
        id: 'c1',
        name: '金额',
        code: 'AMOUNT',
        dataType: 'DECIMAL',
        length: '18',
        precision: '2',
        isPrimaryKey: false,
        comment: '',
      );
      const tinyIntColumn = TableDetailColumn(
        id: 'c2',
        name: '状态',
        code: 'STATUS',
        dataType: 'TINYINT',
        length: '2',
        precision: '0',
        isPrimaryKey: false,
        comment: '',
      );

      expect(mapColumnType(decimalColumn, DdlDialect.mysql), 'DECIMAL(18,2)');
      expect(mapColumnType(decimalColumn, DdlDialect.postgresql), 'NUMERIC(18,2)');
      expect(mapColumnType(tinyIntColumn, DdlDialect.mysql), 'TINYINT');
      expect(mapColumnType(tinyIntColumn, DdlDialect.postgresql), 'SMALLINT');
    });

    test('maps postgresql large text fields to text', () {
      const longVarcharColumn = TableDetailColumn(
        id: 'c1',
        name: '说明',
        code: 'DESCRIPTION',
        dataType: 'NVARCHAR2',
        length: '5000',
        isPrimaryKey: false,
        comment: '',
      );
      const clobColumn = TableDetailColumn(
        id: 'c2',
        name: '内容',
        code: 'CONTENT',
        dataType: 'TEXT',
        isPrimaryKey: false,
        comment: '',
      );

      expect(mapColumnType(longVarcharColumn, DdlDialect.postgresql), 'TEXT');
      expect(mapColumnType(clobColumn, DdlDialect.postgresql), 'TEXT');
    });

    test('maps xmltype without length', () {
      const xmlColumn = TableDetailColumn(
        id: 'c1',
        name: '报文',
        code: 'PAYLOAD',
        dataType: 'XMLTYPE',
        length: '4000',
        isPrimaryKey: false,
        comment: '',
      );

      expect(mapColumnType(xmlColumn, DdlDialect.oracle), 'XMLTYPE');
      expect(mapColumnType(xmlColumn, DdlDialect.mysql), 'LONGTEXT');
      expect(mapColumnType(xmlColumn, DdlDialect.postgresql), 'XML');
    });
  });

  test('buildTableDdl keeps mysql engine clause while using mapped types', () {
    const detail = TableDetail(
      tableName: '日志',
      tableCode: 'APP_LOG',
      comment: '应用日志',
      sourcePdm: 'demo.pdm',
      columns: [
        TableDetailColumn(
          id: 'c1',
          name: '主键',
          code: 'ID',
          dataType: 'NUMBER',
          length: '18',
          precision: '0',
          nullable: false,
          isPrimaryKey: true,
          comment: '主键',
        ),
        TableDetailColumn(
          id: 'c2',
          name: '正文',
          code: 'CONTENT',
          dataType: 'CLOB',
          nullable: true,
          isPrimaryKey: false,
          comment: '正文',
        ),
      ],
    );

    final ddl = buildTableDdl(detail, DdlDialect.mysql);

    expect(ddl, contains('ID BIGINT NOT NULL COMMENT \'主键\''));
    expect(ddl, contains('CONTENT LONGTEXT COMMENT \'正文\''));
    expect(
      ddl,
      contains('ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin COMMENT=\'应用日志\''),
    );
  });

  test('buildTableDdl can skip table and column comments', () {
    const detail = TableDetail(
      tableName: '用户',
      tableCode: 'SYS_USER',
      comment: '系统用户',
      sourcePdm: 'demo.pdm',
      columns: [
        TableDetailColumn(
          id: 'c1',
          name: '主键',
          code: 'ID',
          dataType: 'NUMBER',
          length: '18',
          precision: '0',
          nullable: false,
          isPrimaryKey: true,
          comment: '主键',
        ),
        TableDetailColumn(
          id: 'c2',
          name: '姓名',
          code: 'USER_NAME',
          dataType: 'VARCHAR2',
          length: '64',
          nullable: true,
          isPrimaryKey: false,
          comment: '姓名',
        ),
      ],
    );

    final ddl = buildTableDdl(
      detail,
      DdlDialect.mysql,
      includeComments: false,
    );

    expect(ddl, isNot(contains('COMMENT=')));
    expect(ddl, isNot(contains(' COMMENT \'')));
    expect(
      ddl,
      contains('ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;'),
    );
  });

  test('buildDefaultClause treats empty quoted string as no default value', () {
    expect(buildDefaultClause("''", DdlDialect.mysql), isEmpty);
    expect(buildDefaultClause("''", DdlDialect.oracle), isEmpty);
    expect(buildDefaultClause("''", DdlDialect.postgresql), isEmpty);
  });

  test('buildDefaultClause keeps quoted literal defaults without extra quotes', () {
    expect(buildDefaultClause("' '", DdlDialect.mysql), " DEFAULT ' '");
    expect(buildDefaultClause("'A'", DdlDialect.oracle), " DEFAULT 'A'");
    expect(buildDefaultClause("'测试'", DdlDialect.postgresql), " DEFAULT '测试'");
  });

  test('buildDefaultClause removes quotes for numeric column defaults', () {
    const numericColumn = TableDetailColumn(
      id: 'c1',
      name: '状态',
      code: 'STATUS',
      dataType: 'NUMBER',
      length: '2',
      precision: '0',
      isPrimaryKey: false,
      comment: '',
    );
    const textColumn = TableDetailColumn(
      id: 'c2',
      name: '状态文本',
      code: 'STATUS_TEXT',
      dataType: 'VARCHAR2',
      length: '8',
      isPrimaryKey: false,
      comment: '',
    );

    expect(
      buildDefaultClause("'0'", DdlDialect.oracle, column: numericColumn),
      ' DEFAULT 0',
    );
    expect(
      buildDefaultClause("'12.5'", DdlDialect.mysql, column: numericColumn),
      ' DEFAULT 12.5',
    );
    expect(
      buildDefaultClause("'0'", DdlDialect.oracle, column: textColumn),
      " DEFAULT '0'",
    );
  });

  test('buildDefaultClause keeps numeric column expression defaults raw', () {
    const numericColumn = TableDetailColumn(
      id: 'c1',
      name: '流水号',
      code: 'SERIAL_NO',
      dataType: 'NUMBER',
      length: '22',
      precision: '0',
      isPrimaryKey: false,
      comment: '',
    );

    expect(
      buildDefaultClause(
        "TO_NUMBER(TO_CHAR(sysdate,'yyyymmddhh24miss'))",
        DdlDialect.oracle,
        column: numericColumn,
      ),
      " DEFAULT TO_NUMBER(TO_CHAR(sysdate,'yyyymmddhh24miss'))",
    );
  });

  test('buildTableDml generates basic crud templates from primary key', () {
    const detail = TableDetail(
      tableName: '用户',
      tableCode: 'SYS_USER',
      comment: '系统用户',
      sourcePdm: 'demo.pdm',
      columns: [
        TableDetailColumn(
          id: 'c1',
          name: '主键',
          code: 'ID',
          dataType: 'NUMBER',
          length: '18',
          precision: '0',
          nullable: false,
          isPrimaryKey: true,
          comment: '主键',
        ),
        TableDetailColumn(
          id: 'c2',
          name: '姓名',
          code: 'USER_NAME',
          dataType: 'VARCHAR2',
          length: '64',
          nullable: true,
          isPrimaryKey: false,
          comment: '姓名',
        ),
      ],
    );

    final dml = buildTableDml(detail, DdlDialect.mysql);

    expect(dml, contains('-- SELECT'));
    expect(dml, contains('FROM SYS_USER'));
    expect(dml, contains('WHERE ID = :ID;'));
    expect(dml, contains('-- INSERT'));
    expect(dml, contains('INSERT INTO SYS_USER (ID, USER_NAME)\nVALUES (:ID, :USER_NAME);'));
    expect(dml, contains(':USER_NAME'));
    expect(dml, contains('-- UPDATE'));
    expect(dml, contains('SET\n  USER_NAME = :USER_NAME\nWHERE ID = :ID;'));
    expect(dml, contains('-- DELETE'));
    expect(dml, contains('DELETE FROM SYS_USER WHERE ID = :ID;'));
  });
}
