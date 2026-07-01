import '../domain/lyric_project.dart';
import 'lyric_engine.dart';

class MockLyricEngine implements LyricEngine {
  @override
  Future<RenderedLyricLines> renderAt({
    required LyricProject project,
    required Duration position,
  }) async {
    final phase = position.inSeconds % 12;
    if (phase < 4) {
      return const RenderedLyricLines(
        ruby: 'いたみに',
        currentPrefix: '痛みに慣れてる',
        currentTail: ' フリをしていた',
        nextLine: '無数にできてた傷',
      );
    }
    if (phase < 8) {
      return const RenderedLyricLines(
        ruby: 'ながれる',
        currentPrefix: '流れる涙の',
        currentTail: ' 向こう側まで',
        nextLine: '声が届くように',
      );
    }
    return const RenderedLyricLines(
      ruby: 'ほしくず',
      currentPrefix: '星屑ステージ',
      currentTail: ' ライトの下で',
      nextLine: 'もう一度だけ歌う',
    );
  }
}
