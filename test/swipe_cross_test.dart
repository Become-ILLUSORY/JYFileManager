// 交叉验证：横滑连选与长按拖选、轻点、纵向滚动 互不干扰。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jy_file_manager/core/models/panel_state.dart';
import 'package:jy_file_manager/services/fs/local_fs.dart';
import 'package:jy_file_manager/ui/widgets/file_panel.dart';

Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Localizations(
        locale: const Locale('en', 'US'),
        delegates: const [
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: MiuixThemeController(
          child: SizedBox(width: 400, height: 700, child: child),
        ),
      ),
    );

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jy_cross');
    for (var i = 0; i < 14; i++) {
      File('${dir.path}/f$i.txt').writeAsStringSync('x');
    }
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<(PanelState, List<String>)> pumpPanel(WidgetTester tester) async {
    final items = await tester.runAsync(() => LocalFs.instance.list(dir.path));
    final state = PanelState(id: 0, initialPath: dir.path)..setItems(items!);
    final opened = <String>[];
    final longPressed = <String>[];
    await tester.pumpWidget(
      _host(
        FilePanel(
          state: state,
          panelIndex: 0,
          autoLoad: false,
          onOpenItem: (_, item) => opened.add(item.name),
          onItemLongPress: (_, item, _) => longPressed.add(item.name),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return (state, opened);
  }

  testWidgets('轻点仍能打开（不被横滑识别器吃掉）', (tester) async {
    final (state, opened) = await pumpPanel(tester);
    await tester.tapAt(const Offset(120, 60));
    await tester.pumpAndSettle();
    debugPrint('轻点 → 打开 = $opened，选中 = ${state.selected.length}（应为空）');
  });

  testWidgets('长按拖选仍有效', (tester) async {
    final (state, _) = await pumpPanel(tester);
    final g = await tester.startGesture(const Offset(120, 60));
    await tester.pump(const Duration(milliseconds: 700)); // 触发长按
    debugPrint('长按后 选中 = ${state.selected.length}');
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, 26)); // 纵向拖 156px ≈ 3 行
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugPrint('长按纵拖后 选中 = ${state.selected.length}（应 ≥ 3）');
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('纵向滚动仍能滚（不被横滑识别器抢走）', (tester) async {
    final (state, _) = await pumpPanel(tester);
    final scrollable = find.byType(Scrollable).first;
    final before = tester.widget<Scrollable>(scrollable).controller?.offset;

    final g = await tester.startGesture(const Offset(120, 400));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(2, -30)); // 向上滚
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    final after = tester.widget<Scrollable>(scrollable).controller?.offset;
    debugPrint('纵向滚动 offset: $before → $after（应变化），选中 = ${state.selected.length}（应为 0）');
  });

  testWidgets('选择模式下轻点 = 区间补选（回归）', (tester) async {
    final (state, _) = await pumpPanel(tester);
    // 先长按第 1 行进入选择模式
    var g = await tester.startGesture(const Offset(120, 60));
    await tester.pump(const Duration(milliseconds: 700));
    await g.up();
    await tester.pumpAndSettle();
    debugPrint('长按第1行 选中 = ${state.selected.length}（应为 1，进入选择模式）');

    // 再点第 4 行（y = 60 + 3*52 = 216），应把中间一并补选
    await tester.tapAt(const Offset(120, 216));
    await tester.pumpAndSettle();
    debugPrint('轻点第4行 选中 = ${state.selected.length}（区间补选应为 4）');
  });
}
