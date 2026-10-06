// 主题封装：MIUIx 主题 + Liquid Glass 开关
//
// 关键点：MiuixThemeController 位于 MaterialApp **之外**，因此拿不到
// MediaQuery —— 不能依赖 MediaQuery.platformBrightnessOf 判断系统深色。
// 这里改为直接读 PlatformDispatcher 的平台亮度，并监听其变化重建。
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

  /// 解析「当前是否深色」——把「跟随系统」真正落到平台亮度上
  static bool resolveDark(AppSettings settings, Brightness platform) {
    return switch (settings.themeMode) {
      AppThemeMode.system => platform == Brightness.dark,
      AppThemeMode.light => false,
      AppThemeMode.dark => true,
    };
  }

  /// 把已解析的明暗映射为 MIUIx 配色模式
  static MiuixColorSchemeMode modeFrom(AppSettings settings, bool dark) {
    if (settings.monetEnabled) {
      return dark
          ? MiuixColorSchemeMode.monetDark
          : MiuixColorSchemeMode.monetLight;
    }
    return dark ? MiuixColorSchemeMode.dark : MiuixColorSchemeMode.light;
  }
}

/// 全局主题桥：把 AppSettings 的主题选项映射到 MiuixThemeController，
/// 并向外提供 MaterialApp。子组件通过 [MiuixTheme.of] 取色。
class AppThemeBridge extends StatefulWidget {
  const AppThemeBridge({
    super.key,
    required this.settings,
    required this.builder,
  });

  final AppSettings settings;
  final WidgetBuilder builder;

  @override
  State<AppThemeBridge> createState() => _AppThemeBridgeState();
}

class _AppThemeBridgeState extends State<AppThemeBridge>
    with WidgetsBindingObserver {
  Brightness _platform = Brightness.light;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _platform = WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 系统切换深浅色时重建
  @override
  void didChangePlatformBrightness() {
    final next = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (next != _platform && mounted) {
      setState(() => _platform = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听设置变化，主题/玻璃开关切换时整棵树重建
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final dark = AppTheme.resolveDark(widget.settings, _platform);
        return MiuixThemeController(
          colorSchemeMode: AppTheme.modeFrom(widget.settings, dark),
          keyColor:
              widget.settings.monetEnabled ? widget.settings.keyColor : null,
          isDark: dark,
          child: Builder(
            builder: (context) {
              final miuixTheme = MiuixTheme.of(context);
              return MaterialApp(
                title: 'JY文件管理器',
                debugShowCheckedModeBanner: false,
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                theme: AppTheme.materialFrom(
                  miuixTheme.colors,
                  Brightness.light,
                ),
                darkTheme: AppTheme.materialFrom(
                  miuixTheme.colors,
                  Brightness.dark,
                ),
                home: widget.builder(context),
              );
            },
          ),
        );
      },
    );
  }
}
