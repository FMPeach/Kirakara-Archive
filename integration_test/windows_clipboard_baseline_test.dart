import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _allowClipboardMutation = bool.fromEnvironment(
  'KIRAKARA_ALLOW_CLIPBOARD_MUTATION',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'stock Windows Clipboard API round-trips Unicode text',
    (_) async {
      final previous = await Clipboard.getData(Clipboard.kTextPlain);
      const sample = 'Kirakara 剪贴板基线 🙂\r\n第二行';
      try {
        await Clipboard.setData(const ClipboardData(text: sample));
        final result = await Clipboard.getData(Clipboard.kTextPlain);
        expect(result?.text, sample);
      } finally {
        await Clipboard.setData(ClipboardData(text: previous?.text ?? ''));
      }
    },
    skip: !Platform.isWindows || !_allowClipboardMutation,
  );
}
