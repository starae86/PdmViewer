import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Keeps settings, the database and generated runtime files in one directory.
class AppStorageDirectory {
  static Future<Directory> resolve({Directory? supportDirectory}) async {
    final support = supportDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(path.join(support.path, 'PdmViewer'));
    if (!await directory.exists()) {
      final legacyDirectories = [
        Directory(path.join(support.path, 'pdm_viewer')),
        // Windows support paths include the executable's product name.
        if (Platform.isWindows)
          Directory(path.join(support.parent.path, 'pdm_viewer', 'pdm_viewer')),
      ];
      for (final legacy in legacyDirectories) {
        if (await legacy.exists()) {
          await support.create(recursive: true);
          await legacy.rename(directory.path);
          break;
        }
      }
      await directory.create(recursive: true);
    }
    return directory;
  }
}
