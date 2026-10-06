// 面板状态模型：每个浏览面板的独立状态
import 'package:flutter/foundation.dart';

import 'file_item.dart';

/// 排序字段
enum SortField {
  name,
  size,
  modified,
  type,
  permissions,
}

/// 视图模式
enum ViewMode {
  /// 紧凑列表（每行两列信息）
  compact,
  /// 详细列表
  detailed,
  /// 网格
  grid,
}

/// 单个文件面板的状态。
///
/// 双面板设计中，左右两个面板各持有一个实例，互不干扰。
class PanelState extends ChangeNotifier {
  PanelState({required this.id, String? initialPath})
      : _currentPath = initialPath ?? '/';

  /// 面板 ID（0=左，1=右）
  final int id;

  String _currentPath;
  String get currentPath => _currentPath;

  List<FileItem> _items = [];
  List<FileItem> get items => _items;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// 列表代次：每次「目录切换」自增，供面板的过渡动画做 key。
  int _revision = 0;
  int get revision => _revision;

  /// 已选中的路径集合
  final Set<String> _selected = {};
  Set<String> get selected => _selected;
  int get selectedCount => _selected.length;
  bool get hasSelection => _selected.isNotEmpty;

  /// 导航历史
  final List<String> _history = [];
  int _historyIndex = -1;
  List<String> get history => List.unmodifiable(_history);
  bool get canGoBack => _historyIndex > 0;
  bool get canGoForward => _historyIndex < _history.length - 1;

  /// 排序设置
  SortField _sortField = SortField.name;
  bool _sortAscending = true;
  bool _foldersFirst = true;
  bool _showHidden = false;

  SortField get sortField => _sortField;
  bool get sortAscending => _sortAscending;
  bool get foldersFirst => _foldersFirst;
  bool get showHidden => _showHidden;

  /// 视图模式
  ViewMode _viewMode = ViewMode.compact;
  ViewMode get viewMode => _viewMode;

  /// 目录统计（文件夹数、文件数、总大小）
  int folderCount = 0;
  int fileCount = 0;
  int totalSize = 0;

  /// 滚动位置（面板切换时保留）
  double scrollOffset = 0;

  // ============ 导航 ============

  /// 设置当前路径（记录历史）
  void setPath(String path, {bool recordHistory = true}) {
    if (path == _currentPath && _items.isNotEmpty) return;
    _currentPath = path;
    _error = null;
    _revision++;
    // 立刻清空列表并进入加载态：配合面板的 AnimatedSwitcher，
    // 切换目录时旧内容淡出、新内容淡入，不会残留上一个目录的条目。
    _items = [];
    _loading = true;
    _selected.clear();
    _recount();
    if (recordHistory) {
      // 截断前进历史
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(path);
      _historyIndex = _history.length - 1;
    }
    notifyListeners();
  }

  /// 强制刷新（路径不变但重新加载）
  void invalidate() {
    _error = null;
    notifyListeners();
  }

  bool goBack() {
    if (!canGoBack) return false;
    _historyIndex--;
    _currentPath = _history[_historyIndex];
    _error = null;
    _revision++;
    _items = [];
    _loading = true;
    _selected.clear();
    _recount();
    notifyListeners();
    return true;
  }

  bool goForward() {
    if (!canGoForward) return false;
    _historyIndex++;
    _currentPath = _history[_historyIndex];
    _error = null;
    _revision++;
    _items = [];
    _loading = true;
    _selected.clear();
    _recount();
    notifyListeners();
    return true;
  }

  // ============ 数据 ============

  void setLoading(bool value) {
    if (_loading == value) return;
    _loading = value;
    notifyListeners();
  }

  /// 记录错误。
  ///
  /// 列表必须一并清空：否则会残留上一个目录的内容，
  /// 表现为「路径已经变了，列表却还是旧目录」——例如无权限列出 `/` 时
  /// 看起来就像「一直卡在 /storage/emulated/0 回不到根目录」。
  void setError(String? message) {
    _error = message;
    _items = [];
    _selected.clear();
    _recount();
    _loading = false;
    notifyListeners();
  }

  /// 应用新的目录内容（含排序与统计）
  void setItems(List<FileItem> items) {
    _items = _sortItems(items);
    _recount();
    _loading = false;
    _error = null;
    // 清理已不存在的选中项
    final names = items.map((e) => e.path).toSet();
    _selected.removeWhere((p) => !names.contains(p));
    notifyListeners();
  }

  void _recount() {
    var folders = 0, files = 0, size = 0;
    for (final item in _items) {
      if (item.isDirectory) {
        folders++;
      } else {
        files++;
        size += item.size;
      }
    }
    folderCount = folders;
    fileCount = files;
    totalSize = size;
  }

  List<FileItem> _sortItems(List<FileItem> items) {
    final list = List<FileItem>.from(items);
    list.sort((a, b) {
      // 文件夹优先
      if (_foldersFirst && a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      int cmp;
      switch (_sortField) {
        case SortField.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortField.size:
          cmp = a.size.compareTo(b.size);
        case SortField.modified:
          cmp = a.modified.compareTo(b.modified);
        case SortField.type:
          final ea = a.isDirectory ? '' : a.extension;
          final eb = b.isDirectory ? '' : b.extension;
          cmp = ea.compareTo(eb);
          if (cmp == 0) {
            cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
        case SortField.permissions:
          cmp = (a.mode ?? 0).compareTo(b.mode ?? 0);
      }
      return _sortAscending ? cmp : -cmp;
    });
    return list;
  }

  // ============ 选择 ============

  void select(String path) {
    _selected.add(path);
    notifyListeners();
  }

  void deselect(String path) {
    _selected.remove(path);
    notifyListeners();
  }

  void toggleSelect(String path) {
    if (_selected.contains(path)) {
      _selected.remove(path);
    } else {
      _selected.add(path);
    }
    notifyListeners();
  }

  void selectAll() {
    _selected
      ..clear()
      ..addAll(_items.map((e) => e.path));
    notifyListeners();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  void invertSelection() {
    final all = _items.map((e) => e.path).toSet();
    final next = all.difference(_selected);
    _selected
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  /// 选中项对应的 FileItem 列表
  List<FileItem> get selectedItems =>
      _items.where((e) => _selected.contains(e.path)).toList();

  /// 直接替换整个选中集合（拖选时反复重算区间用，避免逐项增删）
  void setSelection(Iterable<String> paths) {
    _selected
      ..clear()
      ..addAll(paths);
    notifyListeners();
  }

  /// 按索引区间选择（用于长按后上下滑动连续选中）。
  ///
  /// [from] 与 [to] 为 [_items] 中的下标，方向无所谓。
  /// [additive] 为 false 时先清空原有选择。
  void selectRange(int from, int to, {bool additive = false}) {
    if (_items.isEmpty) return;
    final lo = from < to ? from : to;
    final hi = from < to ? to : from;
    if (!additive) _selected.clear();
    for (var i = lo; i <= hi; i++) {
      if (i >= 0 && i < _items.length) _selected.add(_items[i].path);
    }
    notifyListeners();
  }

  /// 路径在列表中的下标（不存在返回 -1）
  int indexOfPath(String path) => _items.indexWhere((e) => e.path == path);

  /// 当前目录下的单个选中项（无选中或多选返回 null）
  FileItem? get singleSelected {
    if (_selected.length != 1) return null;
    for (final item in _items) {
      if (_selected.contains(item.path)) return item;
    }
    return null;
  }

  /// 供跨面板操作使用的选中文件
  List<FileItem> get operationTargets {
    final sel = selectedItems;
    if (sel.isNotEmpty) return sel;
    return [];
  }

  // ============ 设置 ============

  void setSort(SortField field, {bool? ascending}) {
    if (_sortField == field && ascending == null) {
      // 点击同一字段切换升降序
      _sortAscending = !_sortAscending;
    } else {
      _sortField = field;
      if (ascending != null) _sortAscending = ascending;
    }
    _items = _sortItems(_items);
    notifyListeners();
  }

  void setFoldersFirst(bool value) {
    _foldersFirst = value;
    _items = _sortItems(_items);
    notifyListeners();
  }

  void setShowHidden(bool value) {
    _showHidden = value;
    notifyListeners();
  }

  void setViewMode(ViewMode mode) {
    _viewMode = mode;
    notifyListeners();
  }
}
