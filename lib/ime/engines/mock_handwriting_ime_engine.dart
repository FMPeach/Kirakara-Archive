import '../ime_candidate.dart';
import '../ime_composition.dart';
import '../ime_engine.dart';
import '../ime_mode.dart';

class MockHandwritingImeEngine implements HandwritingImeEngine {
  static const _mockCandidates = [
    ImeCandidate(text: '残', annotation: '手写'),
    ImeCandidate(text: '花', annotation: '手写'),
    ImeCandidate(text: '高', annotation: '手写'),
    ImeCandidate(text: '緑', annotation: '手写'),
    ImeCandidate(text: '星', annotation: '手写'),
  ];

  String _rawInput = '';
  int _strokeCount = 0;
  ImeComposition _composition = ImeComposition.empty(ImeMode.handwriting);

  @override
  ImeMode get mode => ImeMode.handwriting;

  @override
  ImeComposition get composition => _composition;

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {
    await clear();
  }

  @override
  Future<ImeComposition> inputKey(String key) async {
    _rawInput = '$_rawInput$key';
    _composition = ImeComposition(
      mode: mode,
      rawInput: _rawInput,
      preedit: _rawInput,
      candidates: _mockCandidates,
    );
    return _composition;
  }

  @override
  Future<ImeComposition> backspace() async {
    if (_rawInput.isNotEmpty) {
      _rawInput = _rawInput.substring(0, _rawInput.length - 1);
    }
    _composition = _rawInput.isEmpty
        ? ImeComposition.empty(mode)
        : ImeComposition(
            mode: mode,
            rawInput: _rawInput,
            preedit: _rawInput,
            candidates: _mockCandidates,
          );
    return _composition;
  }

  @override
  Future<ImeComposition> clear() async {
    _rawInput = '';
    _strokeCount = 0;
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
    final text = _rawInput;
    await clear();
    return ImeCommitResult(text: text, composition: _composition);
  }

  @override
  Future<ImeComposition> beginStroke(double x, double y) async {
    _strokeCount += 1;
    _rawInput = '$_strokeCount 笔';
    _composition = ImeComposition(
      mode: mode,
      rawInput: _rawInput,
      preedit: _rawInput,
      candidates: const [],
    );
    return _composition;
  }

  @override
  Future<ImeComposition> appendStrokePoint(double x, double y) async {
    return _composition;
  }

  @override
  Future<ImeComposition> endStroke() async {
    return _composition;
  }

  @override
  Future<ImeComposition> recognize() async {
    if (_strokeCount == 0) {
      _composition = ImeComposition.empty(mode);
      return _composition;
    }
    _composition = ImeComposition(
      mode: mode,
      rawInput: _rawInput,
      preedit: _rawInput,
      candidates: _mockCandidates,
    );
    return _composition;
  }
}
