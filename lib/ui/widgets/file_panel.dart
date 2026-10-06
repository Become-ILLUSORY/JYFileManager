// 文件面板：单个文件浏览器面板（双窗口的其中一窗）
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/models/file_item.dart';
import '../../core/models/panel_state.dart';
import '../../services/fs/local_fs.dart';
import '../widgets/file_list_tile.dart';

/// 文件浏览面板
class FilePanel extends StatefulWidget {
  const FilePanel({
    super.key,
    required this.state,
    required this.onOpenItem,
    required this.onItemLongPress,
    this.isActive = true,
    this.onActivated,
    this.dense = true,
  });

  final PanelState state;
  final void Function(FileItem item) onOpenItem;
  final void Function(FileItem item) onItemLongPress;
  final bool isActive;
  final VoidCallback? onActivated;
  final bool dense;

  @override
  State<FilePanel> createState() => FilePanelState();
}

class FilePanelState extends State<FilePanel> {
  final _scrollController = ScrollController();
  final _fs = LocalFs.instance;
  bool _loadedOnce = false;

  PanelState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_onStateChanged);
    // 首帧后加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_loadedOnce) refresh();
    });
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
      final items = await _fs.list(state.currentPath, showHidden: state.showHidden);
      state.setItems(items);
    } catch (e) {
      state.setError('$e');
    }
  }

  /// 加载指定路径
  Future<void> navigateTo(String path) async {
    state.setPath(path);
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

  @override
  Widget build(BuildContext context) {
    final s = state;

    return GestureDetector(
      onTapDown: (_) => widget.onActivated?.call(),
      behavior: HitTestBehavior.translucent,
      child: Column(
        children: [
          Expanded(
            child: s.loading && s.items.isEmpty
                ? const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: MiuixCircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : s.error != null && s.items.isEmpty
                    ? _ErrorView(message: s.error!, onRetry: refresh)
                    : s.items.isEmpty
                        ? _EmptyView(loading: s.loading)
                        : RefreshIndicator(
                            onRefresh: refresh,
                            child: ListView.builder(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 60),
                              itemCount: s.items.length,
                              itemBuilder: (context, index) {
                                final item = s.items[index];
                                return FileListTile(
                                  item: item,
                                  selected: s.selected.contains(item.path),
                                  multiSelect: s.hasSelection,
                                  dense: widget.dense,
                                  onTap: () => widget.onOpenItem(item),
                                  onLongPress: () => widget.onItemLongPress(item),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 40,
            color: colors.onSurfaceVariantSummary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            loading ? '加载中…' : '空文件夹',
            style: TextStyle(
              color: colors.onSurfaceVariantSummary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: colors.error, size: 36),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
