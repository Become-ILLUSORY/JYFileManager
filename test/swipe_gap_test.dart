// 复现用户视频里的场景：
//   先横滑第 1 行 → 只选中它
//   再横滑第 5 行 → 期望「第 1..5 行」全被选上（中间的要补齐）
// 修复前实际只会选中 2 行（首尾各一），中间 3 行缺失。
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

/// 横向滑动（纯横向短滑，和视频里一致）
Future<void> _flickRight(WidgetTester tester, double y) async {
  final g = await tester.startGesture(Offset(120, y));
  await tester.pump(const Duration(milliseconds: 16));
  for (var i = 0; i < 5; i++) {
    await g.moveBy(const Offset(14, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pumpAndSettle();
}


/// 第 [row] 行（0 起）在列表中的中心 y 坐标。
/// 用常量推导，调整行高时测试自动跟随。
double _rowY(int row) => 2 + row * kFileRowHeight + kFileRowHeight / 2;

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jy_gap');
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

  // 行高 52，列表顶部 padding 2；第 0 行是「..」，第 1 行是 f0
  // 第 1 行中心 ≈ 2 + 1*52 + 26 = 80
  // 第 5 行中心 ≈ 2 + 5*52 + 26 = 288
  testWidgets('视频场景：先滑第1行、再滑第5行 → 中间应补齐', (tester) async {
    final state = await pumpPanel(tester);
    debugPrint('条目数 = ${state.items.length}');

    await _flickRight(tester, _rowY(1));
    debugPrint('第 1 次横滑（第1行）→ 选中 ${state.selected.length} 行（期望 1）');
    expect(state.selected.length, 1, reason: '第一次横滑应只选中起始行');

    await _flickRight(tester, _rowY(5));
    final names = state.selectedItems.map((e) => e.name).toList()..sort();
    debugPrint('第 2 次横滑（第5行）→ 选中 ${state.selected.length} 行（期望 5）');
    debugPrint('选中的是：$names');
    expect(state.selected.length, 5, reason: '第二次横滑应把中间的行一并选上');
  });
}

// 诊断：横滑两次时的实际选中过程
void debugGap() {}
