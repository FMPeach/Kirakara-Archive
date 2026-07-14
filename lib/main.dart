import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/kirakara_app.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final exeDir = p.dirname(Platform.resolvedExecutable);
  final defaultCacheDirectory = Platform.isWindows
      ? (Directory(r'D:\').existsSync()
          ? r'D:\Kirakara_Cache'
          : p.join(exeDir, 'Kirakara_Cache'))
      : p.join((await getTemporaryDirectory()).path, 'Kirakara_Cache');
  final cacheDirectory =
      await SettingsService.resolveCacheDirectory(defaultCacheDirectory);
  runApp(
    KirakaraApp(
      databasePath: p.join(exeDir, 'kirakara_index.db'),
      cacheDirectoryPath: cacheDirectory,
    ),
  );
}
