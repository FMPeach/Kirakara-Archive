import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kirakara_app/services/kirakara_show_ffi.dart';
import 'package:kirakara_app/services/stage_texture_service.dart';

const _videoPath = String.fromEnvironment('KIRAKARA_TEST_VIDEO');
const _lyricPath = String.fromEnvironment('KIRAKARA_TEST_LYRIC');
const _vocalPath = String.fromEnvironment('KIRAKARA_TEST_VOCAL');
const _accompanimentPath =
    String.fromEnvironment('KIRAKARA_TEST_ACCOMPANIMENT');
const _stageTextureChannel = MethodChannel('kirakara/stage_texture');

Future<Map<String, Object?>> _readDiagnosticsCounters() async {
  final result = await _stageTextureChannel.invokeMapMethod<String, Object?>(
    'getDiagnosticsCounters',
  );
  return result ?? <String, Object?>{};
}

int _counterDelta(
  Map<String, Object?> before,
  Map<String, Object?> after,
  String key,
) {
  return (after[key]! as int) - (before[key]! as int);
}

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

      if (Platform.environment['KIRAKARA_COMPOSITOR_DIAGNOSTICS'] == '1') {
        final activeBefore = await _readDiagnosticsCounters();
        expect(activeBefore['enabled'], isTrue);
        final activeSample = Stopwatch()..start();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 1)),
        );
        final activeAfter = await _readDiagnosticsCounters();
        activeSample.stop();
        final activeCallbacks = _counterDelta(
          activeBefore,
          activeAfter,
          'textureCallbacks',
        );
        final activeFrameAvailable = _counterDelta(
          activeBefore,
          activeAfter,
          'frameAvailableCalls',
        );
        final activeTextureAcquires = _counterDelta(
          activeBefore,
          activeAfter,
          'textureAcquires',
        );
        final activeAcquires = _counterDelta(
          activeBefore,
          activeAfter,
          'advancedTextureAcquires',
        );
        final activePresents = _counterDelta(
          activeBefore,
          activeAfter,
          'flutterPresents',
        );
        final activePresentsWithAcquire = _counterDelta(
          activeBefore,
          activeAfter,
          'flutterPresentsWithNewAcquire',
        );
        debugPrint(
          '[stage-baseline] active ${activeSample.elapsedMilliseconds}ms: '
          'callbacks=$activeCallbacks, '
          'frame_available=$activeFrameAvailable, '
          'texture_acquires=$activeTextureAcquires, '
          'advanced_acquires=$activeAcquires, presents=$activePresents, '
          'presents_with_new_acquire=$activePresentsWithAcquire',
        );
        expect(activeCallbacks, greaterThanOrEqualTo(45));
        expect(
          activeFrameAvailable,
          inInclusiveRange(activeCallbacks - 1, activeCallbacks + 1),
        );
        // At a 60 Hz desktop refresh, the stock external-texture path can
        // coalesce adjacent 60 Hz producer notifications before acquisition.
        // Phase 0 traces measured that behavior in both the official and the
        // unchanged local Engine, so this baseline protects minimum progress
        // and counter consistency instead of requiring the defect to vanish.
        final minimumAdvancedAcquires = (activeCallbacks * 2 / 3).floor();
        expect(
          activeAcquires,
          inInclusiveRange(minimumAdvancedAcquires, activeCallbacks),
        );
        expect(
          activeTextureAcquires,
          inInclusiveRange(activeAcquires, activeCallbacks + 2),
        );
        expect(
          activePresentsWithAcquire,
          // Counter snapshots cross the raster/present threads. One acquire
          // immediately before the first snapshot may be presented inside
          // the sample, or one acquire at the end may present just after it.
          inInclusiveRange(activeAcquires - 2, activeAcquires + 1),
        );
        expect(
          activePresents,
          inInclusiveRange(
            activePresentsWithAcquire,
            activePresentsWithAcquire + 3,
          ),
        );

        await texture.setActive(false);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        final inactiveBefore = await _readDiagnosticsCounters();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 750)),
        );
        final inactiveAfter = await _readDiagnosticsCounters();
        final inactiveCallbacks = _counterDelta(
          inactiveBefore,
          inactiveAfter,
          'textureCallbacks',
        );
        final inactivePresents = _counterDelta(
          inactiveBefore,
          inactiveAfter,
          'flutterPresents',
        );
        debugPrint(
          '[stage-baseline] inactive 750ms: callbacks=$inactiveCallbacks, '
          'presents=$inactivePresents',
        );
        expect(inactiveCallbacks, lessThanOrEqualTo(1));
        expect(inactivePresents, lessThanOrEqualTo(2));
      }
    },
    skip: !Platform.isWindows,
  );
}
