// 应用内统一开关控件。
//
// 与 Miuix 原版开关的差异（针对本应用的浅色玻璃面板做了修正）：
//   1. Miuix 未选中轨道用的是 secondary(#E6E6E6)，叠在本应用的浅色玻璃
//      面板(#E5E5E5 左右)上几乎同色 —— 轨道直接“消失”，只剩一个白点，
//      看起来又扁又怪。这里把未选中轨道改为半透明前景色，保证可见。
//   2. 轨道与滑块都补上投影：轨道有落影、滑块有浮起感，
//      在浅色背景上也能看出「这是一颗可以拨动的开关」。
//   3. 打开时轨道带强调色光晕，进一步强化立体感。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  static const double _trackW = 50;
  static const double _trackH = 30;
  static const double _thumbSize = 24;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final on = value;
    final active = enabled && onChanged != null;

    final trackColor = !active
        ? colors.onSurface.withValues(alpha: 0.10)
        : on
            ? colors.primary
            : colors.onSurface.withValues(alpha: 0.18);

    return Semantics(
      toggled: on,
      enabled: active,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: active ? () => onChanged!(!on) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: _trackW,
          height: _trackH,
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(_trackH / 2),
            boxShadow: [
              // 轨道落影：让开关从面板上「浮」起来
              BoxShadow(
                color: Colors.black.withValues(alpha: active ? 0.20 : 0.10),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
              // 打开时叠加一圈强调色光晕
              if (active && on)
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.34),
                  blurRadius: 12,
                  spreadRadius: -1,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _gap),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: _thumbSize,
                height: _thumbSize,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.05),
                    width: 0.5,
                  ),
                  boxShadow: [
                    // 滑块浮起：下缘更重、上缘更轻
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 2,
                      offset: const Offset(0, -0.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
