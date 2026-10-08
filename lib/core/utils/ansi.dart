// ANSI 转义序列解析：把终端输出里的颜色码转成 Flutter 的 TextSpan。
//
// 为什么需要：`ls` 等命令在支持彩色输出时会插入 ANSI 转义序列
// （如 \x1b[01;34m 表示亮蓝），终端要把它们渲染成颜色，
// 而不是原样显示乱码。
//
// 支持的常见序列：
//   \x1b[<n>m        设置样式/颜色
//   \x1b[0m          重置
//   30-37 / 90-97    前景色（含亮色）
//   40-47 / 100-107  背景色
//   1 加粗 / 4 下划线 / 7 反显
//   \x1b[K           清除到行尾（忽略）
//   \x1b[<n>A/B/C/D  光标移动（忽略，终端不支持光标定位）
import 'package:flutter/material.dart';

/// 终端配色（与常见终端主题一致）
class TermColors {
  TermColors._();

  static const black = Color(0xFF3B4048);
  static const red = Color(0xFFE06C75);
  static const green = Color(0xFF98C379);
  static const yellow = Color(0xFFE5C07B);
  static const blue = Color(0xFF61AFEF);
  static const magenta = Color(0xFFC678DD);
  static const cyan = Color(0xFF56B6C2);
  static const white = Color(0xFFDCDFE4);
  static const brightBlack = Color(0xFF7F848E);
  static const brightRed = Color(0xFFFF7B86);
  static const brightGreen = Color(0xFFB4E08A);
  static const brightYellow = Color(0xFFFFD68A);
  static const brightBlue = Color(0xFF8FCCFF);
  static const brightMagenta = Color(0xFFE0A8F0);
  static const brightCyan = Color(0xFF7FD8E4);
  static const brightWhite = Color(0xFFFFFFFF);

  /// 标准 16 色
  static const List<Color> palette = [
    black, red, green, yellow, blue, magenta, cyan, white,
    brightBlack, brightRed, brightGreen, brightYellow,
    brightBlue, brightMagenta, brightCyan, brightWhite,
  ];
}

/// 一段带样式的文本
class AnsiSpan {
  const AnsiSpan(this.text, this.style);
  final String text;
  final TextStyle style;
}

/// ANSI 解析器
class AnsiParser {
  AnsiParser._();

  /// 把带 ANSI 码的字符串解析成若干段
  ///
  /// [base] 是默认样式，[defaultColor] 是未指定颜色时的前景色。
  static List<AnsiSpan> parse(
    String input, {
    required TextStyle base,
    required Color defaultColor,
  }) {
    final out = <AnsiSpan>[];
    final buf = StringBuffer();

    // 当前样式状态
    var fg = defaultColor;
    var bg = Colors.transparent;
    var bold = false;
    var underline = false;
    var reverse = false;

    void flush() {
      if (buf.isEmpty) return;
      var textColor = fg;
      var bgColor = bg;
      if (reverse) {
        final t = textColor;
        textColor = bgColor == Colors.transparent ? defaultColor : bgColor;
        bgColor = t;
      }
      out.add(AnsiSpan(
        buf.toString(),
        base.copyWith(
          color: textColor,
          backgroundColor: bgColor == Colors.transparent ? null : bgColor,
          fontWeight: bold ? FontWeight.w700 : null,
          decoration: underline ? TextDecoration.underline : null,
        ),
      ));
      buf.clear();
    }

    var i = 0;
    while (i < input.length) {
      final ch = input[i];

      // 转义序列起始
      if (ch == '\x1b' && i + 1 < input.length && input[i + 1] == '[') {
        final end = input.indexOf(RegExp(r'[A-Za-z]'), i + 2);
        if (end < 0) {
          // 序列不完整（可能跨 chunk），原样输出
          buf.write(input.substring(i));
          break;
        }
        final params = input.substring(i + 2, end);
        final cmd = input[end];

        if (cmd == 'm') {
          flush();
          final codes = params.isEmpty
              ? [0]
              : params.split(';').map((s) => int.tryParse(s) ?? 0).toList();
          for (final c in codes) {
            if (c == 0) {
              fg = defaultColor;
              bg = Colors.transparent;
              bold = false;
              underline = false;
              reverse = false;
            } else if (c == 1) {
              bold = true;
            } else if (c == 4) {
              underline = true;
            } else if (c == 7) {
              reverse = true;
            } else if (c == 22) {
              bold = false;
            } else if (c == 24) {
              underline = false;
            } else if (c == 27) {
              reverse = false;
            } else if (c >= 30 && c <= 37) {
              fg = TermColors.palette[c - 30];
            } else if (c >= 90 && c <= 97) {
              fg = TermColors.palette[c - 90 + 8];
            } else if (c >= 40 && c <= 47) {
              bg = TermColors.palette[c - 40];
            } else if (c >= 100 && c <= 107) {
              bg = TermColors.palette[c - 100 + 8];
            } else if (c == 39) {
              fg = defaultColor;
            } else if (c == 49) {
              bg = Colors.transparent;
            }
          }
          i = end + 1;
          continue;
        }

        // 其它控制序列（清行、光标移动等）直接丢弃
        i = end + 1;
        continue;
      }

      // 其它控制字符（除 \n \t）丢弃
      if (ch.codeUnitAt(0) < 0x20 && ch != '\n' && ch != '\t') {
        i++;
        continue;
      }

      buf.write(ch);
      i++;
    }

    flush();
    return out;
  }

  /// 去掉字符串里的 ANSI 序列（用于判断是否有内容）
  static String strip(String input) {
    return input.replaceAll(RegExp(r'\x1b\[[0-9;]*[A-Za-z]'), '');
  }
}
