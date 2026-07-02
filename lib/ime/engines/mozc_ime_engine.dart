import '../ime_candidate.dart';
import '../ime_composition.dart';
import '../ime_engine.dart';
import '../ime_mode.dart';
import '../native/ime_native_bridge.dart';
import '../native/mozc_native_bridge.dart';
import 'mock_japanese_ime_engine.dart';

class MozcImeEngine implements ImeEngine {
  MozcImeEngine({
    NativeImeBridge? bridge,
    ImeEngine? fallback,
    this.sessionId = 'kirakara-mozc-session',
  })  : _bridge = bridge ?? const MozcNativeBridgeProbe().probe(),
        _fallback = fallback ?? MockJapaneseImeEngine();

  final NativeImeBridge _bridge;
  final ImeEngine _fallback;
  final String sessionId;

  String _rawInput = '';
  int _pageIndex = 0;
  bool _nativeFailed = false;
  ImeComposition _composition = ImeComposition.empty(ImeMode.japaneseRomaji);

  @override
  ImeMode get mode => ImeMode.japaneseRomaji;

  @override
  ImeComposition get composition => _composition;

  bool get isNativeAvailable => _bridge.isAvailable && !_nativeFailed;
  String? get nativeUnavailableReason {
    if (_nativeFailed) {
      return 'Mozc native bridge failed and fallback is active';
    }
    return _bridge.unavailableReason;
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

  bool get _shouldUseFallback => !_bridge.isAvailable || _nativeFailed;

  Future<ImeComposition> _syncFallbackInput() async {
    var composition = await _fallback.clear();
    for (final codeUnit in _rawInput.codeUnits) {
      composition = await _fallback.inputKey(String.fromCharCode(codeUnit));
    }
    return composition;
  }

  @override
  Future<ImeComposition> inputKey(String key) async {
    if (_shouldUseFallback) {
      _composition = await _fallback.inputKey(key);
      return _composition;
    }
    _rawInput = '$_rawInput${key.toLowerCase()}';
    _pageIndex = 0;
    try {
      _composition = await _composeNative();
    } on Object {
      _nativeFailed = true;
      _composition = await _syncFallbackInput();
    }
    return _composition;
  }

  @override
  Future<ImeComposition> backspace() async {
    if (_shouldUseFallback) {
      _composition = await _fallback.backspace();
      return _composition;
    }
    if (_rawInput.isNotEmpty) {
      _rawInput = _rawInput.substring(0, _rawInput.length - 1);
    }
    _pageIndex = 0;
    try {
      _composition = _rawInput.isEmpty
          ? ImeComposition.empty(mode)
          : await _composeNative();
    } on Object {
      _nativeFailed = true;
      _composition = await _syncFallbackInput();
    }
    return _composition;
  }

  @override
  Future<ImeComposition> clear() async {
    _rawInput = '';
    _pageIndex = 0;
    if (_shouldUseFallback) {
      _composition = await _fallback.clear();
      return _composition;
    }
    try {
      final result = await _bridge.clear(sessionId);
      _composition = _fromNative(result);
    } on Object {
      _nativeFailed = true;
      _composition = await _fallback.clear();
    }
    return _composition;
  }

  @override
  Future<ImeComposition> nextPage() async {
    if (_shouldUseFallback) {
      _composition = await _fallback.nextPage();
      return _composition;
    }
    if (_composition.hasNextPage) {
      _pageIndex += 1;
      try {
        _composition = await _composeNative();
      } on Object {
        _nativeFailed = true;
        _composition = await _syncFallbackInput();
      }
    }
    return _composition;
  }

  @override
  Future<ImeComposition> previousPage() async {
    if (_shouldUseFallback) {
      _composition = await _fallback.previousPage();
      return _composition;
    }
    if (_pageIndex > 0) {
      _pageIndex -= 1;
      try {
        _composition = await _composeNative();
      } on Object {
        _nativeFailed = true;
        _composition = await _syncFallbackInput();
      }
    }
    return _composition;
  }

  @override
  Future<ImeCommitResult> commitCandidate(int index) async {
    if (_shouldUseFallback) {
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
    if (_shouldUseFallback) {
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
