// 文件面板：单个浏览面板（文件列表 + 空态/错误态）
//
// 路径统一显示在顶部的 PathBar，面板内不再重复展示路径。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/models/file_item.dart';
import '../../core/models/panel_state.dart';
import '../../services/fs/fs_provider.dart';
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
    this.isActive = true,
    this.onActivated,
    this.panelIndex = 0,
    this.dense = true,
    this.autoLoad = true,
    this.accentSide = PanelAccentSide.left,
  });

  final PanelState state;
  final void Function(int panel, FileItem item) onOpenItem;
  final void Function(int panel, FileItem item) onItemLongPress;
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

class FilePanelState extends State<FilePanel> {
  final _scrollController = ScrollController();
  final _fs = appFs;
  bool _loadedOnce = false;

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
    _scrollController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
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
    }
  }

  String _friendlyError(Object e) {
    final text = '$e';
    if (text.contains('PathNotFoundException') ||
        text.contains('No such file') ||
        text.contains('ENOENT')) {
      return '目录不存在或无访问权限';
    }
    if (text.contains('Permission denied') || text.contains('EACCES')) {
      return '没有访问权限';
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

  /// 返回上级
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
          Positioned.fill(child: _buildBody(s)),
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

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 2, bottom: 104),
        itemCount: (showUp ? 1 : 0) + s.items.length + (s.items.isEmpty ? 1 : 0),
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
          if (s.items.isEmpty) {
            if (s.loading) return const _StatusRow.loading();
            if (s.error != null) {
              return _StatusRow.error(message: s.error!, onRetry: refresh);
            }
            return const _StatusRow.empty();
          }

          final item = s.items[i];
          return FileListTile(
            item: item,
            selected: s.selected.contains(item.path),
            multiSelect: s.hasSelection,
            dense: widget.dense,
            onTap: () {
              if (s.hasSelection && !s.selected.contains(item.path)) {
                s.toggleSelect(item.path);
              } else {
                widget.onOpenItem(widget.panelIndex, item);
              }
            },
            onLongPress: () => widget.onItemLongPress(widget.panelIndex, item),
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
