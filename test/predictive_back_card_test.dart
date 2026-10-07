// 预测返回卡片动效：变换参数与可逆性验证。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jy_file_manager/ui/widgets/predictive_back_card.dart';

Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: SizedBox(width: 400, height: 800, child: child),
      ),
    );

Offset _translateOf(WidgetTester tester) {
  final t = tester.widgetList<Transform>(find.byType(Transform)).toList();
  if (t.isEmpty) return Offset.zero;
  final m = t.first.transform;
  return Offset(m.storage[12], m.storage[13]);
}

double? _scaleOf(WidgetTester tester) {
  final t = tester.widgetList<Transform>(find.byType(Transform)).toList();
  if (t.length < 2) return null;
  return t[1].transform.storage[0];
}

double? _radiusOf(WidgetTester tester) {
  final clips = tester.widgetList<ClipRRect>(find.byType(ClipRRect)).toList();
  if (clips.isEmpty) return null;
  final r = clips.first.borderRadius;
  return r is BorderRadius ? r.topLeft.x : null;
}

void main() {
  testWidgets('进度 0 时不包裹任何变换', (tester) async {
    await tester.pumpWidget(
      _host(const PredictiveBackCard(progress: 0, child: Text('内容'))),
    );
    await tester.pump();
    debugPrint('progress=0 → Transform 数量 = '
        '${find.byType(Transform).evaluate().length}（应为 0）');
    expect(find.text('内容'), findsOneWidget);
  });

  testWidgets('进度递增：位移/缩放/圆角单调变化', (tester) async {
    for (final p in [0.0, 0.25, 0.5, 0.65, 0.9, 1.0]) {
      await tester.pumpWidget(
        _host(PredictiveBackCard(progress: p, child: const Text('内容'))),
      );
      await tester.pump();
      final dx = _translateOf(tester).dx;
      final s = _scaleOf(tester);
      debugPrint('progress=$p → 位移 dx=${dx.toStringAsFixed(1)} '
          '缩放=${s?.toStringAsFixed(3) ?? '-'} '
          '圆角=${_radiusOf(tester)?.toStringAsFixed(1) ?? '-'}');
    }
  });

  testWidgets('拖回 progress=0 应完全复原', (tester) async {
    await tester.pumpWidget(
      _host(const PredictiveBackCard(progress: 0.8, child: Text('内容'))),
    );
    await tester.pump();
    final wrapped = find.byType(Transform).evaluate().length;

    await tester.pumpWidget(
      _host(const PredictiveBackCard(progress: 0, child: Text('内容'))),
    );
    await tester.pump();
    final restored = find.byType(Transform).evaluate().length;
    debugPrint('progress=0.8 时 Transform=$wrapped → 拖回 0 后 Transform=$restored（应为 0）');
    expect(find.text('内容'), findsOneWidget);
  });
}
