// 预测返回手势的跟手动效。
//
// 背景：根路由上我们把返回用于「返回上级目录 / 取消选择」，框架因此不会
// 播放自己的退出动画（见 home_page 的 handleStartBackGesture 注释），
// 跟手位移必须自己画。
//
// 参数对齐 Android 的「全屏预测返回」规格
// （flutter 的 PredictiveBackFullscreenPageTransition）：
//   - 位移   xShift = 屏宽 / 20 - 8，随进度线性跟随
//   - 缩放   1.0 → 0.95
//   - 圆角   手势期间渐显，优先用设备屏幕圆角，取不到时退回 28dp
//   - 压暗   越过提交点（0.65）之后才开始，之前保持原样
//
// 为什么是「卡片化」而不是单纯平移：Android 上退出的界面会缩成一张
// 圆角卡片浮在上一层之上，这是预测返回最显著的特征；只做平移会显得
// 生硬、不像系统行为。
import 'package:flutter/material.dart';

class PredictiveBackCard extends StatelessWidget {
  const PredictiveBackCard({
    super.key,
    required this.progress,
    required this.child,
  });

  /// 手势进度：0 = 未开始，1 = 已到提交点
  final double progress;

  final Widget child;

  /// Android 的提交点：越过此值松手即执行返回
  static const double commitAt = 0.65;

  /// 手势期间的最终缩放（Android 规格）
  static const double endScale = 0.95;

  /// 取不到设备圆角时的兜底值
  static const double _fallbackRadius = 28;

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    if (t <= 0) return child;

    final width = MediaQuery.sizeOf(context).width;
    // Android 规格：屏宽/20 - 8
    final shift = width / 20 - 8;
    final scale = 1 - (1 - endScale) * t;

    // 优先用设备屏幕圆角，让卡片边缘与屏幕外框一致
    final deviceRadii = MediaQuery.displayCornerRadiiOf(context);
    final radius = deviceRadii != null
        ? BorderRadius.lerp(BorderRadius.zero, deviceRadii, t)!
        : BorderRadius.circular(_fallbackRadius * t);

    // 提交点之后才开始压暗，之前保持原样（与 Android 一致）
    final dim = t <= commitAt
        ? 0.0
        : ((t - commitAt) / (1 - commitAt)).clamp(0.0, 1.0) * 0.35;

    return Stack(
      children: [
        // 背后的一层：手势期间渐显，让「浮起来」有依托
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.45 * t)),
        ),
        Transform.translate(
          offset: Offset(shift * t, 0),
          child: Transform.scale(
            scale: scale,
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  child,
                  if (dim > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: dim),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
