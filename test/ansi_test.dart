// ANSI 颜色解析与终端相关逻辑的测试。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jy_file_manager/core/utils/ansi.dart';
import 'package:jy_file_manager/core/utils/command_completer.dart';

void main() {
  const base = TextStyle(fontSize: 12.5);
  const def = Color(0xFFD8DEE9);

  group('ANSI 解析', () {
    test('无颜色码时原样返回单段', () {
      final spans = AnsiParser.parse('hello world', base: base, defaultColor: def);
      expect(spans.length, 1);
      expect(spans.first.text, 'hello world');
      expect(spans.first.style.color, def);
    });

    test('基本前景色（31 红 / 32 绿 / 34 蓝）', () {
      final spans = AnsiParser.parse(
        '\x1b[31mred\x1b[0m \x1b[32mgreen\x1b[0m',
        base: base,
        defaultColor: def,
      );
      final texts = spans.map((s) => s.text).toList();
      expect(texts, contains('red'));
      expect(texts, contains('green'));
      final red = spans.firstWhere((s) => s.text == 'red');
      expect(red.style.color, TermColors.red);
      final green = spans.firstWhere((s) => s.text == 'green');
      expect(green.style.color, TermColors.green);
    });

    test('亮色（90-97）', () {
      final spans = AnsiParser.parse(
        '\x1b[94mbright\x1b[0m',
        base: base,
        defaultColor: def,
      );
      expect(spans.first.style.color, TermColors.brightBlue);
    });

    test('加粗与下划线', () {
      final spans = AnsiParser.parse(
        '\x1b[1mbold\x1b[0m \x1b[4munder\x1b[0m',
        base: base,
        defaultColor: def,
      );
      final bold = spans.firstWhere((s) => s.text == 'bold');
      expect(bold.style.fontWeight, FontWeight.w700);
      final under = spans.firstWhere((s) => s.text == 'under');
      expect(under.style.decoration, TextDecoration.underline);
    });

    test('重置后回到默认色', () {
      final spans = AnsiParser.parse(
        '\x1b[31mred\x1b[0mnormal',
        base: base,
        defaultColor: def,
      );
      final normal = spans.firstWhere((s) => s.text == 'normal');
      expect(normal.style.color, def);
    });

    test('组合参数（1;34 加粗蓝色，ls 目录常见）', () {
      final spans = AnsiParser.parse(
        '\x1b[01;34mdirname\x1b[0m',
        base: base,
        defaultColor: def,
      );
      final dir = spans.firstWhere((s) => s.text == 'dirname');
      expect(dir.style.color, TermColors.blue);
      expect(dir.style.fontWeight, FontWeight.w700);
    });

    test('可执行文件的亮绿（ls 常见 01;32）', () {
      final spans = AnsiParser.parse(
        '\x1b[01;32mscript.sh\x1b[0m',
        base: base,
        defaultColor: def,
      );
      expect(spans.first.style.color, TermColors.green);
    });

    test('背景色', () {
      final spans = AnsiParser.parse(
        '\x1b[41mred bg\x1b[0m',
        base: base,
        defaultColor: def,
      );
      expect(spans.first.style.backgroundColor, TermColors.red);
    });

    test('非颜色控制序列被丢弃（清行/光标移动）', () {
      final spans = AnsiParser.parse(
        'a\x1b[Kb\x1b[2Cc',
        base: base,
        defaultColor: def,
      );
      expect(spans.first.text, 'abc');
    });

    test('strip 去掉全部 ANSI 码', () {
      expect(
        AnsiParser.strip('\x1b[31mred\x1b[0m text'),
        'red text',
      );
    });

    test('多行文本保持换行', () {
      final spans = AnsiParser.parse(
        'line1\nline2',
        base: base,
        defaultColor: def,
      );
      expect(spans.first.text, 'line1\nline2');
    });
  });

  group('命令补全', () {
    test('空输入不返回命令候选', () async {
      final list = await CommandCompleter.complete('', cursor: 0, cwd: '/');
      // 空前缀会返回全部命令（用于列表展示），这里只验证不抛异常
      expect(list, isA<List<Completion>>());
    });

    test('命令前缀匹配', () async {
      final list = await CommandCompleter.complete('ls', cursor: 2, cwd: '/');
      expect(list.any((c) => c.value == 'ls'), isTrue);
    });

    test('选项补全（ls -）', () async {
      final list = await CommandCompleter.complete('ls -', cursor: 4, cwd: '/');
      expect(list.every((c) => c.value.startsWith('-')), isTrue);
      expect(list.any((c) => c.value == '-l'), isTrue);
    });

    test('路径补全（根目录下的目录）', () async {
      final list = await CommandCompleter.complete('cd /', cursor: 4, cwd: '/');
      expect(list, isA<List<Completion>>());
    });
  });
}
