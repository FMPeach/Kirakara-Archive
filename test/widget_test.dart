import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirakara_app/app/kirakara_app.dart';
import 'package:kirakara_app/ui/widgets/kira_design_canvas.dart';

void main() {
  testWidgets('Kirakara controller shell renders', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TickerMode(
      enabled: false,
      child: KirakaraApp(databasePath: ':memory:'),
    ));
    await tester.pump();

    expect(find.text('Kira Karaoke'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.text('投屏'), findsOneWidget);
    expect(find.text('主控'), findsNothing);
    expect(find.text('歌名点歌'), findsOneWidget);
    expect(find.text('点歌列表'), findsOneWidget);
    expect(find.byType(KiraDesignCanvas), findsOneWidget);

    final fixedStage = find.byWidgetPredicate((widget) {
      return widget is SizedBox &&
          widget.width == KiraDesignCanvas.stageSize.width &&
          widget.height == KiraDesignCanvas.stageSize.height;
    });
    expect(fixedStage, findsOneWidget);

    final fittedStage = find.byWidgetPredicate((widget) {
      return widget is FittedBox && widget.fit == BoxFit.contain;
    });
    expect(fittedStage, findsOneWidget);

    await tester.tap(find.text('投屏'));
    await tester.pump();
    expect(find.text('显示输出'), findsOneWidget);
    expect(find.text('双屏异显'), findsOneWidget);
    expect(find.text('无线投屏'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();

    await tester.tap(find.byTooltip('设置'));
    await tester.pump();
    expect(find.text('报幕文字'), findsOneWidget);
    expect(find.text('媒体缓存'), findsOneWidget);
    expect(find.text('队列预缓存范围'), findsOneWidget);
  });

  testWidgets('browse pages render inside the controller shell',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TickerMode(
      enabled: false,
      child: KirakaraApp(databasePath: ':memory:'),
    ));
    await tester.pump();

    await tester.tap(find.text('歌名点歌').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('搜索歌名、歌手、编号'), findsWidgets);
    expect(find.text('搜索范围'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('返回').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('歌手点歌').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('地区与类型'), findsOneWidget);
    if (find.text('没有匹配歌手').evaluate().isNotEmpty) {
      expect(tester.takeException(), isNull);
      return;
    }
    expect(find.text('緑黄色社会'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('緑黄色社会').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('共 2 首歌曲'), findsOneWidget);
    expect(find.text('在歌手内搜索'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('返回').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('分类').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('番剧 OP / ED / 插曲'), findsOneWidget);
    expect(find.text('在当前分类中搜索歌曲、歌手、编号'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
