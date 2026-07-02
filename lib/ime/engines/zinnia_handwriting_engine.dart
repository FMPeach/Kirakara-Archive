import '../handwriting_stroke.dart';
import '../ime_candidate.dart';
import '../ime_composition.dart';
import '../ime_engine.dart';
import '../ime_mode.dart';
import '../native/zinnia_native_bridge.dart';
import 'mock_handwriting_ime_engine.dart';

class ZinniaHandwritingEngine implements HandwritingImeEngine {
  ZinniaHandwritingEngine({
    NativeHandwritingBridge? bridge,
    HandwritingImeEngine? fallback,
    this.sessionId = 'kirakara-zinnia-session',
  })  : _bridge = bridge ??
            const UnavailableNativeHandwritingBridge(
              engineName: 'zinnia',
              reason: 'Zinnia bridge DLL is not configured',
            ),
        _fallback = fallback ?? MockHandwritingImeEngine();

  final NativeHandwritingBridge _bridge;
  final HandwritingImeEngine _fallback;
  final String sessionId;

  final List<ImeStroke> _strokes = [];
  ImeStroke? _activeStroke;
  ImeComposition _composition = ImeComposition.empty(ImeMode.handwriting);

  @override
  ImeMode get mode => ImeMode.handwriting;

  @override
  ImeComposition get composition => _composition;

  bool get isNativeAvailable => _bridge.isAvailable;
  String? get nativeUnavailableReason => _bridge.unavailableReason;

  @override
  Future<void> activate() async {
    if (_bridge.isAvailable) {
      await _bridge.activateSession(sessionId);
      return;
    }
    await _fallback.activate();
  }

  @override
  Future<void> deactivate() async {
    if (_bridge.isAvailable) {
      await _bridge.deactivateSession(sessionId);
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
    if (!_bridge.isAvailable) {
      _composition = await _fallback.beginStroke(x, y);
      return _composition;
    }
    _activeStroke = [ImeStrokePoint(x: x, y: y)];
    _composition = _strokeComposition(candidates: const []);
    return _composition;
  }

  @override
  Future<ImeComposition> appendStrokePoint(double x, double y) async {
    if (!_bridge.isAvailable) {
      _composition = await _fallback.appendStrokePoint(x, y);
      return _composition;
    }
    _activeStroke?.add(ImeStrokePoint(x: x, y: y));
    _composition = _strokeComposition(candidates: const []);
    return _composition;
  }

  @override
  Future<ImeComposition> endStroke() async {
    if (!_bridge.isAvailable) {
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
    if (!_bridge.isAvailable) {
      _composition = await _fallback.recognize();
      return _composition;
    }
    if (_strokes.isEmpty) {
      _composition = ImeComposition.empty(mode);
      return _composition;
    }
    final candidates = await _bridge.recognize(
      sessionId: sessionId,
      strokes: _strokes,
    );
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
    if (!_bridge.isAvailable) {
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
