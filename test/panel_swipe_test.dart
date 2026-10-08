// 端到端：真实 FilePanel 里的横滑连选。
//
// 真实手势是「先横向起手，再纵向扫过几行」，而不是均匀斜线。
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


/// 第 [row] 行（0 起）在列表中的中心 y 坐标。
/// 用常量推导，调整行高时测试自动跟随，不会失效。
double _rowY(int row) => 2 + row * kFileRowHeight + kFileRowHeight / 2;

void main() {
  testWidgets('FilePanel：先横后纵扫过多行应连选', (tester) async {
    final dir = Directory.systemTemp.createTempSync('jy_swipe2');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    for (var i = 0; i < 12; i++) {
      File('${dir.path}/f$i.txt').writeAsStringSync('x');
    }

    // 直接用 LocalFs 读列表，避免 SmartFs 的提权探测把测试拖住
    final items = await tester.runAsync(
      () => LocalFs.instance.list(dir.path),
    );
    debugPrint('【准备】LocalFs 列出 = ${items!.length} 项');

    final state = PanelState(id: 0, initialPath: dir.path)
      ..setItems(items);
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
    debugPrint('【面板】条目数 = ${state.items.length}');

    // 场景 1：先横向起手（越过 slop），再纵向扫过 2 行
    var g = await tester.startGesture(Offset(120, _rowY(1)));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(5, 0)); // 横向累计 20
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugPrint('【1】横移 20 后 选中 = ${state.selected.length}');
    await g.moveBy(const Offset(0, 104)); // 纵向扫 2 行
    await tester.pump(const Duration(milliseconds: 16));
    debugPrint('【1】纵扫 104 后 选中 = ${state.selected.length}（应 ≥ 3）');
    await g.up();
    await tester.pumpAndSettle();
    debugPrint('【1】结束 选中 = ${state.selected.length}');
    state.clearSelection();

    // 场景 2：纯纵向滚动不应误触发
    g = await tester.startGesture(Offset(120, _rowY(5)));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(1, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    debugPrint('【2】纯纵向滚动 选中 = ${state.selected.length}（应为 0）');
  });
}
