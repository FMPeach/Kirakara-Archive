import 'package:flutter_test/flutter_test.dart';
import 'package:kirakara_app/ime/engines/mozc_ime_engine.dart';
import 'package:kirakara_app/ime/native/ime_native_bridge.dart';

void main() {
  test('Mozc engine falls back to mock Japanese input when native is unavailable',
      () async {
    final engine = MozcImeEngine();

    expect(engine.isNativeAvailable, isFalse);
    for (final key in ['Z', 'A', 'N', 'K', 'O', 'K', 'U']) {
      await engine.inputKey(key);
    }

    expect(engine.composition.rawInput, 'zankoku');
    expect(
      engine.composition.candidates.map((c) => c.text),
      contains('残酷な天使'),
    );
  });

  test('Mozc engine maps native bridge candidates into composition', () async {
    final engine = MozcImeEngine(bridge: _FakeMozcBridge());

    expect(engine.isNativeAvailable, isTrue);
    for (final key in ['S', 'U', 'I', 'S', 'E', 'I']) {
      await engine.inputKey(key);
    }

    expect(engine.composition.rawInput, 'suisei');
    expect(engine.composition.candidates.single.text, '彗星');

    final commit = await engine.commitCandidate(0);
    expect(commit.text, '彗星');
    expect(commit.composition.rawInput, isEmpty);
  });
}

class _FakeMozcBridge implements NativeImeBridge {
  @override
  String get engineName => 'mozc';

  @override
  bool get isAvailable => true;

  @override
  String? get unavailableReason => null;

  @override
  Future<void> activateSession(String sessionId) async {}

  @override
  Future<void> deactivateSession(String sessionId) async {}

  @override
  Future<NativeImeResult> compose({
    required String sessionId,
    required String rawInput,
    required int pageIndex,
  }) async {
    return NativeImeResult(
      rawInput: rawInput,
      preedit: rawInput,
      candidates: [
        NativeImeCandidate(text: rawInput == 'suisei' ? '彗星' : rawInput),
      ],
    );
  }

  @override
  Future<NativeImeResult> clear(String sessionId) async {
    return const NativeImeResult(
      rawInput: '',
      preedit: '',
      candidates: [],
    );
  }
}
