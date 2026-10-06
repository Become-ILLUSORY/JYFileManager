// 文件面板：单个浏览面板（文件列表 + 空态/错误态）
//
// 路径统一显示在顶部的 PathBar，面板内不再重复展示路径。
//
// 选择交互：
//   - 左右滑动某一行     直接切换该行选中状态
//   - 长按某一行         进入选择并选中它，按住继续上下滑动可连续选中
//                        （松手时才弹出操作菜单）
//   - 已有选中时轻点     追加/取消选择；无选中时轻点则打开
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/models/file_item.dart';
import '../../core/models/panel_state.dart';
import '../../services/fs/fs_provider.dart';
import '../../services/fs/vfs.dart';
import '../widgets/file_list_tile.dart';

/// 焦点强调线所在的外侧（左面板在左，右面板在右）
enum PanelAccentSide { left, right }

/// 文件浏览面板
class FilePanel extends StatefulWidget {
  const FilePanel({
    super.key,
    required this.state,
    required this.onOpenItem,
    required this.onItemLongPress,
    this.onItemMenu,
    this.onPermissionDenied,
    this.isActive = true,
    this.onActivated,
    this.panelIndex = 0,
    this.dense = true,
    this.autoLoad = true,
    this.accentSide = PanelAccentSide.left,
  });

  final PanelState state;
  final void Function(int panel, FileItem item) onOpenItem;

  /// 长按（含拖选结束）后请求弹出菜单，携带按下位置用于定位
  final void Function(int panel, FileItem item, Offset globalPosition)
      onItemLongPress;

  /// 行尾「更多」按钮：直接弹菜单，不进入拖选流程
  final void Function(int panel, FileItem item, Offset globalPosition)?
      onItemMenu;

  /// 访问被拒绝时回调（宿主据此弹出「无权限」提示并引导提权）
  final void Function(int panel, String path, Object error)?
      onPermissionDenied;

  final bool isActive;
  final VoidCallback? onActivated;

  /// 面板索引（0=左 1=右）。回调携带它，避免依赖“当前焦点”造成竞态。
  final int panelIndex;
  final bool dense;

  /// 是否在首次挂载后自动加载当前目录（主页面统一驱动时可关闭）
  final bool autoLoad;

  /// 焦点强调线所在的外侧
  final PanelAccentSide accentSide;

  @override
  State<FilePanel> createState() => FilePanelState();
}

class FilePanelState extends State<FilePanel>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _listKey = GlobalKey();
  final _fs = appFs;
  bool _loadedOnce = false;

  /// 目录切换时的内容过渡动画（淡入 + 轻微位移）
  late final AnimationController _navAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );
  late final Animation<double> _navFade = CurvedAnimation(
    parent: _navAnim,
    curve: Curves.easeOutCubic,
  );

  /// 已播放过渡动画的列表代次
  int _navRevision = 0;

  /// 上一次的路径（用于判断是「进入子目录」还是「返回上级」）
  String _navLastPath = '';

  /// 前进方向：true=进入更深的目录，false=返回上级
  bool _navDeeper = true;

  /// 已发出切换请求、正在等待新目录内容
  bool _navPending = false;

  /// 拖选进行中的锚点行号（长按起点）
  int? _dragAnchor;

  /// 拖选已经处理过的行号，避免来回滑动时反复翻转
  final Set<int> _dragTouched = {};

  /// 拖选是否真正发生了移动（用于区分「长按」与「长按后拖选」）
  bool _dragMoved = false;

  /// 最近一次已提示过权限不足的路径，避免重复弹窗
  String? _lastDeniedPath;

  PanelState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_onStateChanged);
    if (widget.autoLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loadedOnce) refresh();
      });
    }
  }

  @override
  void dispose() {
    state.removeListener(_onStateChanged);
    _navAnim.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    _syncNavAnimation();
    setState(() {});
  }

  /// 目录切换过渡：路径变化 → 内容从 0 起播（淡入 + 横向滑入），
  /// 新目录内容到达时若动画已结束则补播一次。
  ///
  /// 判定「加载结束」用 `!state.loading`：空目录与出错同样会结束加载，
  /// 否则动画会停在 0 导致面板一片空白。
  void _syncNavAnimation() {
    final rev = state.revision;
    if (rev != _navRevision) {
      _navRevision = rev;
      _navPending = true;
      _navDeeper = state.currentPath.length >= _navLastPath.length;
      _navLastPath = state.currentPath;
      _navAnim.value = 0;
      _navAnim.forward();
      return;
    }
    if (_navPending && !state.loading) {
      _navPending = false;
      // 加载很快时动画仍在播，直接让它继续；加载较慢时动画已结束，
      // 这里补播一次，保证「新目录内容」本身也有淡入效果。
      if (_navAnim.isCompleted) {
        _navAnim.value = 0;
        _navAnim.forward();
      }
    }
  }

  /// 重新加载当前目录
  Future<void> refresh() async {
    _loadedOnce = true;
    state.setLoading(true);
    try {
      final items = await _fs.list(
        state.currentPath,
        showHidden: state.showHidden,
      );
      state.setItems(items);
    } catch (e) {
      state.setError(_friendlyError(e));
      if (isPermissionError(e)) {
        // 只在首次遇到时提示，避免连续浏览时反复弹窗
        _maybeNotifyPermission(e);
      }
    }
  }

  /// 判断是否为权限类错误
  bool isPermissionError(Object e) {
    if (e is PermissionException) return true;
    final text = '$e';
    return text.contains('Permission denied') ||
        text.contains('EACCES') ||
        text.contains('EPERM') ||
        text.contains('Operation not permitted') ||
        text.contains('没有访问权限') ||
        text.contains('无访问权限');
  }

  /// 权限不足时通知宿主（宿主决定是否弹窗）
  void _maybeNotifyPermission(Object e) {
    final cb = widget.onPermissionDenied;
    if (cb == null) return;
    // 同一路径只提示一次
    if (_lastDeniedPath == state.currentPath) return;
    _lastDeniedPath = state.currentPath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb(widget.panelIndex, state.currentPath, e);
    });
  }

  String _friendlyError(Object e) {
    final text = '$e';
    if (isPermissionError(e)) return '没有访问权限';
    if (text.contains('PathNotFoundException') ||
        text.contains('No such file') ||
        text.contains('ENOENT')) {
      return '目录不存在';
    }
    return text;
  }

  /// 加载指定路径（[force] 为真时即使路径相同也重新加载）
  Future<void> navigateTo(String path, {bool force = false}) async {
    if (!force && path == state.currentPath) return;
    state.setPath(path);
    _loadedOnce = true;
    await refresh();
  }

  /// 返回上级。已在根目录时不做任何事。
  Future<void> goUp() async {
    final parent = _fs.parent(state.currentPath);
    if (parent == state.currentPath) return;
    await navigateTo(parent);
  }

  Future<void> goBack() async {
    if (state.goBack()) await refresh();
  }

  Future<void> goForward() async {
    if (state.goForward()) await refresh();
  }

  /// 滚动到顶部
  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  // ============ 选择交互 ============

  /// 列表行总数（含可能存在的 ".." 行）
  int get _rowCount {
    final parentPath = _fs.parent(state.currentPath);
    final showUp = parentPath != state.currentPath;
    return (showUp ? 1 : 0) + state.items.length;
  }

  /// 把全局坐标换算成列表行号；不在列表范围内返回 null
  int? _rowIndexAt(Offset global) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(global);
    if (local.dy < 0 || local.dy > box.size.height) return null;

    // 列表顶部有 2px padding，每行固定 kFileRowHeight
    final raw = (local.dy - 2) / kFileRowHeight;
    if (raw < 0) return null;
    final index = raw.floor();
    if (index >= _rowCount) return null;
    return index;
  }

  /// 行号 → 文件项（".." 行返回 null）
  FileItem? _itemAtRow(int row) {
    final parentPath = _fs.parent(state.currentPath);
    final showUp = parentPath != state.currentPath;
    final i = showUp ? row - 1 : row;
    if (i < 0 || i >= state.items.length) return null;
    return state.items[i];
  }

  /// 轻点行：选择模式下追加/取消，否则打开
  void _handleTap(FileItem item) {
    final s = state;
    if (s.hasSelection) {
      s.toggleSelect(item.path);
    } else {
      widget.onOpenItem(widget.panelIndex, item);
    }
  }

  /// 左右滑动某一行 → 切换其选中状态
  void _handleSwipe(FileItem item) {
    state.toggleSelect(item.path);
  }

  /// 长按开始：进入选择并选中起点
  void _handleLongPressStart(FileItem item, Offset global) {
    final s = state;
    if (!s.selected.contains(item.path)) {
      s.select(item.path);
    }
    _dragAnchor = _rowIndexAt(global);
    _dragTouched
      ..clear()
      ..add(_dragAnchor ?? -1);
    _dragMoved = false;
  }

  /// 长按移动：按手指所在行连续选中（锚点到当前行整段）
  void _handleLongPressMove(Offset global) {
    final row = _rowIndexAt(global);
    if (row == null) return;
    _dragMoved = true;

    final anchor = _dragAnchor ?? row;
    final lo = row < anchor ? row : anchor;
    final hi = row < anchor ? anchor : row;

    // 记录本次滑过的区间，整段选中（已选中的保持选中）
    for (var r = lo; r <= hi; r++) {
      final item = _itemAtRow(r);
      if (item == null) continue;
      if (!state.selected.contains(item.path)) {
        state.select(item.path);
      }
      _dragTouched.add(r);
    }
  }

  /// 长按结束：若期间没有拖动，视为「请求菜单」；拖动过则只保留选区。
  void _handleLongPressEnd(FileItem item, Offset global) {
    final wasDrag = _dragMoved;
    _dragAnchor = null;
    _dragTouched.clear();
    _dragMoved = false;
    if (!wasDrag) {
      widget.onItemLongPress(widget.panelIndex, item, global);
    }
  }

  void _handleLongPressCancel() {
    _dragAnchor = null;
    _dragTouched.clear();
    _dragMoved = false;
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final colors = MiuixTheme.of(context).colors;

    // 焦点面板在靠外一侧显示一条强调线（路径已统一到顶部路径栏）
    final accentOnLeft = widget.accentSide == PanelAccentSide.left;

    return Listener(
      onPointerDown: (_) => widget.onActivated?.call(),
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _navFade,
              builder: (context, child) {
                final t = _navFade.value;
                // 进入子目录从右侧滑入，返回上级从左侧滑入
                final dx = (_navDeeper ? 1 : -1) * (1 - t) * 0.06;
                return Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: FractionalTranslation(
                    translation: Offset(dx, 0),
                    child: child,
                  ),
                );
              },
              child: _buildBody(s),
            ),
          ),
          Positioned(
            top: 10,
            bottom: 10,
            left: accentOnLeft ? 0 : null,
            right: accentOnLeft ? null : 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: widget.isActive ? 1 : 0,
              child: Container(
                width: 2.5,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 列表内容。
  ///
  /// 关键约定：「..」始终作为第一行存在（只要不在根目录），
  /// 空目录 / 加载中 / 出错都只是它下方的一行状态提示 ——
  /// 这样空文件夹里也能正常返回上级。
  Widget _buildBody(PanelState s) {
    final parentPath = _fs.parent(s.currentPath);
    final showUp = parentPath != s.currentPath;
    final hasStatus = s.items.isEmpty;

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        key: _listKey,
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 2, bottom: 132),
        itemCount: (showUp ? 1 : 0) + s.items.length + (hasStatus ? 1 : 0),
        itemBuilder: (context, index) {
          var i = index;

          if (showUp && i == 0) {
            return ParentDirTile(
              parentPath: parentPath,
              onTap: goUp,
              dense: widget.dense,
            );
          }
          if (showUp) i -= 1;

          // 没有条目时，用一行状态提示占位
          if (hasStatus) {
            if (s.loading) return const _StatusRow.loading();
            if (s.error != null) {
              return _StatusRow.error(message: s.error!, onRetry: refresh);
            }
            return const _StatusRow.empty();
          }

          final item = s.items[i];
          final selected = s.selected.contains(item.path);

          return FileListTile(
            item: item,
            selected: selected,
            multiSelect: s.hasSelection,
            dense: widget.dense,
            onTap: () => _handleTap(item),
            onSwipeSelect: () => _handleSwipe(item),
            onLongPressStart: (g) => _handleLongPressStart(item, g),
            onLongPressMove: _handleLongPressMove,
            onLongPressEnd: (g) => _handleLongPressEnd(item, g),
            onLongPressCancel: _handleLongPressCancel,
            onMore: widget.onItemMenu == null
                ? null
                : () => widget.onItemMenu!(
                      widget.panelIndex,
                      item,
                      Offset.zero,
                    ),
          );
        },
      ),
    );
  }
}

/// 列表中的一行状态提示（空 / 加载中 / 出错）
class _StatusRow extends StatelessWidget {
  const _StatusRow.loading()
      : icon = Icons.hourglass_empty_rounded,
        message = '加载中…',
        onRetry = null,
        isError = false;

  const _StatusRow.empty()
      : icon = Icons.folder_open_rounded,
        message = '此文件夹为空',
        onRetry = null,
        isError = false;

  const _StatusRow.error({required this.message, required this.onRetry})
      : icon = Icons.error_outline_rounded,
        isError = true;

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
      child: Column(
        children: [
          Icon(
            icon,
            size: 34,
            color: isError
                ? colors.error
                : colors.onSurfaceVariantSummary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: colors.onSurfaceVariantSummary,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            MiuixButton(
              onPressed: onRetry,
              minWidth: 84,
              minHeight: 34,
              child: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}
