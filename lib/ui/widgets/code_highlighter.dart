// 语法高亮引擎：按需注册语言，把源码转成带样式的 TextSpan。
//
// 性能考虑：
//   - re_highlight 的 highlight() 是纯 Dart 实现，几十 KB 的文件可以整篇处理；
//     但上 MB 的文件整篇高亮会明显卡顿，所以超过阈值时**只高亮可见部分**
//     （调用方传入起止行），其余按纯文本显示。
//   - 语言模块是懒加载的：只有真正用到某个语言时才 import 并注册，
//     避免把所有 197 种语言的 Mode 都塞进内存。
import 'package:flutter/material.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cmake.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/dos.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/groovy.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/less.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/objectivec.dart';
import 'package:re_highlight/languages/perl.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/properties.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/r.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scala.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/x86asm.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

/// 超过这个字符数就不再整篇高亮（改为只高亮可见区域）
const int kHighlightFullLimit = 200 * 1024;

class CodeHighlighter {
  CodeHighlighter._();

  static final Highlight _hl = Highlight()..safeMode();
  static final Set<String> _registered = {};

  /// 语言名 → 模块
  static final Map<String, Mode> _modules = {
    'bash': langBash,
    'c': langC,
    'cmake': langCmake,
    'cpp': langCpp,
    'csharp': langCsharp,
    'css': langCss,
    'dart': langDart,
    'diff': langDiff,
    'dockerfile': langDockerfile,
    'dos': langDos,
    'go': langGo,
    'groovy': langGroovy,
    'ini': langIni,
    'java': langJava,
    'javascript': langJavascript,
    'json': langJson,
    'kotlin': langKotlin,
    'less': langLess,
    'lua': langLua,
    'makefile': langMakefile,
    'markdown': langMarkdown,
    'objectivec': langObjectivec,
    'perl': langPerl,
    'php': langPhp,
    'powershell': langPowershell,
    'properties': langProperties,
    'python': langPython,
    'r': langR,
    'ruby': langRuby,
    'rust': langRust,
    'scala': langScala,
    'scss': langScss,
    'sql': langSql,
    'swift': langSwift,
    'typescript': langTypescript,
    'x86asm': langX86Asm,
    'xml': langXml,
    'yaml': langYaml,
  };

  static void _ensure(String? language) {
    if (language == null || _registered.contains(language)) return;
    final mode = _modules[language];
    if (mode == null) return;
    _hl.registerLanguage(language, mode);
    _registered.add(language);
  }

  /// 是否支持该语言的高亮
  static bool supports(String? language) =>
      language != null && _modules.containsKey(language);

  /// 把 [code] 高亮为 TextSpan。
  ///
  /// [base] 是基础文字样式（字体/字号），[theme] 是 scope → 样式映射。
  static TextSpan render(
    String code, {
    required String? language,
    required TextStyle base,
    required Map<String, TextStyle> theme,
  }) {
    _ensure(language);
    if (language == null || !_registered.contains(language)) {
      return TextSpan(text: code, style: base);
    }
    try {
      final result = _hl.highlight(code: code, language: language);
      final renderer = TextSpanRenderer(base, theme);
      result.render(renderer);
      return renderer.span ?? TextSpan(text: code, style: base);
    } catch (_) {
      // 高亮失败不应影响阅读，退回纯文本
      return TextSpan(text: code, style: base);
    }
  }
}
