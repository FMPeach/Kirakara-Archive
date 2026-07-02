import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirakara_app/ime/ime_controller.dart';
import 'package:kirakara_app/ime/search_query_controller.dart';
import 'package:kirakara_app/ui/theme/kirakara_theme.dart';
import 'package:kirakara_app/ui/widgets/karaoke_input_panel.dart';

void main() {
  testWidgets('touch keyboard unfocuses hardware IME text field',
      (tester) async {
    tester.view.physicalSize = const Size(640, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final search = SearchQueryController();
    final ime = ImeController(searchQueryController: search);
    final focusNode = FocusNode(debugLabel: 'test-search');
    addTearDown(ime.dispose);
    addTearDown(search.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKirakaraTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 488,
            height: 760,
            child: KaraokeInputPanel(
              activeTab: '歌名',
              placeholder: '搜索歌名、歌手、编号',
              controller: search.textController,
              searchFocusNode: focusNode,
              imeController: ime,
              onTab: (_) {},
              onSearch: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isFalse);
    expect(search.text, 'A');

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '残酷');
    await tester.pump();
    expect(search.text, '残酷');
  });
}
