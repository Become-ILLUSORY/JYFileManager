// 终端功能键栏：软键盘缺少的控制键与方向键。
//
// 为什么需要它：Android 软键盘没有 Esc/Tab/Ctrl/方向键，
// 而这些是终端里最常用的键（补全、中断、翻历史、移动光标）。
// 这里用两行按键补齐，布局与常见终端 App 一致。
import 'package:flutter/material.dart';

/// 一个功能键
class TermKey {
  const TermKey(this.label, {this.send, this.action, this.flex = 1});

  /// 键面文字
  final String label;

  /// 按下后发送给终端的字节序列（null 表示只触发 action）
  final String? send;

  /// 本地动作（不发送给终端）
  final String? action;

  final int flex;
}

/// 终端功能键栏
class TerminalKeyBar extends StatelessWidget {
  const TerminalKeyBar({
    super.key,
    required this.onSend,
    required this.onAction,
    this.ctrlActive = false,
  });

  /// 发送字节给终端
  final void Function(String data) onSend;

  /// 本地动作：esc / tab / ctrl / up / down / left / right / enter / more
  final void Function(String action) onAction;

  /// Ctrl 是否处于激活态（激活后下一个字母键会转成控制字符）
  final bool ctrlActive;

  /// 第一行
  ///
  /// 箭头统一用「小三角」字符（U+25B4/U+25BE/U+25C2/U+25B8）：
  /// 常用的 ◀(U+25C0) ▶(U+25B6) 在 Unicode 里带 emoji 变体，
  /// Android 会渲染成橙色彩色 emoji，与其它键风格不一致。
  static const List<TermKey> row1 = [
    TermKey('Esc', send: '\x1b'),
    TermKey('Tab', action: 'tab'),
    TermKey('PgUp', send: '\x1b[5~'),
    TermKey('Home', send: '\x1b[H'),
    TermKey('\u25B4', action: 'up'),
    TermKey('End', send: '\x1b[F'),
    TermKey('⋮', action: 'more'),
  ];

  /// 第二行
  static const List<TermKey> row2 = [
    TermKey('Ctrl', action: 'ctrl'),
    TermKey('Alt', send: '\x1b'),
    TermKey('PgDn', send: '\x1b[6~'),
    TermKey('\u25C2', action: 'left'),
    TermKey('\u25BE', action: 'down'),
    TermKey('\u25B8', action: 'right'),
    TermKey('⏎', action: 'enter'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF16181D),
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(row1),
          const SizedBox(height: 4),
          _row(row2),
        ],
      ),
    );
  }

  Widget _row(List<TermKey> keys) {
    return Row(
      children: [
        for (final k in keys)
          Expanded(
            flex: k.flex,
            child: _key(k),
          ),
      ],
    );
  }

  Widget _key(TermKey k) {
    final isCtrl = k.action == 'ctrl';
    final active = isCtrl && ctrlActive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: active ? const Color(0xFF2D6CDF) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () {
            if (k.send != null) {
              onSend(k.send!);
            } else if (k.action != null) {
              onAction(k.action!);
            }
          },
          child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: Text(
              k.label,
              // 指定字体回退链：几何字符不要走 emoji 字体，
              // 否则 ▲▼◀▶ 会被渲染成彩色图标
              style: TextStyle(
                fontSize: k.label.length > 3 ? 12 : 13,
                fontFamily: 'Roboto',
                fontFamilyFallback: const ['Noto Sans', 'Droid Sans'],
                color: active
                    ? Colors.white
                    : const Color(0xFFD8DEE9),
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
