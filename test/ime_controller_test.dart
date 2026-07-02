import 'package:flutter_test/flutter_test.dart';
import 'package:kirakara_app/ime/ime_controller.dart';
import 'package:kirakara_app/ime/ime_mode.dart';
import 'package:kirakara_app/ime/search_query_controller.dart';

void main() {
  test('IME controller separates composition from committed search text',
      () async {
    final search = SearchQueryController();
    final ime = ImeController(searchQueryController: search);
    addTearDown(ime.dispose);
    addTearDown(search.dispose);

    await ime.handleKeyboardKey('A');
    expect(search.text, 'A');
    expect(ime.composition.rawInput, isEmpty);

    await ime.setMode(ImeMode.pinyin);
    await ime.handleKeyboardKey('L');
    await ime.handleKeyboardKey('V');

    expect(search.text, 'A');
    expect(ime.composition.rawInput, 'lv');
    expect(ime.composition.candidates.map((c) => c.text), contains('绿'));

    await ime.commitCandidate(0);
    expect(search.text, 'A绿');
    expect(ime.composition.rawInput, isEmpty);

    await ime.handleKeyboardKey('退格');
    expect(search.text, 'A');

    await ime.handleKeyboardKey('清空');
    expect(search.text, isEmpty);

    await ime.setMode(ImeMode.japaneseRomaji);
    for (final key in ['Z', 'A', 'N', 'K', 'O', 'K', 'U']) {
      await ime.handleKeyboardKey(key);
    }
    expect(
      ime.composition.candidates.map((c) => c.text),
      contains('残酷な天使'),
    );

    await ime.handleKeyboardKey('空格');
    expect(search.text, '残酷な天使');
    expect(ime.composition.rawInput, isEmpty);
  });
}
