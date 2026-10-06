// JY文件管理器 —— 应用入口
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/app_settings.dart';
import 'ui/pages/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.init();
  runApp(const JyFileManagerApp());
}

class JyFileManagerApp extends StatelessWidget {
  const JyFileManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppSettings>.value(
      value: AppSettings.instance,
      child: AppThemeBridge(
        settings: AppSettings.instance,
        builder: (context) {
          // MiuixScaffold 不提供 Material 祖先；缺少时 Text 会退化成
          // WidgetsApp 的 _errorTextStyle（红字 + 黄色双下划线）。
          // 这里补一层 Material，保证 DefaultTextStyle / InkWell 正常。
          return const Material(
            type: MaterialType.transparency,
            child: HomePage(),
          );
        },
      ),
    );
  }
}
