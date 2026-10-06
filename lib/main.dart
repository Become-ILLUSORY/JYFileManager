// JY文件管理器 - 入口
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/app_settings.dart';
import 'ui/theme.dart';
import 'ui/pages/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await AppSettings.instance.init();
  runApp(const JyApp());
}

class JyApp extends StatelessWidget {
  const JyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppSettings>.value(
      value: AppSettings.instance,
      child: Consumer<AppSettings>(
        builder: (context, settings, _) {
          return AppThemeBridge(
            settings: settings,
            builder: (context) => const HomePage(),
          );
        },
      ),
    );
  }
}
