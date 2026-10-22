import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pdm_viewer/data/services/app_storage_directory.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('PdmViewerStorageTest');
  });

  tearDown(() => temp.delete(recursive: true));

  test('new installations use the PdmViewer directory', () async {
    final directory = await AppStorageDirectory.resolve(supportDirectory: temp);
    expect(path.basename(directory.path), 'PdmViewer');
    expect(await directory.exists(), isTrue);
  });

  test(
    'existing database, sidecars and theme survive directory migration',
    () async {
      final legacy = await Directory(
        path.join(temp.path, 'pdm_viewer'),
      ).create();
      for (final name in ['pdm_viewer.db', 'pdm_viewer.db-wal', 'theme.json']) {
        await File(path.join(legacy.path, name)).writeAsString(name);
      }
      final directory = await AppStorageDirectory.resolve(
        supportDirectory: temp,
      );
      for (final name in ['pdm_viewer.db', 'pdm_viewer.db-wal', 'theme.json']) {
        expect(
          await File(path.join(directory.path, name)).readAsString(),
          name,
        );
      }
      expect(await legacy.exists(), isFalse);
      expect(
        (await AppStorageDirectory.resolve(supportDirectory: temp)).path,
        directory.path,
      );
    },
  );

  test('does not overwrite an existing new directory', () async {
    final current = await Directory(path.join(temp.path, 'PdmViewer')).create();
    await File(path.join(current.path, 'theme.json')).writeAsString('new');
    final legacy = await Directory(path.join(temp.path, 'pdm_viewer')).create();
    await File(path.join(legacy.path, 'theme.json')).writeAsString('old');
    final directory = await AppStorageDirectory.resolve(supportDirectory: temp);
    expect(
      await File(path.join(directory.path, 'theme.json')).readAsString(),
      'new',
    );
    expect(await legacy.exists(), isTrue);
  });
}
