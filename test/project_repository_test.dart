import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pdm_viewer/data/database/app_database.dart';
import 'package:pdm_viewer/data/repositories/project_repository.dart';
import 'package:pdm_viewer/data/repositories/search_repository.dart';
import 'package:pdm_viewer/domain/models/pdm_models.dart';
import 'package:pdm_viewer/domain/models/search_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists projects, file links, indexes, and scoped search', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'pdm_viewer_repo_test',
    );
    final database = await AppDatabase.open(
      databasePath: path.join(tempDir.path, 'state.json'),
    );
    addTearDown(() async {
      database.dispose();
      await tempDir.delete(recursive: true);
    });
    final projectRepository = ProjectRepository(database);
    final searchRepository = SearchRepository(database);

    final project = await projectRepository.createProject('API 管理');
    final projectFile = await projectRepository.upsertProjectFile(
      projectId: project.id,
      filePath: 'D:/demo/13API管理.pdm',
    );

    await projectRepository.replaceProjectIndex(
      projectId: project.id,
      fileId: projectFile.id,
      lastImportedHash: sha256
          .convert(utf8.encode('D:/demo/13API管理.pdm:index'))
          .toString(),
      parsed: const ParsedPdmFile(
        modelName: 'API 管理',
        sourcePath: 'D:/demo/13API管理.pdm',
        sourceName: '13API管理.pdm',
        tables: [
          ParsedPdmTable(
            id: 'table-1',
            name: '作业管理_作业目录表',
            code: 'FV_JOB_FOLDER',
            comment: '目录表',
            columns: [
              ParsedPdmColumn(
                id: 'column-1',
                name: '文件夹ID',
                code: 'ID',
                comment: '主键',
                dataType: 'VARCHAR2(32)',
                isPrimaryKey: true,
              ),
            ],
          ),
        ],
      ),
    );

    final reloadedProjects = await projectRepository.getProjects();
    expect(reloadedProjects, hasLength(1));

    final stats = await projectRepository.getWorkspaceStats(project.id);
    expect(stats.fileCount, 1);
    expect(stats.tableCount, 1);
    expect(stats.columnCount, 1);

    final reloadedFiles = await projectRepository.getProjectFiles(project.id);
    expect(reloadedFiles.single.lastImportedHash, isNotEmpty);

    final tableResults = await searchRepository.search(
      projectId: project.id,
      keyword: 'JOB',
      scope: SearchScope.table,
    );
    expect(tableResults, hasLength(1));
    expect(tableResults.first.tableCode, 'FV_JOB_FOLDER');

    final columnResults = await searchRepository.search(
      projectId: project.id,
      keyword: 'ID',
      scope: SearchScope.column,
    );
    expect(columnResults, hasLength(1));
    expect(columnResults.first.tableCode, 'FV_JOB_FOLDER');
    expect(columnResults.first.matchedColumnIds, ['column-1']);

    final detail = await searchRepository.getTableDetail(
      projectId: project.id,
      pdmFileId: projectFile.id,
      sourceTableId: 'table-1',
    );
    expect(detail, isNotNull);
    expect(detail!.columns, hasLength(1));

    final filteredBrowse = await searchRepository.browse(
      projectId: project.id,
      pdmFileId: projectFile.id,
    );
    expect(filteredBrowse, hasLength(1));

    final allProjectBrowse = await searchRepository.browse(projectId: null);
    expect(allProjectBrowse, hasLength(1));

    final emptySearchBrowse = await searchRepository.search(
      projectId: null,
      keyword: '',
      scope: SearchScope.table,
    );
    expect(emptySearchBrowse, hasLength(1));
  });
}
