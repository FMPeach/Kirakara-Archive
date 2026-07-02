import '../handwriting_stroke.dart';
import '../ime_candidate.dart';
import '../ime_composition.dart';
import '../ime_engine.dart';
import '../ime_mode.dart';
import '../native/ime_native_bridge.dart';
import '../native/zinnia_native_bridge.dart';
import 'mock_handwriting_ime_engine.dart';

class ZinniaHandwritingEngine implements HandwritingImeEngine {
  ZinniaHandwritingEngine({
    NativeHandwritingBridge? bridge,
    HandwritingImeEngine? fallback,
    this.sessionId = 'kirakara-zinnia-session',
  })  : _bridge = bridge ?? const ZinniaNativeBridgeProbe().probe(),
        _fallback = fallback ?? MockHandwritingImeEngine();

  final NativeHandwritingBridge _bridge;
  final HandwritingImeEngine _fallback;
  final String sessionId;

  final List<ImeStroke> _strokes = [];
  ImeStroke? _activeStroke;
  bool _nativeFailed = false;
  ImeComposition _composition = ImeComposition.empty(ImeMode.handwriting);

  @override
  ImeMode get mode => ImeMode.handwriting;

  @override
  ImeComposition get composition => _composition;

  bool get isNativeAvailable => _bridge.isAvailable && !_nativeFailed;
  String? get nativeUnavailableReason {
    if (_nativeFailed) {
      return 'Zinnia native bridge failed and fallback is active';
    }
    return _bridge.unavailableReason;
  }

  Future<ImeComposition> _syncFallbackStrokesAndRecognize() async {
    await _fallback.clear();
    ImeComposition composition = ImeComposition.empty(mode);
    for (final stroke in _strokes) {
      if (stroke.isEmpty) {
        continue;
      }
      composition = await _fallback.beginStroke(stroke.first.x, stroke.first.y);
      for (final point in stroke.skip(1)) {
        composition = await _fallback.appendStrokePoint(point.x, point.y);
      }
      composition = await _fallback.endStroke();
    }
    if (_strokes.isNotEmpty) {
      composition = await _fallback.recognize();
    }
    return composition;
  }

  @override
  Future<void> activate() async {
    if (isNativeAvailable) {
      try {
        await _bridge.activateSession(sessionId);
        return;
      } on Object {
        _nativeFailed = true;
      }
    }
    await _fallback.activate();
  }

  @override
  Future<void> deactivate() async {
    if (isNativeAvailable) {
      try {
        await _bridge.deactivateSession(sessionId);
      } on Object {
        _nativeFailed = true;
      }
      return;
    }
    await _fallback.deactivate();
  }

  @override
  Future<ImeComposition> inputKey(String key) async {
    return _fallback.inputKey(key);
  }

  @override
  Future<ImeComposition> beginStroke(double x, double y) async {
    if (!isNativeAvailable) {
      _composition = await _fallback.beginStroke(x, y);
      return _composition;
    }
    _activeStroke = [ImeStrokePoint(x: x, y: y)];
    _composition = _strokeComposition(candidates: const []);
    return _composition;
  }

  @override
  Future<ImeComposition> appendStrokePoint(double x, double y) async {
    if (!isNativeAvailable) {
      _composition = await _fallback.appendStrokePoint(x, y);
      return _composition;
    }
    _activeStroke?.add(ImeStrokePoint(x: x, y: y));
    _composition = _strokeComposition(candidates: const []);
    return _composition;
  }

  @override
  Future<ImeComposition> endStroke() async {
    if (!isNativeAvailable) {
      _composition = await _fallback.endStroke();
      return _composition;
    }
    final stroke = _activeStroke;
    if (stroke != null && stroke.isNotEmpty) {
      _strokes.add(stroke);
    }
    _activeStroke = null;
    _composition = _strokeComposition(candidates: const []);
    return _composition;
  }

  @override
  Future<ImeComposition> recognize() async {
    if (!isNativeAvailable) {
      _composition = await _fallback.recognize();
      return _composition;
    }
    if (_strokes.isEmpty) {
      _composition = ImeComposition.empty(mode);
      return _composition;
    }
    late final List<NativeImeCandidate> candidates;
    try {
      candidates = await _bridge.recognize(
        sessionId: sessionId,
        strokes: _strokes,
      );
    } on Object {
      _nativeFailed = true;
      _composition = await _syncFallbackStrokesAndRecognize();
      return _composition;
    }
    _composition = _strokeComposition(
      candidates: [
        for (final candidate in candidates)
          ImeCandidate(
            text: candidate.text,
            annotation: candidate.annotation,
            score: candidate.score,
          ),
      ],
    );
    return _composition;
  }

  @override
  Future<ImeComposition> backspace() async {
    if (_strokes.isNotEmpty) {
      _strokes.removeLast();
    }
    _activeStroke = null;
    _composition = _strokeComposition(candidates: const []);
    return _composition;
  }

  @override
  Future<ImeComposition> clear() async {
    _strokes.clear();
    _activeStroke = null;
    if (!isNativeAvailable) {
      _composition = await _fallback.clear();
      return _composition;
    }
    _composition = ImeComposition.empty(mode);
    return _composition;
  }

  @override
  Future<ImeComposition> nextPage() async => _composition;

  @override
  Future<ImeComposition> previousPage() async => _composition;

  @override
  Future<ImeCommitResult> commitCandidate(int index) async {
    final candidates = _composition.candidates;
    if (index < 0 || index >= candidates.length) {
      return commitRaw();
    }
    final text = candidates[index].text;
    await clear();
    return ImeCommitResult(text: text, composition: _composition);
  }

  @override
  Future<ImeCommitResult> commitRaw() async {
    final text = _composition.rawInput;
    await clear();
    return ImeCommitResult(text: text, composition: _composition);
  }

  ImeComposition _strokeComposition({
    required List<ImeCandidate> candidates,
  }) {
    final count = _strokes.length + (_activeStroke == null ? 0 : 1);
    final rawInput = count == 0 ? '' : '$count 笔';
    return ImeComposition(
      mode: mode,
      rawInput: rawInput,
      preedit: rawInput,
      candidates: candidates,
    );
  }
}
