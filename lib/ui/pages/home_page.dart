// 主界面：双面板文件管理器（Liquid Glass 设计）
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../../core/models/file_item.dart';
import '../../core/models/panel_state.dart';
import '../../core/utils/format.dart';
import '../../services/app_settings.dart';
import '../../services/fs/local_fs.dart';
import '../widgets/file_panel.dart';

/// 主页面：左右双面板文件浏览
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final PanelState _left;
  late final PanelState _right;
  final _leftKey = GlobalKey<FilePanelState>();
  final _rightKey = GlobalKey<FilePanelState>();
  final _fs = LocalFs.instance;

  /// 当前活动面板（0=左 1=右）
  int _active = 0;

  /// Liquid Glass 背景捕获
  final _backdrop = MiuixLayerBackdrop();

  PanelState get _activeState => _active == 0 ? _left : _right;
  PanelState get _otherState => _active == 0 ? _right : _left;
  FilePanelState? get _activePanel =>
      _active == 0 ? _leftKey.currentState : _rightKey.currentState;

  @override
  void initState() {
    super.initState();
    _left = PanelState(id: 0);
    _right = PanelState(id: 1);
    _initPaths();
  }

  Future<void> _initPaths() async {
    final home = await _fs.defaultStartPath();
    _left.setPath(home);
    _right.setPath('/');
  }

  @override
  void dispose() {
    _backdrop.dispose();
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  // ============ 操作 ============

  void _openItem(FileItem item) {
    if (item.isDirectory) {
      _activePanel?.navigateTo(item.path);
    } else {
      // TODO: 文件打开方式
    }
  }

  void _showItemMenu(FileItem item) {
    // TODO: 长按菜单
  }

  Future<void> _goUp() async {
    await _activePanel?.goUp();
  }

  Future<void> _goBack() async {
    await _activePanel?.goBack();
  }

  Future<void> _goForward() async {
    await _activePanel?.goForward();
  }

  /// 交换左右面板路径
  void _swapPanels() {
    final lp = _left.currentPath;
    final rp = _right.currentPath;
    _left.setPath(rp);
    _right.setPath(lp);
    _leftKey.currentState?.refresh();
    _rightKey.currentState?.refresh();
  }

  /// 同步：另一窗口跳到当前窗口路径
  void _syncOther() {
    _otherState.setPath(_activeState.currentPath);
    if (_active == 0) {
      _rightKey.currentState?.refresh();
    } else {
      _leftKey.currentState?.refresh();
    }
  }

  // ============ 构建 ============

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final glass = settings.glassEnabled;
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;

    final body = Column(
      children: [
        // 面板统计条
        _StatsBar(
          left: _left,
          right: _right,
          active: _active,
          onSwitch: (i) => setState(() => _active = i),
        ),
        // 双面板
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: FilePanel(
                  key: _leftKey,
                  state: _left,
                  isActive: _active == 0,
                  onActivated: () => setState(() => _active = 0),
                  onOpenItem: _openItem,
                  onItemLongPress: _showItemMenu,
                ),
              ),
              // 中间分隔线
              Container(
                width: 1,
                color: colors.dividerLine.withValues(alpha: 0.6),
              ),
              Expanded(
                child: FilePanel(
                  key: _rightKey,
                  state: _right,
                  isActive: _active == 1,
                  onActivated: () => setState(() => _active = 1),
                  onOpenItem: _openItem,
                  onItemLongPress: _showItemMenu,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return MiuixScaffold(
      topBar: _buildTopBar(glass, colors),
      bottomBar: _BottomToolbar(
        glass: glass,
        onBack: _goBack,
        onForward: _goForward,
        onUp: _goUp,
        onSwap: _swapPanels,
        onSync: _syncOther,
        onNew: _showCreateMenu,
      ),
      content: (padding) {
        final content = Padding(
          padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
          child: body,
        );
        // 玻璃模式：捕获背景供顶/底栏采样
        if (glass) {
          return MiuixLayerBackdropCapture(
            backdrop: _backdrop,
            child: content,
          );
        }
        return content;
      },
    );
  }

  Widget _buildTopBar(bool glass, MiuixColors colors) {
    final s = _activeState;
    final subtitle = '文件夹: ${s.folderCount}  文件: ${s.fileCount}  '
        '储存: ${formatSize(s.totalSize)}';

    if (glass) {
      return MiuixGlassTopAppBar(
        title: s.currentPath,
        subtitle: subtitle,
        backdrop: _backdrop,
        navigationIcon: MiuixIconButton(
          onPressed: _showSidebar,
          child: const Icon(Icons.menu_rounded, size: 22),
        ),
        actions: [
          MiuixIconButton(
            onPressed: _showTopMenu,
            child: const Icon(Icons.more_vert_rounded, size: 22),
          ),
        ],
      );
    }

    // 非玻璃模式：普通顶栏
    return MiuixTopAppBar(
      title: s.currentPath,
      subtitle: subtitle,
      navigationIcon: MiuixIconButton(
        onPressed: _showSidebar,
        child: const Icon(Icons.menu_rounded, size: 22),
      ),
      actions: [
        MiuixIconButton(
          onPressed: _showTopMenu,
          child: const Icon(Icons.more_vert_rounded, size: 22),
        ),
      ],
    );
  }

  void _showSidebar() {
    // TODO: 侧边栏（书签、存储、根目录）
  }

  void _showTopMenu() {
    // TODO: 顶部菜单
  }

  void _showCreateMenu() {
    // TODO: 新建菜单
  }
}

/// 面板统计条：显示两个面板的路径切换
class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.left,
    required this.right,
    required this.active,
    required this.onSwitch,
  });

  final PanelState left;
  final PanelState right;
  final int active;
  final ValueChanged<int> onSwitch;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Container(
      height: 30,
      color: colors.surfaceContainer,
      child: Row(
        children: [
          Expanded(
            child: _tab(context, 'A', 0, left.currentPath),
          ),
          Container(width: 1, color: colors.dividerLine.withValues(alpha: 0.4)),
          Expanded(
            child: _tab(context, 'B', 1, right.currentPath),
          ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, String label, int index, String path) {
    final colors = MiuixTheme.of(context).colors;
    final selected = active == index;
    return InkWell(
      onTap: () => onSwitch(index),
      child: Container(
        alignment: Alignment.center,
        color: selected
            ? colors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? colors.primary : colors.onSurfaceVariantSummary,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: selected
                      ? colors.primary
                      : colors.onSurfaceVariantSummary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部工具栏
class _BottomToolbar extends StatelessWidget {
  const _BottomToolbar({
    required this.glass,
    required this.onBack,
    required this.onForward,
    required this.onUp,
    required this.onSwap,
    required this.onSync,
    required this.onNew,
  });

  final bool glass;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onUp;
  final VoidCallback onSwap;
  final VoidCallback onSync;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final buttons = <Widget>[
      _btn(context, Icons.arrow_back_rounded, '返回', onBack),
      _btn(context, Icons.arrow_forward_rounded, '前进', onForward),
      _btn(context, Icons.add_rounded, '新建', onNew),
      _btn(context, Icons.swap_horiz_rounded, '交换', onSwap),
      _btn(context, Icons.arrow_upward_rounded, '上级', onUp),
      _btn(context, Icons.sync_rounded, '同步', onSync),
    ];

    final bar = SafeArea(
      top: false,
      child: SizedBox(
        height: 52,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: buttons,
        ),
      ),
    );

    if (glass) {
      // 玻璃材质底栏
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainer.withValues(alpha: 0.55),
              border: Border(
                top: BorderSide(
                  color: colors.dividerLine.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: bar,
          ),
        ),
      );
    }

    return Container(
      color: colors.surfaceContainer,
      child: bar,
    );
  }

  Widget _btn(BuildContext context, IconData icon, String tip, VoidCallback onTap) {
    final colors = MiuixTheme.of(context).colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Icon(icon, size: 22, color: colors.onSurface),
      ),
    );
  }
}
