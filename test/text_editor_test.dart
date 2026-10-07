// 文本编辑器与文本类型识别的测试。
//
// 覆盖：
//   1. 文件类型识别（哪些文件该进编辑器）
//   2. 内容嗅探（无扩展名/未知扩展名时按内容判断）
//   3. 编码往返（UTF-8 / GBK / UTF-16 中文不乱码）
//   4. 语法高亮不抛异常、且能产出带样式的 span
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jy_file_manager/core/utils/text_codec.dart';
import 'package:jy_file_manager/core/utils/text_file_kinds.dart';
import 'package:jy_file_manager/ui/widgets/code_highlighter.dart';
import 'package:jy_file_manager/ui/widgets/code_theme.dart';

void main() {
  group('文本类型识别', () {
    test('常见文本/代码扩展名应识别为可编辑', () {
      const yes = [
        'note.txt', 'config.yaml', 'data.json', 'main.py', 'app.c', 'App.java',
        'index.html', 'style.css', 'script.sh', 'README.md', 'settings.ini',
        'build.gradle', 'CMakeLists.txt', 'Dockerfile', 'Makefile', 'app.dart',
        'main.go', 'lib.rs', 'index.js', 'types.ts', 'query.sql', 'log.txt',
        'a.log', 'b.csv', 'c.xml', 'd.properties', 'e.toml', 'f.env',
      ];
      for (final n in yes) {
        expect(TextFileKinds.isTextByName(n), isTrue, reason: '$n 应可编辑');
      }
    });

    test('二进制扩展名不应识别为文本', () {
      const no = [
        'photo.png', 'video.mp4', 'song.mp3', 'archive.zip', 'app.apk',
        'doc.pdf', 'lib.so', 'data.db', 'font.ttf', 'a.exe', 'b.jar',
      ];
      for (final n in no) {
        expect(TextFileKinds.isTextByName(n), isFalse, reason: '$n 不应可编辑');
      }
    });

    test('歧义扩展名：.ts 按 TypeScript 处理（内容嗅探兜底视频流）', () {
      // .ts 既是 TypeScript 也是 MPEG-TS 视频流，代码文件更常见，
      // 所以按文本处理；真的视频流会被内容嗅探拦下（含 NUL 字节）
      expect(TextFileKinds.isTextByName('index.ts'), isTrue);
      expect(TextFileKinds.kindOf('index.ts')?.language, 'typescript');

      final videoLike = Uint8List.fromList([0x47, 0x40, 0x00, 0x10, 0x00, 0x00]);
      expect(TextFileKinds.looksLikeText(videoLike), isFalse,
          reason: '含 NUL 的视频流应被嗅探为二进制');
    });

    test('语言映射正确', () {
      expect(TextFileKinds.kindOf('a.py')?.language, 'python');
      expect(TextFileKinds.kindOf('a.yaml')?.language, 'yaml');
      expect(TextFileKinds.kindOf('a.yml')?.language, 'yaml');
      expect(TextFileKinds.kindOf('a.json')?.language, 'json');
      expect(TextFileKinds.kindOf('a.java')?.language, 'java');
      expect(TextFileKinds.kindOf('a.c')?.language, 'c');
      expect(TextFileKinds.kindOf('a.cpp')?.language, 'cpp');
      expect(TextFileKinds.kindOf('a.txt')?.language, isNull); // 纯文本不高亮
    });

    test('内容嗅探：文本 vs 二进制', () {
      final text = Uint8List.fromList(utf8.encode('hello\nworld\n'));
      expect(TextFileKinds.looksLikeText(text), isTrue);

      // 含 NUL 字节 → 二进制
      final bin = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x00, 0x0D]);
      expect(TextFileKinds.looksLikeText(bin), isFalse);

      // 大量控制字符 → 二进制
      final ctrl = Uint8List.fromList(List.filled(100, 0x01));
      expect(TextFileKinds.looksLikeText(ctrl), isFalse);

      // 空文件当文本
      expect(TextFileKinds.looksLikeText(Uint8List(0)), isTrue);
    });
  });

  group('编码往返', () {
    const sample = '中文测试 abc 123\n第二行：YAML 配置\n';

    test('UTF-8 往返', () {
      final bytes = TextCodecUtil.encode(sample, TextEncoding.utf8);
      expect(TextCodecUtil.decode(bytes, TextEncoding.utf8), sample);
      expect(TextCodecUtil.detect(bytes).encoding, TextEncoding.utf8);
    });

    test('GBK 往返（中文不乱码）', () {
      final bytes = TextCodecUtil.encode(sample, TextEncoding.gbk);
      final decoded = TextCodecUtil.decode(bytes, TextEncoding.gbk);
      expect(decoded, sample);
      // 检测应认出是中文编码，而不是当成 UTF-8
      final det = TextCodecUtil.detect(bytes);
      expect(det.encoding, anyOf(TextEncoding.gbk, TextEncoding.gb18030));
    });

    test('UTF-16 LE 往返（带 BOM）', () {
      final bytes = TextCodecUtil.encode(sample, TextEncoding.utf16le);
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xFE);
      expect(TextCodecUtil.decode(bytes, TextEncoding.utf16le), sample);
      expect(TextCodecUtil.detect(bytes).encoding, TextEncoding.utf16le);
    });

    test('带 BOM 的 UTF-8 应被识别且不残留 BOM 字符', () {
      final raw = utf8.encode(sample);
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...raw]);
      expect(TextCodecUtil.detect(bytes).encoding, TextEncoding.utf8);
      final text = TextCodecUtil.decode(bytes, TextEncoding.utf8);
      expect(text.startsWith('\uFEFF'), isFalse);
      expect(text, sample);
    });
  });

  group('语法高亮', () {
    const base = TextStyle(fontFamily: 'monospace', fontSize: 14);

    test('支持的语言清单', () {
      for (final lang in [
        'json', 'yaml', 'python', 'c', 'cpp', 'java', 'javascript',
        'typescript', 'xml', 'markdown', 'bash', 'sql', 'ini', 'dart', 'go',
      ]) {
        expect(CodeHighlighter.supports(lang), isTrue, reason: '$lang 应支持');
      }
      expect(CodeHighlighter.supports('不存在的语言'), isFalse);
      expect(CodeHighlighter.supports(null), isFalse);
    });

    test('高亮产出带样式的 span（关键字与字符串应有颜色）', () {
      final span = CodeHighlighter.render(
        'def hello(name):\n    return "world"  # 注释\n',
        language: 'python',
        base: base,
        theme: CodeThemes.light,
      );
      final children = <TextSpan>[];
      span.visitChildren((s) {
        if (s is TextSpan) children.add(s);
        return true;
      });
      final colored = children.where((s) => s.style?.color != null).toList();
      debugPrint('python 高亮：共 ${children.length} 段，其中带色 ${colored.length} 段');
      expect(colored, isNotEmpty, reason: '应至少有一段被着色');
    });

    test('各语言高亮都不抛异常', () {
      const samples = {
        'json': '{"a": 1, "b": [true, null]}',
        'yaml': 'key: value\nlist:\n  - a\n  - b\n',
        'java': 'public class A { public static void main(String[] a) {} }',
        'c': '#include <stdio.h>\nint main(){printf("hi");return 0;}',
        'xml': '<root><item id="1">text</item></root>',
        'bash': r'#!/bin/bash' '\n' r'for f in *.txt; do echo "$f"; done',
        'sql': 'SELECT id, name FROM users WHERE age > 18;',
        'markdown': '# 标题\n\n**粗体** 和 `代码`\n',
      };
      samples.forEach((lang, code) {
        final span = CodeHighlighter.render(
          code,
          language: lang,
          base: base,
          theme: CodeThemes.dark,
        );
        expect(span, isNotNull, reason: '$lang 高亮不应为 null');
        debugPrint('$lang 高亮 OK（${code.length} 字符）');
      });
    });

    test('未知语言退回纯文本，不抛异常', () {
      final span = CodeHighlighter.render(
        'some text',
        language: null,
        base: base,
        theme: CodeThemes.light,
      );
      expect(span.text, 'some text');
    });
  });
}
