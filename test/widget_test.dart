// 冒烟测试：验证应用能启动并渲染主界面
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jy_file_manager/main.dart';
import 'package:jy_file_manager/ui/pages/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // 测试环境没有平台通道，需注入内存实现，否则 init() 会一直等待
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('应用启动并渲染双面板主界面', (WidgetTester tester) async {
    await tester.pumpWidget(const JyFileManagerApp());
    await tester.pump();

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);

    // 等待首帧后的目录加载完成
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  });
}
