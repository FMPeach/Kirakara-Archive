import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kirakara_app/services/kirakara_show_ffi.dart';
import 'package:kirakara_app/services/stage_texture_service.dart';

const _videoPath = String.fromEnvironment('KIRAKARA_TEST_VIDEO');
const _lyricPath = String.fromEnvironment('KIRAKARA_TEST_LYRIC');
const _vocalPath = String.fromEnvironment('KIRAKARA_TEST_VOCAL');
const _accompanimentPath =
    String.fromEnvironment('KIRAKARA_TEST_ACCOMPANIMENT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'stock external texture attaches while a real Show source plays',
    (tester) async {
      for (final fixture in <String>[
        _videoPath,
        _lyricPath,
        _vocalPath,
        _accompanimentPath,
      ]) {
        expect(
          fixture,
          isNotEmpty,
          reason: 'Pass all KIRAKARA_TEST_* paths with --dart-define.',
        );
        expect(File(fixture).existsSync(), isTrue, reason: fixture);
      }

      final show = KirakaraShowFFI();
      final texture = StageTextureController();
      addTearDown(() async {
        await texture.setActive(false);
        show.stop();
        show.dispose();
      });

      show.setStageVisible(false);
      final textureId = await texture.attach(show.nativeHandleAddress);
      expect(textureId, isNotNull);
      expect(textureId, greaterThanOrEqualTo(0));
      await texture.setActive(true);

      await tester.pumpWidget(
        MaterialApp(
          home: ColoredBox(
            color: Colors.black,
            child: Texture(textureId: textureId!),
          ),
        ),
      );

      expect(
        show.load(
          _videoPath,
          lyricPath: _lyricPath,
          vocalPath: _vocalPath,
          accompanimentPath: _accompanimentPath,
        ),
        isTrue,
      );
      show.play();

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (show.position < 0.25 && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(show.position, greaterThanOrEqualTo(0.25));
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isWindows,
  );
}
