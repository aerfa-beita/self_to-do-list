import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:todo_list/database/database.dart';

void main() {
  test(
    'Windows database is copied once into a stable user data path',
    () async {
      final root = await Directory.systemTemp.createTemp('todo-db-location-');
      addTearDown(() => root.delete(recursive: true));
      final legacy = File(join(root.path, 'legacy', 'todo_list.db'));
      await legacy.parent.create(recursive: true);
      await legacy.writeAsString('existing-data');

      final stablePath = await resolveWindowsDatabasePath(
        legacyPath: legacy.path,
        localAppDataPath: join(root.path, 'local-app-data'),
      );

      expect(stablePath, contains(join('XiaohuaTodo', 'todo_list.db')));
      expect(await File(stablePath).readAsString(), 'existing-data');
      expect(await legacy.readAsString(), 'existing-data');

      await legacy.writeAsString('newer-legacy-data');
      final resolvedAgain = await resolveWindowsDatabasePath(
        legacyPath: legacy.path,
        localAppDataPath: join(root.path, 'local-app-data'),
      );
      expect(resolvedAgain, stablePath);
      expect(await File(stablePath).readAsString(), 'existing-data');
    },
  );
}
