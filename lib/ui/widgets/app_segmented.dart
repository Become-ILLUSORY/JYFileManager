// 应用内统一的分段选择控件（用于主题切换等）。
//
// 为什么不用 MiuixTabRow：
//   1. 它的底是 `ColoredBox(color: colors.background(false))` —— 一层满宽、
//      无圆角的纯色背景。把 backgroundColor 设成 surfaceContainer(#FFFFFF)
//      后，在浅灰玻璃面板上就是一条又宽又硬的白色横带，四角方直、上下贴边，
//      蓝选中块周围还会围一圈白，非常突兀。
//   2. 每段宽度由 _calculateTabWidth 用 min/maxWidth 决定，默认
//      maxWidth=98 —— 三段 + 两处 9dp 间距共 312dp，比面板内容区还宽，
//      最右侧那段会被卡片圆角裁掉。
//
// 这里改为自绘：圆角轨道 + 会滑动的高亮胶囊，宽度按容器等分，
// 不铺白底、不会被裁、也不依赖第三方控件的内部布局约定。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

class AppSegmented extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.height = 40,
    this.padding = 3,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double height;

  /// 轨道内边距（高亮胶囊与轨道边缘的间隙）
  final double padding;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final n = tabs.length;
    if (n == 0) return const SizedBox.shrink();
    final index = selectedIndex.clamp(0, n - 1);
    final radius = height / 2 - 4;

    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // 极淡的轨道底色：既能看出「这是一条选择器」，
          // 又不会在浅色面板上形成一块突兀的实心色块。
          color: colors.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: LayoutBuilder(
            builder: (ctx, c) {
              final segW = c.maxWidth / n;
              return Stack(
                children: [
                  // 高亮胶囊：随选中项滑动
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment(
                      n == 1 ? 0 : -1 + 2 * index / (n - 1),
                      0,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      width: segW,
                      height: c.maxHeight,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(radius),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.28),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 文本层
                  Row(
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onSelected(i),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 200),
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.1,
                                  fontWeight: i == index
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: i == index
                                      ? colors.onPrimary
                                      : colors.onSurfaceVariantSummary,
                                ),
                                child: Text(
                                  tabs[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
