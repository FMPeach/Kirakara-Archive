import '../ime_candidate.dart';
import '../ime_composition.dart';
import '../ime_engine.dart';
import '../ime_mode.dart';
import '../native/ime_native_bridge.dart';
import 'mock_japanese_ime_engine.dart';

class MozcImeEngine implements ImeEngine {
  MozcImeEngine({
    NativeImeBridge? bridge,
    ImeEngine? fallback,
    this.sessionId = 'kirakara-mozc-session',
  })  : _bridge = bridge ??
            const UnavailableNativeImeBridge(
              engineName: 'mozc',
              reason: 'Mozc bridge DLL is not configured',
            ),
        _fallback = fallback ?? MockJapaneseImeEngine();

  final NativeImeBridge _bridge;
  final ImeEngine _fallback;
  final String sessionId;

  String _rawInput = '';
  int _pageIndex = 0;
  ImeComposition _composition =
      ImeComposition.empty(ImeMode.japaneseRomaji);

  @override
  ImeMode get mode => ImeMode.japaneseRomaji;

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
    if (!_bridge.isAvailable) {
      _composition = await _fallback.inputKey(key);
      return _composition;
    }
    _rawInput = '$_rawInput${key.toLowerCase()}';
    _pageIndex = 0;
    _composition = await _composeNative();
    return _composition;
  }

  @override
  Future<ImeComposition> backspace() async {
    if (!_bridge.isAvailable) {
      _composition = await _fallback.backspace();
      return _composition;
    }
    if (_rawInput.isNotEmpty) {
      _rawInput = _rawInput.substring(0, _rawInput.length - 1);
    }
    _pageIndex = 0;
    _composition = _rawInput.isEmpty
        ? ImeComposition.empty(mode)
        : await _composeNative();
    return _composition;
  }

  @override
  Future<ImeComposition> clear() async {
    if (!_bridge.isAvailable) {
      _composition = await _fallback.clear();
      return _composition;
    }
    _rawInput = '';
    _pageIndex = 0;
    final result = await _bridge.clear(sessionId);
    _composition = _fromNative(result);
    return _composition;
  }

  @override
  Future<ImeComposition> nextPage() async {
    if (!_bridge.isAvailable) {
      _composition = await _fallback.nextPage();
      return _composition;
    }
    if (_composition.hasNextPage) {
      _pageIndex += 1;
      _composition = await _composeNative();
    }
    return _composition;
  }

  @override
  Future<ImeComposition> previousPage() async {
    if (!_bridge.isAvailable) {
      _composition = await _fallback.previousPage();
      return _composition;
    }
    if (_pageIndex > 0) {
      _pageIndex -= 1;
      _composition = await _composeNative();
    }
    return _composition;
  }

  @override
  Future<ImeCommitResult> commitCandidate(int index) async {
    if (!_bridge.isAvailable) {
      final result = await _fallback.commitCandidate(index);
      _composition = result.composition;
      return result;
    }
    final candidates = _composition.candidates;
    final text = index >= 0 && index < candidates.length
        ? candidates[index].text
        : _rawInput;
    await clear();
    return ImeCommitResult(text: text, composition: _composition);
  }

  @override
  Future<ImeCommitResult> commitRaw() async {
    if (!_bridge.isAvailable) {
      final result = await _fallback.commitRaw();
      _composition = result.composition;
      return result;
    }
    final text = _rawInput;
    await clear();
    return ImeCommitResult(text: text, composition: _composition);
  }

  Future<ImeComposition> _composeNative() async {
    final result = await _bridge.compose(
      sessionId: sessionId,
      rawInput: _rawInput,
      pageIndex: _pageIndex,
    );
    return _fromNative(result);
  }

  ImeComposition _fromNative(NativeImeResult result) {
    return ImeComposition(
      mode: mode,
      rawInput: result.rawInput,
      preedit: result.preedit,
      candidates: [
        for (final candidate in result.candidates)
          ImeCandidate(
            text: candidate.text,
            annotation: candidate.annotation,
            score: candidate.score,
          ),
      ],
      pageIndex: result.pageIndex,
      hasPreviousPage: result.hasPreviousPage,
      hasNextPage: result.hasNextPage,
    );
  }
}
