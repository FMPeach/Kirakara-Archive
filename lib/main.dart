import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app/kirakara_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final exeDir = p.dirname(Platform.resolvedExecutable);
  runApp(
    KirakaraApp(
      databasePath: p.join(exeDir, 'kirakara_index.db'),
    ),
  );
}
