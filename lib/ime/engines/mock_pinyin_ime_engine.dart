import '../ime_candidate.dart';
import '../ime_composition.dart';
import '../ime_engine.dart';
import '../ime_mode.dart';

class MockPinyinImeEngine implements ImeEngine {
  static const _pageSize = 6;
  static const _dictionary = <String, List<String>>{
    'lv': ['绿', '旅', '律', '率'],
    'liu': ['流', '留', '六'],
    'hua': ['花', '华', '化'],
    'tong': ['痛', '同', '童'],
    'can': ['残', '灿', '餐'],
    'gao': ['高', '稿', '告'],
    'qiao': ['桥', '乔', '侨'],
    'xing': ['星', '行', '醒'],
    'jie': ['街', '界', '节'],
    'dong': ['动', '东', '冬'],
    'fang': ['方', '芳', '房'],
  };

  String _rawInput = '';
  int _pageIndex = 0;
  ImeComposition _composition = ImeComposition.empty(ImeMode.pinyin);

  @override
  ImeMode get mode => ImeMode.pinyin;

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
    return [ImeCandidate(text: _rawInput, annotation: 'raw')];
  }
}
