// 侧滑选择语义的测试。
//
// 语义：滑动的起点行决定本次是「选中」还是「取消选中」——
//   起点未选中 → 本次滑过的行都被选中
//   起点已选中 → 本次滑过的行都被取消选中
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jy_file_manager/core/models/panel_state.dart';
import 'package:jy_file_manager/services/fs/local_fs.dart';
import 'package:jy_file_manager/ui/widgets/file_list_tile.dart';
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

/// 第 [row] 行（0 起）的中心 y 坐标
double _rowY(int row) => 2 + row * kFileRowHeight + kFileRowHeight / 2;

/// 纯横向滑动
Future<void> _swipe(WidgetTester tester, int row) async {
  final g = await tester.startGesture(Offset(120, _rowY(row)));
  await tester.pump(const Duration(milliseconds: 16));
  for (var i = 0; i < 5; i++) {
    await g.moveBy(const Offset(14, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jy_swipe_toggle');
    for (var i = 0; i < 12; i++) {
      File('${dir.path}/f$i.txt').writeAsStringSync('x');
    }
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<PanelState> pumpPanel(WidgetTester tester) async {
    final items = await tester.runAsync(() => LocalFs.instance.list(dir.path));
    final state = PanelState(id: 0, initialPath: dir.path)..setItems(items!);
    await tester.pumpWidget(
      _host(
        FilePanel(
          key: ValueKey(state.hashCode),
          state: state,
          panelIndex: 0,
          autoLoad: false,
          onOpenItem: (_, _) {},
          onItemLongPress: (_, _, _) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return state;
  }

  testWidgets('未选中项：侧滑一次选中它', (tester) async {
    final state = await pumpPanel(tester);
    await _swipe(tester, 1);
    debugPrint('第一次侧滑后 选中 ${state.selectedCount} 项');
    expect(state.selectedCount, 1);
  });

  testWidgets('已选中项：再次侧滑取消选中', (tester) async {
    final state = await pumpPanel(tester);

    await _swipe(tester, 1);
    debugPrint('第一次侧滑 → 选中 ${state.selectedCount} 项');
    expect(state.selectedCount, 1);

    await _swipe(tester, 1);
    debugPrint('第二次侧滑 → 选中 ${state.selectedCount} 项（应为 0）');
    expect(state.selectedCount, 0, reason: '对已选中的项再滑一次应取消选中');
  });

  testWidgets('取消模式下滑过多行：整段取消', (tester) async {
    final state = await pumpPanel(tester);

    // 先选中第 1~3 行（先滑第 1 行，再滑第 3 行补齐）
    await _swipe(tester, 1);
    await _swipe(tester, 3);
    debugPrint('选中第 1~3 行 → ${state.selectedCount} 项');
    expect(state.selectedCount, 3);

    // 从第 1 行起手（已选中）向第 3 行滑 → 应把这三行都取消
    final g = await tester.startGesture(Offset(120, _rowY(1)));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(Offset(0, _rowY(3) - _rowY(1)));
    await tester.pump(const Duration(milliseconds: 16));
    await g.up();
    await tester.pumpAndSettle();

    debugPrint('取消滑动后 → 选中 ${state.selectedCount} 项（应为 0）');
    expect(state.selectedCount, 0);
  });

  testWidgets('起点未选中时，滑过已选中的行会改为选中（不取消）', (tester) async {
    final state = await pumpPanel(tester);

    // 先只选中第 3 行
    await _swipe(tester, 3);
    expect(state.selectedCount, 1);

    // 从第 1 行（未选中）起手，滑到第 3 行 → 三行都选中
    final g = await tester.startGesture(Offset(120, _rowY(1)));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(Offset(0, _rowY(3) - _rowY(1)));
    await tester.pump(const Duration(milliseconds: 16));
    await g.up();
    await tester.pumpAndSettle();

    debugPrint('选中滑动后 → ${state.selectedCount} 项（应为 3）');
    expect(state.selectedCount, 3);
  });
}
