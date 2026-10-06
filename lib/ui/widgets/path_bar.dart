// 路径栏：全局唯一的面包屑，始终展示「焦点面板」的路径
//
// 设计意图：路径只在一处出现，避免左右面板各自重复一条路径造成的拥挤。
// 左侧 A/B 切换器表明当前焦点，面包屑可点击跳转，右侧为返回上级。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/utils/ui_icons.dart';
import 'sheets.dart';

class PathBar extends StatelessWidget {
  const PathBar({
    super.key,
    required this.path,
    required this.activeIndex,
    required this.canGoUp,
    required this.onSwitchPanel,
    required this.onNavigate,
    required this.onUp,
  });

  /// 焦点面板的当前路径
  final String path;

  /// 焦点面板索引（0=左，1=右）
  final int activeIndex;

  final bool canGoUp;
  final ValueChanged<int> onSwitchPanel;
  final ValueChanged<String> onNavigate;
  final VoidCallback onUp;

  /// 这些前缀作为面包屑起点，避免出现「根目录 › storage › emulated › 0」这类冗长路径
  static const _roots = <String, String>{
    '/storage/emulated/0': '内部存储',
    '/sdcard': '内部存储',
    '/storage/emulated': '存储设备',
    '/storage': '存储设备',
    '/': '根目录',
  };

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final crumbs = _crumbs(path);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: GlassSurface(
        radius: 16,
        alpha: 0.55,
        padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
        child: Row(
          children: [
            _PanelToggle(
              activeIndex: activeIndex,
              onSwitch: onSwitchPanel,
              colors: colors,
            ),
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 17,
              color: colors.dividerLine.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  children: [
                    for (var i = 0; i < crumbs.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: uiIcon(
                            UiIcons.chevronRight,
                            size: 13,
                            color: colors.onSurfaceVariantSummary
                                .withValues(alpha: 0.45),
                          ),
                        ),
                      _Crumb(
                        label: crumbs[i].label,
                        isLast: i == crumbs.length - 1,
                        onTap: () => onNavigate(crumbs[i].path),
                        colors: colors,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            _UpButton(
              enabled: canGoUp,
              onTap: onUp,
              colors: colors,
            ),
          ],
        ),
      ),
    );
  }

  /// 生成面包屑：从最贴近的存储根开始，末段为当前目录
  List<_CrumbData> _crumbs(String path) {
    var base = '/';
    for (final entry in _roots.entries) {
      final r = entry.key;
      if (path == r || path.startsWith('$r/')) {
        base = r;
        break;
      }
    }

    final result = <_CrumbData>[
      _CrumbData(label: _roots[base]!, path: base),
    ];
    if (base == path) return result;

    final rest = path.substring(base == '/' ? 1 : base.length + 1);
    var acc = base == '/' ? '' : base;
    for (final part in rest.split('/').where((e) => e.isNotEmpty)) {
      acc = '$acc/$part';
      result.add(_CrumbData(label: part, path: acc));
    }
    return result;
  }
}

/// 面包屑数据
class _CrumbData {
  const _CrumbData({required this.label, required this.path});
  final String label;
  final String path;
}

/// 单个路径段
class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.isLast,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool isLast;
  final VoidCallback onTap;
  final MiuixColors colors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: isLast ? 13 : 12.5,
              height: 1.15,
              color: isLast ? colors.primary : colors.onSurfaceVariantSummary,
              fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// A/B 焦点切换器
class _PanelToggle extends StatelessWidget {
  const _PanelToggle({
    required this.activeIndex,
    required this.onSwitch,
    required this.colors,
  });

  final int activeIndex;
  final ValueChanged<int> onSwitch;
  final MiuixColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.onSurfaceVariantSummary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 2; i++)
            _letter(i == activeIndex ? colors.primary : null, i),
        ],
      ),
    );
  }

  Widget _letter(Color? activeColor, int index) {
    final selected = activeColor != null;
    return GestureDetector(
      onTap: () => onSwitch(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 22,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          index == 0 ? 'A' : 'B',
          style: TextStyle(
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w700,
            color: selected
                ? colors.onPrimary
                : colors.onSurfaceVariantSummary,
          ),
        ),
      ),
    );
  }
}

/// 返回上级
class _UpButton extends StatelessWidget {
  const _UpButton({
    required this.enabled,
    required this.onTap,
    required this.colors,
  });

  final bool enabled;
  final VoidCallback onTap;
  final MiuixColors colors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 28,
          height: 26,
          child: Center(
            child: uiIcon(
              UiIcons.arrowUp,
              size: 17,
              color: enabled
                  ? colors.onSurface
                  : colors.onSurfaceVariantSummary.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}
