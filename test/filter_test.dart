// 过滤与路径跳转相关逻辑的测试。
import 'package:flutter_test/flutter_test.dart';

import 'package:jy_file_manager/core/models/file_item.dart';
import 'package:jy_file_manager/core/models/panel_state.dart';

FileItem _f(String name, {bool dir = false}) => FileItem(
      name: name,
      path: '/d/$name',
      isDirectory: dir,
      modified: DateTime(2026, 1, 1),
    );

PanelState _state(List<String> names) {
  final s = PanelState(id: 0, initialPath: '/d');
  s.setItems([for (final n in names) _f(n)]);
  return s;
}

void main() {
  group('过滤', () {
    test('默认无过滤，显示全部', () {
      final s = _state(['a.txt', 'b.txt', 'c.log']);
      expect(s.hasFilter, isFalse);
      expect(s.items.length, 3);
    });

    test('普通文字按名称子串匹配（不区分大小写）', () {
      final s = _state(['Readme.md', 'photo.png', 'README_old.md']);
      s.setFilter('readme');
      expect(s.items.length, 2);
      expect(s.items.every((e) => e.name.toLowerCase().contains('readme')),
          isTrue);
    });

    test('清除过滤后恢复全部', () {
      final s = _state(['a.txt', 'b.txt']);
      s.setFilter('a');
      expect(s.items.length, 1);
      s.setFilter('');
      expect(s.items.length, 2);
      expect(s.hasFilter, isFalse);
    });

    test('/正则 按正则匹配', () {
      final s = _state(['IMG_001.jpg', 'IMG_002.jpg', 'note.txt']);
      s.setFilter(r'/^IMG_\d+\.jpg$');
      expect(s.items.length, 2);
      expect(s.items.every((e) => e.name.startsWith('IMG_')), isTrue);
    });

    test('!文字 排除匹配项', () {
      final s = _state(['a.txt', 'b.log', 'c.txt']);
      s.setFilter('!.txt');
      expect(s.items.length, 1);
      expect(s.items.first.name, 'b.log');
    });

    test('!/正则 排除正则匹配项', () {
      final s = _state(['a.txt', 'b.log', 'c.md']);
      s.setFilter(r'!/\.(txt|md)$');
      expect(s.items.length, 1);
      expect(s.items.first.name, 'b.log');
    });

    test('非法正则退回子串匹配，不清空列表', () {
      final s = _state(['a(b.txt', 'c.txt']);
      s.setFilter('/a(b'); // 未闭合的括号，正则非法
      // 不应抛异常，也不应把列表清空（退化为子串匹配）
      expect(s.items.isNotEmpty, isTrue);
    });

    test('过滤后排序仍然生效', () {
      final s = _state(['c.txt', 'a.txt', 'b.txt']);
      s.setFilter('.txt');
      expect(s.items.map((e) => e.name).toList(), ['a.txt', 'b.txt', 'c.txt']);
    });

    test('切换排序时保持过滤条件', () {
      final s = _state(['b.txt', 'a.txt', 'c.log']);
      s.setFilter('.txt');
      expect(s.items.length, 2);
      s.setSort(SortField.name);
      expect(s.items.length, 2, reason: '排序不应把被过滤掉的项带回来');
    });

    test('文件夹优先设置变化时保持过滤', () {
      final s = _state(['dirA', 'a.txt', 'dirB']);
      s.setFilter('dir');
      expect(s.items.length, 2);
      s.setFoldersFirst(false);
      expect(s.items.length, 2);
    });

    test('过滤不影响选中集合（选中项仍在，只是可能不可见）', () {
      final s = _state(['a.txt', 'b.txt']);
      s.select('/d/a.txt');
      expect(s.selectedCount, 1);
      s.setFilter('b');
      expect(s.items.length, 1);
      // 选中状态保留（清理由 setItems 负责，过滤不清理）
      expect(s.selectedCount, 1);
    });

    test('重新载入列表后过滤继续生效', () {
      final s = _state(['a.txt', 'b.txt']);
      s.setFilter('a');
      expect(s.items.length, 1);
      // 模拟刷新：重新 setItems
      s.setItems([_f('a.txt'), _f('b.txt'), _f('apple.txt')]);
      expect(s.items.length, 2, reason: '过滤条件应继续生效');
    });
  });

  group('路径跳转的路径规范化（回归）', () {
    test('面板 parent 处理根目录', () {
      final s = PanelState(id: 0, initialPath: '/');
      expect(s.currentPath, '/');
    });

    test('setPath 会记录历史，可回退', () {
      final s = PanelState(id: 0, initialPath: '/a');
      s.setPath('/a/b');
      s.setPath('/a/b/c');
      expect(s.currentPath, '/a/b/c');
      expect(s.canGoBack, isTrue);

      s.goBack();
      expect(s.currentPath, '/a/b');
      s.goBack();
      expect(s.currentPath, '/a');
      // 初始路径也在历史里，回退到它之后就没有更早的了
      expect(s.canGoBack, isFalse);
    });

    test('回退后前进可用', () {
      final s = PanelState(id: 0, initialPath: '/a');
      s.setPath('/a/b');
      s.setPath('/a/b/c');
      s.goBack();
      expect(s.currentPath, '/a/b');
      expect(s.canGoForward, isTrue);
      s.goForward();
      expect(s.currentPath, '/a/b/c');
    });

    test('在历史中间跳转会截断前进历史', () {
      final s = PanelState(id: 0, initialPath: '/a');
      s.setPath('/a/b');
      s.setPath('/a/b/c');
      s.goBack(); // 回到 /a/b
      expect(s.canGoForward, isTrue);

      s.setPath('/a/x'); // 新跳转应截断 /a/b/c
      expect(s.canGoForward, isFalse);
    });
  });
}
