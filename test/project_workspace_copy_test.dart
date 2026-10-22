import 'package:flutter_test/flutter_test.dart';
import 'package:pdm_viewer/domain/models/pdm_models.dart';
import 'package:pdm_viewer/domain/models/search_models.dart';
import 'package:pdm_viewer/ui/views/project_workspace_copy.dart';

void main() {
  test(
    'buildTableResultCopyText includes project column only when requested',
    () {
      const item = SearchResultItem(
        id: '1',
        projectId: 'p1',
        projectName: '项目A',
        title: '用户表',
        subtitle: '',
        comment: '用户信息',
        sourcePdm: 'demo.pdm',
        sourceTableId: 't1',
        pdmFileId: 'f1',
        matchedColumnIds: [],
        tableCode: 'USER_INFO',
        tableName: '用户表',
      );

      expect(
        buildTableResultCopyText(
          item: item,
          projectLabel: '项目A',
          includeProject: false,
        ),
        'USER_INFO\t用户信息\tdemo.pdm',
      );
      expect(
        buildTableResultCopyText(
          item: item,
          projectLabel: '项目A',
          includeProject: true,
        ),
        'USER_INFO\t用户信息\tdemo.pdm\t项目A',
      );
    },
  );

  test('buildFieldSelectionCopyText exports rectangular cells with tabs', () {
    const columns = [
      TableDetailColumn(
        id: 'c1',
        name: '姓名',
        code: 'NAME',
        dataType: 'varchar',
        length: '64',
        precision: '',
        nullable: false,
        defaultValue: '',
        isPrimaryKey: true,
        comment: '用户姓名',
      ),
      TableDetailColumn(
        id: 'c2',
        name: '年龄',
        code: 'AGE',
        dataType: 'int',
        length: '4',
        precision: '0',
        nullable: true,
        defaultValue: '18',
        isPrimaryKey: false,
        comment: '',
      ),
    ];

    const selection = FieldTableSelection(
      anchor: FieldTableCellPosition(rowIndex: 1, columnIndex: 0),
      focus: FieldTableCellPosition(rowIndex: 2, columnIndex: 2),
    );

    expect(
      buildFieldSelectionCopyText(
        headers: const ['主键', '字段名', '字段描述'],
        columns: columns,
        selection: selection,
      ),
      'PK\tNAME\t姓名\n\tAGE\t年龄',
    );
  });

  test('buildTableResultsSelectionCopyText exports selected table cells', () {
    const items = [
      SearchResultItem(
        id: '1',
        projectId: 'p1',
        projectName: '项目A',
        title: '用户表',
        subtitle: '',
        comment: '用户信息',
        sourcePdm: 'a.pdm',
        sourceTableId: 't1',
        pdmFileId: 'f1',
        matchedColumnIds: [],
        tableCode: 'USER_INFO',
        tableName: '用户表',
      ),
      SearchResultItem(
        id: '2',
        projectId: 'p1',
        projectName: '项目A',
        title: '角色表',
        subtitle: '',
        comment: '角色信息',
        sourcePdm: 'a.pdm',
        sourceTableId: 't2',
        pdmFileId: 'f1',
        matchedColumnIds: [],
        tableCode: 'ROLE_INFO',
        tableName: '角色表',
      ),
    ];

    expect(
      buildTableResultsSelectionCopyText(
        items: items,
        selection: const FieldTableSelection(
          anchor: FieldTableCellPosition(rowIndex: 0, columnIndex: 0),
          focus: FieldTableCellPosition(rowIndex: 1, columnIndex: 1),
        ),
        projectLabelFor: (item) => item.projectName,
      ),
      'USER_INFO\t用户信息\nROLE_INFO\t角色信息',
    );
  });

  test('buildFieldSelectionCopyText includes header row when selected', () {
    const columns = [
      TableDetailColumn(
        id: 'c1',
        name: '姓名',
        code: 'NAME',
        dataType: 'varchar',
        length: '64',
        precision: '',
        nullable: false,
        defaultValue: '',
        isPrimaryKey: true,
        comment: '用户姓名',
      ),
    ];

    const selection = FieldTableSelection(
      anchor: FieldTableCellPosition(rowIndex: 0, columnIndex: 0),
      focus: FieldTableCellPosition(rowIndex: 1, columnIndex: 1),
    );

    expect(
      buildFieldSelectionCopyText(
        headers: const ['主键', '字段名'],
        columns: columns,
        selection: selection,
      ),
      '主键\t字段名\nPK\tNAME',
    );
  });

  test('toLowerCamelCase converts common database field names', () {
    expect(toLowerCamelCase('USER_NAME'), 'userName');
    expect(toLowerCamelCase('user-name'), 'userName');
    expect(toLowerCamelCase('UserName'), 'userName');
    expect(toLowerCamelCase('USERID'), 'userid');
    expect(toLowerCamelCase('字段名'), '字段名');
  });

  test('camel case copy transforms every selected field name', () {
    const columns = [
      TableDetailColumn(
        id: 'c1',
        name: '用户名称',
        code: 'USER_NAME',
        dataType: 'varchar',
        isPrimaryKey: false,
        comment: '',
      ),
      TableDetailColumn(
        id: 'c2',
        name: '创建时间',
        code: 'CREATE_TIME',
        dataType: 'timestamp',
        isPrimaryKey: false,
        comment: '',
      ),
    ];

    expect(
      buildFieldSelectionCopyText(
        headers: const ['字段名'],
        columns: columns,
        selection: const FieldTableSelection(
          anchor: FieldTableCellPosition(rowIndex: 1, columnIndex: 1),
          focus: FieldTableCellPosition(rowIndex: 2, columnIndex: 1),
        ),
        camelCaseFieldNames: true,
      ),
      'userName\ncreateTime',
    );
  });
}
