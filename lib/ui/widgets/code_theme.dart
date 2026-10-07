// 代码高亮的配色主题（浅色 / 深色两套）。
//
// 说明：主题按 re_highlight 的 scope 命名体系定义（与 highlight.js 一致），
// 这里挑了编辑器里最常出现的若干 scope，保证关键字、字符串、注释、数字、
// 类型名这几类有清晰区分即可，不追求覆盖全部 scope（未覆盖的会退回基础色）。
import 'package:flutter/material.dart';

/// 高亮主题集合
class CodeThemes {
  CodeThemes._();

  /// 浅色主题（配浅色界面）
  static const Map<String, TextStyle> light = {
    'keyword': TextStyle(color: Color(0xFFD73A49), fontWeight: FontWeight.w600),
    'built_in': TextStyle(color: Color(0xFF005CC5)),
    'type': TextStyle(color: Color(0xFF005CC5)),
    'literal': TextStyle(color: Color(0xFF005CC5)),
    'number': TextStyle(color: Color(0xFF005CC5)),
    'string': TextStyle(color: Color(0xFF032F62)),
    'regexp': TextStyle(color: Color(0xFF032F62)),
    'subst': TextStyle(color: Color(0xFF24292E)),
    'symbol': TextStyle(color: Color(0xFF005CC5)),
    'class': TextStyle(color: Color(0xFF6F42C1), fontWeight: FontWeight.w600),
    'function': TextStyle(color: Color(0xFF6F42C1)),
    'title': TextStyle(color: Color(0xFF6F42C1)),
    'params': TextStyle(color: Color(0xFF24292E)),
    'comment': TextStyle(color: Color(0xFF6A737D), fontStyle: FontStyle.italic),
    'doctag': TextStyle(color: Color(0xFFD73A49), fontWeight: FontWeight.w600),
    'meta': TextStyle(color: Color(0xFF6A737D)),
    'meta-keyword': TextStyle(color: Color(0xFFD73A49)),
    'meta-string': TextStyle(color: Color(0xFF032F62)),
    'section': TextStyle(color: Color(0xFF005CC5), fontWeight: FontWeight.w600),
    'tag': TextStyle(color: Color(0xFF22863A)),
    'name': TextStyle(color: Color(0xFF22863A)),
    'attr': TextStyle(color: Color(0xFF6F42C1)),
    'attribute': TextStyle(color: Color(0xFF6F42C1)),
    'variable': TextStyle(color: Color(0xFFE36209)),
    'template-variable': TextStyle(color: Color(0xFFE36209)),
    'bullet': TextStyle(color: Color(0xFF735C0F)),
    'quote': TextStyle(color: Color(0xFF6A737D), fontStyle: FontStyle.italic),
    'emphasis': TextStyle(fontStyle: FontStyle.italic),
    'strong': TextStyle(fontWeight: FontWeight.w700),
    'link': TextStyle(color: Color(0xFF032F62), decoration: TextDecoration.underline),
    'code': TextStyle(color: Color(0xFF032F62)),
    'deletion': TextStyle(color: Color(0xFFB31D28), backgroundColor: Color(0xFFFFEEF0)),
    'addition': TextStyle(color: Color(0xFF22863A), backgroundColor: Color(0xFFF0FFF4)),
  };

  /// 深色主题（配深色界面）
  static const Map<String, TextStyle> dark = {
    'keyword': TextStyle(color: Color(0xFFFF7B72), fontWeight: FontWeight.w600),
    'built_in': TextStyle(color: Color(0xFF79C0FF)),
    'type': TextStyle(color: Color(0xFF79C0FF)),
    'literal': TextStyle(color: Color(0xFF79C0FF)),
    'number': TextStyle(color: Color(0xFF79C0FF)),
    'string': TextStyle(color: Color(0xFFA5D6FF)),
    'regexp': TextStyle(color: Color(0xFFA5D6FF)),
    'subst': TextStyle(color: Color(0xFFC9D1D9)),
    'symbol': TextStyle(color: Color(0xFF79C0FF)),
    'class': TextStyle(color: Color(0xFFD2A8FF), fontWeight: FontWeight.w600),
    'function': TextStyle(color: Color(0xFFD2A8FF)),
    'title': TextStyle(color: Color(0xFFD2A8FF)),
    'params': TextStyle(color: Color(0xFFC9D1D9)),
    'comment': TextStyle(color: Color(0xFF8B949E), fontStyle: FontStyle.italic),
    'doctag': TextStyle(color: Color(0xFFFF7B72), fontWeight: FontWeight.w600),
    'meta': TextStyle(color: Color(0xFF8B949E)),
    'meta-keyword': TextStyle(color: Color(0xFFFF7B72)),
    'meta-string': TextStyle(color: Color(0xFFA5D6FF)),
    'section': TextStyle(color: Color(0xFF79C0FF), fontWeight: FontWeight.w600),
    'tag': TextStyle(color: Color(0xFF7EE787)),
    'name': TextStyle(color: Color(0xFF7EE787)),
    'attr': TextStyle(color: Color(0xFFD2A8FF)),
    'attribute': TextStyle(color: Color(0xFFD2A8FF)),
    'variable': TextStyle(color: Color(0xFFFFA657)),
    'template-variable': TextStyle(color: Color(0xFFFFA657)),
    'bullet': TextStyle(color: Color(0xFFD2A8FF)),
    'quote': TextStyle(color: Color(0xFF8B949E), fontStyle: FontStyle.italic),
    'emphasis': TextStyle(fontStyle: FontStyle.italic),
    'strong': TextStyle(fontWeight: FontWeight.w700),
    'link': TextStyle(color: Color(0xFFA5D6FF), decoration: TextDecoration.underline),
    'code': TextStyle(color: Color(0xFFA5D6FF)),
    'deletion': TextStyle(color: Color(0xFFFFDCDE), backgroundColor: Color(0xFF67060C)),
    'addition': TextStyle(color: Color(0xFFAFF5B4), backgroundColor: Color(0xFF033A16)),
  };

  /// 按明暗取主题
  static Map<String, TextStyle> of(bool dark) => dark ? CodeThemes.dark : light;
}
