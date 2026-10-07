// 文件对比引擎的测试。
import 'package:flutter_test/flutter_test.dart';

import 'package:jy_file_manager/core/utils/diff_engine.dart';

void main() {
  group('文本对比（LCS）', () {
    test('完全相同的文本', () {
      final r = DiffEngine.compareText('a\nb\nc', 'a\nb\nc');
      expect(r.stats.identical, isTrue);
      expect(r.stats.same, 3);
      expect(r.stats.added, 0);
      expect(r.stats.removed, 0);
    });

    test('新增一行', () {
      final r = DiffEngine.compareText('a\nb', 'a\nb\nc');
      expect(r.stats.added, 1);
      expect(r.stats.removed, 0);
      expect(r.stats.same, 2);
      final added = r.lines.where((l) => l.kind == DiffKind.added).toList();
      expect(added.first.right, 'c');
      expect(added.first.rightNo, 3);
    });

    test('删除一行', () {
      final r = DiffEngine.compareText('a\nb\nc', 'a\nc');
      expect(r.stats.removed, 1);
      expect(r.stats.same, 2);
      final removed = r.lines.where((l) => l.kind == DiffKind.removed).toList();
      expect(removed.first.left, 'b');
    });

    test('修改一行表现为一增一删', () {
      final r = DiffEngine.compareText('a\nOLD\nc', 'a\nNEW\nc');
      expect(r.stats.same, 2);
      expect(r.stats.added + r.stats.removed, 2);
    });

    test('行号正确', () {
      final r = DiffEngine.compareText('x\ny', 'x\nz');
      for (final l in r.lines) {
        if (l.left != null) expect(l.leftNo, isNotNull);
        if (l.right != null) expect(l.rightNo, isNotNull);
      }
    });

    test('空文本对比', () {
      expect(DiffEngine.compareText('', '').stats.identical, isTrue);
      final r = DiffEngine.compareText('', 'a\nb');
      expect(r.stats.added, 2);
    });

    test('一侧为空', () {
      final r = DiffEngine.compareText('a\nb\nc', '');
      expect(r.stats.removed, 3);
      expect(r.stats.added, 0);
    });

    test('LCS 会找到最优匹配（不是简单逐行比）', () {
      // 左侧删掉了中间一行，右侧整体上移 —— LCS 应识别为 1 删 0 增
      final r = DiffEngine.compareText('a\nb\nc\nd', 'a\nc\nd');
      expect(r.stats.removed, 1);
      expect(r.stats.added, 0);
      expect(r.stats.same, 3);
    });
  });

  group('大文件快速对比', () {
    test('超过阈值时走快速路径且不崩', () {
      final big = List.generate(DiffEngine.lcsLineLimit + 100, (i) => 'line$i').join('\n');
      final big2 = List.generate(DiffEngine.lcsLineLimit + 100, (i) => 'line$i').join('\n');
      final r = DiffEngine.compareText(big, big2);
      expect(r.stats.identical, isTrue);
    });

    test('大文件有差异时能检出', () {
      final a = List.generate(DiffEngine.lcsLineLimit + 10, (i) => 'L$i').join('\n');
      final b = List.generate(DiffEngine.lcsLineLimit + 10, (i) => i == 5 ? 'CHANGED' : 'L$i').join('\n');
      final r = DiffEngine.compareText(a, b);
      expect(r.stats.identical, isFalse);
    });
  });

  group('目录对比', () {
    test('仅左侧 / 仅右侧 / 相同 / 大小不同', () {
      final left = {
        'a.txt': (size: 100, isDir: false),
        'b.txt': (size: 200, isDir: false),
        'same.txt': (size: 50, isDir: false),
        'dir': (size: 0, isDir: true),
      };
      final right = {
        'b.txt': (size: 999, isDir: false), // 大小不同
        'same.txt': (size: 50, isDir: false), // 相同
        'c.txt': (size: 300, isDir: false), // 仅右侧
        'dir': (size: 0, isDir: true), // 目录，不比大小
      };

      final result = DiffEngine.compareDirs(left: left, right: right);
      final byName = {for (final e in result) e.name: e};

      expect(byName['a.txt']!.state, DirEntryState.onlyLeft);
      expect(byName['c.txt']!.state, DirEntryState.onlyRight);
      expect(byName['same.txt']!.state, DirEntryState.both);
      expect(byName['b.txt']!.state, DirEntryState.different);
      expect(byName['dir']!.state, DirEntryState.both,
          reason: '目录不比较大小，只要两边都有就算相同');
    });

    test('结果按名称排序', () {
      final left = {'z.txt': (size: 1, isDir: false), 'a.txt': (size: 1, isDir: false)};
      final right = <String, ({int size, bool isDir})>{};
      final result = DiffEngine.compareDirs(left: left, right: right);
      expect(result.map((e) => e.name).toList(), ['a.txt', 'z.txt']);
    });

    test('两个空目录', () {
      final result = DiffEngine.compareDirs(
        left: <String, ({int size, bool isDir})>{},
        right: <String, ({int size, bool isDir})>{},
      );
      expect(result, isEmpty);
    });
  });
}
