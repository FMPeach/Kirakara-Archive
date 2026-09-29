import 'package:flutter_test/flutter_test.dart';
import 'package:kirakara_app/windows_compositor/compositor_probe_options.dart';

void main() {
  group('parseCompositorSoakSeconds', () {
    test('disables the bounded soak when unset or zero', () {
      expect(parseCompositorSoakSeconds(null), 0);
      expect(parseCompositorSoakSeconds(''), 0);
      expect(parseCompositorSoakSeconds('   '), 0);
      expect(parseCompositorSoakSeconds('0'), 0);
    });

    test('accepts the inclusive bounded duration range', () {
      expect(parseCompositorSoakSeconds('30'), 30);
      expect(parseCompositorSoakSeconds(' 30 '), 30);
      expect(parseCompositorSoakSeconds('1800'), 1800);
      expect(parseCompositorSoakSeconds('14400'), 14400);
    });

    test('rejects short, excessive, and malformed durations', () {
      for (final value in <String>['-1', '1', '29', '14401', 'thirty']) {
        expect(
          () => parseCompositorSoakSeconds(value),
          throwsA(isA<StateError>()),
          reason: value,
        );
      }
    });
  });
}
