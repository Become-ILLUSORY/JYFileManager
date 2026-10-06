// 主题封装：MIUIx 主题 + Liquid Glass 开关
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../services/app_settings.dart';

/// 应用主题构建器
class AppTheme {
  AppTheme._();

  /// 从 MIUIx 配色构建 Material 主题（供 Material 组件使用）
  static ThemeData materialFrom(MiuixColors colors, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: brightness,
    ).copyWith(
      surface: colors.surface,
      primary: colors.primary,
      error: colors.error,
      outline: colors.outline,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.surface,
      dividerColor: colors.dividerLine,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// 把应用设置映射为 MIUIx 配色模式
  static MiuixColorSchemeMode modeFrom(AppSettings settings) {
    final dark = switch (settings.themeMode) {
      AppThemeMode.dark => true,
      AppThemeMode.light => false,
      AppThemeMode.system => false,
    };
    final followSystem = settings.themeMode == AppThemeMode.system;

    if (settings.monetEnabled) {
      if (followSystem) return MiuixColorSchemeMode.monetSystem;
      return dark
          ? MiuixColorSchemeMode.monetDark
          : MiuixColorSchemeMode.monetLight;
    }
    if (followSystem) return MiuixColorSchemeMode.system;
    return dark ? MiuixColorSchemeMode.dark : MiuixColorSchemeMode.light;
  }
}

/// 全局主题桥：把 AppSettings 的主题选项映射到 MiuixThemeController，
/// 并向外提供 MaterialApp。子组件通过 [MiuixTheme.of] 取色。
class AppThemeBridge extends StatelessWidget {
  const AppThemeBridge({
    super.key,
    required this.settings,
    required this.builder,
  });

  final AppSettings settings;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    // 监听设置变化，主题/玻璃开关切换时整棵树重建
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MiuixThemeController(
          colorSchemeMode: AppTheme.modeFrom(settings),
          keyColor: settings.monetEnabled ? settings.keyColor : null,
          child: Builder(
            builder: (context) {
              final miuixTheme = MiuixTheme.of(context);
              return MaterialApp(
                title: 'JY文件管理器',
                debugShowCheckedModeBanner: false,
                themeMode: settings.materialThemeMode,
                theme: AppTheme.materialFrom(
                  miuixTheme.colors,
                  Brightness.light,
                ),
                darkTheme: AppTheme.materialFrom(
                  miuixTheme.colors,
                  Brightness.dark,
                ),
                home: builder(context),
              );
            },
          ),
        );
      },
    );
  }
}
