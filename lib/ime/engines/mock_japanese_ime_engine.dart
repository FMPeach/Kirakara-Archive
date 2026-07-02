import '../ime_candidate.dart';
import '../ime_composition.dart';
import '../ime_engine.dart';
import '../ime_mode.dart';

class MockJapaneseImeEngine implements ImeEngine {
  static const _pageSize = 6;
  static const _dictionary = <String, List<String>>{
    'itami': ['痛み', 'いたみ'],
    'furishiteita': ['フリしていた'],
    'nagare': ['流れる涙は', 'ながれ'],
    'zankoku': ['残酷な天使', 'ざんこく'],
    'tenshi': ['天使', 'てんし'],
    'ryokuoushoku': ['緑黄色社会'],
    'hoshimachi': ['星街すいせい'],
    'suisei': ['すいせい', '彗星'],
  };

  String _rawInput = '';
  int _pageIndex = 0;
  ImeComposition _composition =
      ImeComposition.empty(ImeMode.japaneseRomaji);

  @override
  ImeMode get mode => ImeMode.japaneseRomaji;

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
    _rawInput = '$_rawInput${key.toLowerCase()}';
    _pageIndex = 0;
    _composition = _buildComposition();
    return _composition;
  }

  @override
  Future<ImeComposition> backspace() async {
    if (_rawInput.isNotEmpty) {
      _rawInput = _rawInput.substring(0, _rawInput.length - 1);
    }
    _pageIndex = 0;
    _composition = _buildComposition();
    return _composition;
  }

  @override
  Future<ImeComposition> clear() async {
    _rawInput = '';
    _pageIndex = 0;
    _composition = ImeComposition.empty(mode);
    return _composition;
  }

  @override
  Future<ImeComposition> nextPage() async {
    final candidates = _allCandidates();
    if ((_pageIndex + 1) * _pageSize < candidates.length) {
      _pageIndex += 1;
    }
    _composition = _buildComposition();
    return _composition;
  }

  @override
  Future<ImeComposition> previousPage() async {
    if (_pageIndex > 0) {
      _pageIndex -= 1;
    }
    _composition = _buildComposition();
    return _composition;
  }

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

  ImeComposition _buildComposition() {
    final candidates = _allCandidates();
    final start = _pageIndex * _pageSize;
    final visible = candidates.skip(start).take(_pageSize).toList();
    return ImeComposition(
      mode: mode,
      rawInput: _rawInput,
      preedit: _rawInput,
      candidates: visible,
      pageIndex: _pageIndex,
      hasPreviousPage: _pageIndex > 0,
      hasNextPage: start + _pageSize < candidates.length,
    );
  }

  List<ImeCandidate> _allCandidates() {
    if (_rawInput.isEmpty) {
      return const [];
    }
    final matched = <ImeCandidate>[];
    for (final entry in _dictionary.entries) {
      if (entry.key.startsWith(_rawInput) || _rawInput.startsWith(entry.key)) {
        matched.addAll(
          entry.value.map(
            (text) => ImeCandidate(text: text, annotation: entry.key),
          ),
        );
      }
    }
    if (matched.isNotEmpty) {
      return matched;
    }
    return [ImeCandidate(text: _rawInput, annotation: 'romaji')];
  }
}
