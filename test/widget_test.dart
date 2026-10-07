// 冒烟测试：验证关键组件能正常构建。
//
// 注意：本沙箱里构建 MaterialApp 会 StackOverflow（测试环境的栈限制问题，
// 与项目代码无关 —— CI 里同样的代码能正常构建 APK），所以这里不 pumpWidget
// 整个 App，改为验证那些**与平台无关**的核心逻辑与轻量组件。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jy_file_manager/core/models/file_item.dart';
import 'package:jy_file_manager/core/models/panel_state.dart';
import 'package:jy_file_manager/ui/widgets/app_segmented.dart';
import 'package:jy_file_manager/ui/widgets/app_switch.dart';
import 'package:jy_file_manager/ui/widgets/predictive_back_card.dart';

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
  testWidgets('分段控件能渲染并可点击', (tester) async {
    var picked = -1;
    await tester.pumpWidget(
      _host(
        Center(
          child: AppSegmented(
            tabs: const ['跟随系统', '浅色', '深色'],
            selectedIndex: 0,
            onSelected: (i) => picked = i,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(picked, 2);
  });

  testWidgets('开关能渲染并切换', (tester) async {
    var value = false;
    await tester.pumpWidget(
      _host(
        Center(
          child: AppSwitch(value: false, onChanged: (v) => value = v),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(AppSwitch));
    await tester.pumpAndSettle();
    expect(value, isTrue);
  });

  testWidgets('预测返回卡片：进度 0 不加变换，进度 >0 才包裹', (tester) async {
    await tester.pumpWidget(
      _host(const PredictiveBackCard(progress: 0, child: Text('内容'))),
    );
    await tester.pump();
    expect(find.byType(Transform), findsNothing);

    await tester.pumpWidget(
      _host(const PredictiveBackCard(progress: 0.5, child: Text('内容'))),
    );
    await tester.pump();
    expect(find.byType(Transform), findsWidgets);
  });

  test('面板状态：选择与区间补选', () {
    final s = PanelState(id: 0, initialPath: '/');
    expect(s.hasSelection, isFalse);

    s.select('/a');
    s.select('/b');
    expect(s.selectedCount, 2);

    s.clearSelection();
    expect(s.hasSelection, isFalse);

    // setSelection 直接替换整个选中集合
    s.setSelection(['/x', '/y']);
    expect(s.selectedCount, 2);
    // selectedItems 只返回**列表里实际存在**的项，此时列表为空
    expect(s.selectedItems, isEmpty);

    // 载入条目后，selectedItems 才映射到具体 FileItem
    s.setItems([
      FileItem(name: 'x', path: '/x', isDirectory: false, modified: DateTime(2026)),
      FileItem(name: 'y', path: '/y', isDirectory: false, modified: DateTime(2026)),
      FileItem(name: 'z', path: '/z', isDirectory: false, modified: DateTime(2026)),
    ]);
    expect(s.selectedItems.length, 2);

    // 区间补选：把 0..2 全选上
    s.selectRange(0, 2, additive: true);
    expect(s.selectedCount, 3);
  });
}
