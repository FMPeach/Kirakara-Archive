import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/kirakara_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDirectory = await getApplicationSupportDirectory();
  runApp(
    KirakaraApp(
      databasePath: p.join(supportDirectory.path, 'kirakara_index.db'),
    ),
  );
}
