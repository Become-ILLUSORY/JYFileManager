// 手势矩阵：多种真实滑动形状下，横滑连选是否生效。
//
// 真机上用户是斜着划的，而且速度/步长各异，所以这里覆盖：
// 各种角度、各种步长（快滑=大步长）、以及不应触发的纵向滚动。
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

Future<void> _swipePath(
  WidgetTester tester,
  Offset start,
  List<Offset> steps,
) async {
  final g = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 16));
  for (final s in steps) {
    await g.moveBy(s);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pumpAndSettle();
}

List<Offset> _line(double dx, double dy, {int steps = 12}) => List.generate(
      steps,
      (_) => Offset(dx / steps, dy / steps),
    );

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jy_matrix');
    for (var i = 0; i < 14; i++) {
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

  Future<int> scenario(
    WidgetTester tester,
    String label,
    Offset start,
    List<Offset> steps, {
    required bool expectSelect,
  }) async {
    final state = await pumpPanel(tester);
    await _swipePath(tester, start, steps);
    final n = state.selected.length;
    final ok = expectSelect ? n > 0 : n == 0;
    debugPrint('  ${ok ? "✓" : "✗"} [$label] 选中 $n 行');
    return n;
  }

  testWidgets('手势矩阵', (tester) async {
    debugPrint('=== 应触发连选（期望 >0）===');

    await scenario(tester, 'A 纯横向 60x0', const Offset(120, 60),
        _line(60, 0), expectSelect: true);

    await scenario(tester, 'B 45°斜向 60x60', const Offset(120, 60),
        _line(60, 60), expectSelect: true);

    await scenario(tester, 'C 30°偏横 80x45', const Offset(120, 60),
        _line(80, 45), expectSelect: true);

    await scenario(tester, 'D 先横40再纵120', const Offset(120, 60),
        [..._line(40, 0, steps: 6), ..._line(0, 120)], expectSelect: true);

    await scenario(tester, 'E 缓斜 100x130', const Offset(120, 60),
        _line(100, 130), expectSelect: true);

    await scenario(tester, 'H 偏陡 40x110', const Offset(120, 60),
        _line(40, 110), expectSelect: true);

    await scenario(tester, 'I 快滑（3 步）45°', const Offset(120, 60),
        _line(90, 90, steps: 3), expectSelect: true);

    await scenario(tester, 'J 快滑（2 步）横 80', const Offset(120, 60),
        _line(80, 20, steps: 2), expectSelect: true);

    await scenario(tester, 'K 小横移 25 大纵移 100', const Offset(120, 60),
        _line(25, 100), expectSelect: true);

    debugPrint('=== 不应触发（期望 0）===');

    await scenario(tester, 'F 纯纵向 0x150', const Offset(120, 60),
        _line(0, 150), expectSelect: false);

    await scenario(tester, 'G 轻微斜滚 12x150', const Offset(120, 60),
        _line(12, 150), expectSelect: false);

    await scenario(tester, 'L 纵向快滚 5x200', const Offset(120, 60),
        _line(5, 200, steps: 3), expectSelect: false);
  });
}
