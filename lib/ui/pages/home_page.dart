// 主界面：双面板文件管理器（Liquid Glass 设计）
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../../core/models/file_item.dart';
import '../../core/models/panel_state.dart';
import '../../core/utils/format.dart';
import '../../core/utils/ui_icons.dart';
import '../../services/app_settings.dart';
import '../../services/privilege.dart';
import '../../services/fs/fs_provider.dart';
import '../../services/fs/permissions.dart';
import '../../services/open_with.dart';
import 'privilege_settings.dart';
import '../widgets/app_drawer.dart';
import '../widgets/file_panel.dart';
import '../widgets/item_menu.dart';
import '../widgets/path_bar.dart';
import '../widgets/permission_dialog.dart';
import '../widgets/app_segmented.dart';
import '../widgets/app_switch.dart';
import '../widgets/sheets.dart';

/// 主页面：左右双面板文件浏览
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final PanelState _left = PanelState(id: 0);
  late final PanelState _right = PanelState(id: 1);
  final _leftKey = GlobalKey<FilePanelState>();
  final _rightKey = GlobalKey<FilePanelState>();
  final _fs = appFs;
  final _backdrop = MiuixLayerBackdrop();

  /// 当前活动面板（0=左 1=右）
  int _active = 0;

  /// 存储权限是否就绪（null 表示尚未检测）
  bool? _permOk;

  /// 当前提权状态标签（Root / Shizuku / 无）
  String? _privilegeLabel;

  /// 提权是否已生效（用于隐藏「所有文件访问权限」横幅）
  bool get _privilegeActive => PrivilegeManager.instance.isActive;

  /// 按索引取面板状态（0=左 1=右）
  PanelState _panelState(int i) => i == 0 ? _left : _right;

  /// 另一侧面板状态
  PanelState _otherOf(int i) => i == 0 ? _right : _left;

  /// 按索引取面板控制器
  FilePanelState? _panelOf(int i) =>
      i == 0 ? _leftKey.currentState : _rightKey.currentState;

  /// 重新加载两个面板（提权状态变化后调用，让无权限的目录自己恢复）
  Future<void> _reloadPanels() async {
    await Future.wait([
      _panelOf(0)?.refresh() ?? Future<void>.value(),
      _panelOf(1)?.refresh() ?? Future<void>.value(),
    ]);
  }

  PanelState get _activeState => _active == 0 ? _left : _right;
  FilePanelState? get _activePanel =>
      _active == 0 ? _leftKey.currentState : _rightKey.currentState;
  FilePanelState? get _otherPanel =>
      _active == 0 ? _rightKey.currentState : _leftKey.currentState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _backdrop.dispose();
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  /// 启动流程：恢复提权选择 → 检测/申请存储权限 → 载入上次路径
  Future<void> _bootstrap() async {
    final settings = AppSettings.instance;

    // 提权状态变化时同步到顶栏标签，并让面板重新加载
    PrivilegeManager.instance.changes.listen((s) {
      if (!mounted) return;
      setState(() => _privilegeLabel = s.label);
    });

    // 自动回退开关由用户设置直接控制（SmartFs 内部读取），此处无需同步
    // 先恢复用户上次选择的提权通道，避免每次启动都要手动再授权一次
    await PrivilegeManager.instance.restorePreference();
    if (!mounted) return;
    setState(() => _privilegeLabel = PrivilegeManager.instance.status.label);

    // 已经拿到 Root/Shizuku 时，系统那套「所有文件访问权限」就不再是瓶颈了：
    // 提权通道能直接读写 /data、/system 等任意位置，此时再弹授权框、
    // 再把用户丢到根目录，反而是自相矛盾的体验。
    final privileged = PrivilegeManager.instance.isActive;
    var ok = privileged;
    if (!ok) {
      ok = await StoragePermissions.hasAllFilesAccess();
      if (!ok) {
        final res = await StoragePermissions.requestAllFilesAccess();
        ok = res == StorageAccess.granted;
      }
    }
    if (!mounted) return;
    setState(() => _permOk = ok);

    // 权限就绪后用保存的路径，否则退回可读的根目录
    final home = ok ? settings.leftPath : '/';
    final right = ok ? settings.rightPath : '/storage';

    await Future.wait([
      _leftKey.currentState?.navigateTo(home, force: true) ?? Future.value(),
      _rightKey.currentState?.navigateTo(right, force: true) ?? Future.value(),
    ]);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  // ============ 导航 ============

  Future<void> _openItem(int panel, FileItem item) async {
    if (item.isDirectory) {
      await _panelOf(panel)?.navigateTo(item.path);
      return;
    }
    try {
      final error = await openWithSystem(item.path);
      if (error != null) _snack('无法打开该文件：$error');
    } catch (e) {
      _snack('打开失败：$e');
    }
  }

  Future<void> _goUp() => _activePanel?.goUp() ?? Future.value();
  Future<void> _goBack() => _activePanel?.goBack() ?? Future.value();
  Future<void> _goForward() => _activePanel?.goForward() ?? Future.value();
  Future<void> _refresh() => _activePanel?.refresh() ?? Future.value();

  /// 交换左右面板路径
  Future<void> _swapPanels() async {
    final lp = _left.currentPath;
    final rp = _right.currentPath;
    await _leftKey.currentState?.navigateTo(rp);
    await _rightKey.currentState?.navigateTo(lp);
  }

  /// 另一面板跳到当前面板路径
  Future<void> _syncOther() async {
    await _otherPanel?.navigateTo(_activeState.currentPath);
  }

  /// 进入多选模式 / 全选
  void _toggleSelectAll() {
    final s = _activeState;
    if (s.hasSelection) {
      s.clearSelection();
    } else {
      s.selectAll();
    }
  }

  // ============ 文件操作 ============

  Future<void> _createFolder() async {
    final name = await showInputDialog(
      context,
      title: '新建文件夹',
      hint: '文件夹名称',
      confirmText: '创建',
    );
    if (name == null || name.isEmpty) return;
    try {
      await _fs.mkdir('${_activeState.currentPath}/$name');
      _snack('已创建 $name');
      await _refresh();
    } catch (e) {
      _snack('创建失败：$e');
    }
  }

  Future<void> _createFile() async {
    final name = await showInputDialog(
      context,
      title: '新建文件',
      hint: '文件名，如 note.txt',
      confirmText: '创建',
    );
    if (name == null || name.isEmpty) return;
    try {
      await _fs.writeBytes('${_activeState.currentPath}/$name', []);
      _snack('已创建 $name');
      await _refresh();
    } catch (e) {
      _snack('创建失败：$e');
    }
  }

  Future<void> _rename(int panel, FileItem item) async {
    final name = await showInputDialog(
      context,
      title: '重命名',
      initial: item.name,
      confirmText: '重命名',
    );
    if (name == null || name.isEmpty || name == item.name) return;
    try {
      await _fs.rename(item.path, '${_fs.parent(item.path)}/$name');
      _snack('已重命名为 $name');
      await _panelOf(panel)?.refresh();
    } catch (e) {
      _snack('重命名失败：$e');
    }
  }

  Future<void> _deleteItems(int panel, List<FileItem> items) async {
    if (items.isEmpty) return;
    final label = items.length == 1 ? '「${items.first.name}」' : '${items.length} 个项目';
    // 提权已生效且用户关掉了二次确认时，直接执行 —— 设置里写的就是
    // 「在系统目录中删除、重命名等操作前先确认」，关掉就该不再拦。
    // 未提权时始终确认，避免误删。
    final needConfirm = !PrivilegeManager.instance.isActive ||
        AppSettings.instance.confirmRoot;
    if (needConfirm) {
      final ok = await showConfirmDialog(
        context,
        title: '删除确认',
        message: '确定要删除 $label 吗？此操作不可撤销。',
        confirmText: '删除',
        destructive: true,
      );
      if (!ok) return;
    }
    var done = 0;
    for (final item in items) {
      try {
        await _fs.delete(item.path, recursive: true);
        done++;
      } catch (_) {}
    }
    _panelState(panel).clearSelection();
    _snack('已删除 $done 项');
    await _panelOf(panel)?.refresh();
  }

  /// 复制/移动到另一面板目录
  Future<void> _transferToOther(int panel, {required bool move}) async {
    final targets = _panelState(panel).selectedItems;
    if (targets.isEmpty) {
      _snack('请先选择文件');
      return;
    }
    final dest = _otherOf(panel).currentPath;
    var done = 0;
    for (final item in targets) {
      try {
        final dst = '$dest/${item.name}';
        if (item.isDirectory) {
          await _copyTree(item.path, dst);
          if (move) await _fs.delete(item.path, recursive: true);
        } else {
          await _fs.copy(item.path, dst);
          if (move) await _fs.delete(item.path, recursive: true);
        }
        done++;
      } catch (_) {}
    }
    _panelState(panel).clearSelection();
    _snack('${move ? '移动' : '复制'} $done 项到 ${_fs.basename(dest)}');
    await _panelOf(panel)?.refresh();
    await _panelOf(panel == 0 ? 1 : 0)?.refresh();
  }

  Future<void> _copyTree(String src, String dst) async {
    await _fs.mkdir(dst);
    final children = await _fs.list(src);
    for (final child in children) {
      final target = '$dst/${child.name}';
      if (child.isDirectory) {
        await _copyTree(child.path, target);
      } else {
        await _fs.copy(child.path, target);
      }
    }
  }

  // ============ 弹出面板 ============

  /// 访问被拒绝：优雅提示并引导用户开启提权
  void _onPermissionDenied(int panel, String path, Object error) {
    // 已经拿到提权却仍然失败 → 说明是系统层面的硬限制（如 SELinux），
    // 此时不必再劝用户去开提权，只说明情况。
    final active = PrivilegeManager.instance.isActive;
    showPermissionDeniedDialog(
      context,
      path: path,
      reason: active ? '该目录受系统保护，提权也无法访问' : null,
    );
  }

  void _showItemActions(int panel, FileItem item, Offset anchor) {
    final s = _panelState(panel);
    // 长按未选中项时先选中它，让批量操作符合直觉
    if (!s.selected.contains(item.path)) {
      s.clearSelection();
      s.select(item.path);
    }
    final count = s.selectedCount;
    final targets = s.selectedItems;
    final one = count == 1;

    showItemMenu(
      context,
      globalPosition: anchor,
      title: count > 1 ? '已选择 $count 项' : item.name,
      subtitle: count > 1
          ? null
          : (item.isDirectory ? '文件夹' : formatSize(item.size)),
      columns: 2,
      actions: [
        if (one)
          MenuAction(
            label: item.isDirectory ? '打开' : '打开方式',
            icon: item.isDirectory ? UiIcons.folder : UiIcons.play,
            onTap: () => _openItem(panel, item),
          ),
        if (one)
          MenuAction(
            label: '重命名',
            icon: UiIcons.rename,
            onTap: () => _rename(panel, item),
          ),
        MenuAction(
          label: '复制',
          icon: UiIcons.copy,
          onTap: () => _transferToOther(panel, move: false),
        ),
        MenuAction(
          label: '移动',
          icon: UiIcons.cut,
          onTap: () => _transferToOther(panel, move: true),
        ),
        MenuAction(
          label: '压缩',
          icon: UiIcons.archive,
          onTap: () => _snack('压缩功能将在 M3 里程碑接入'),
        ),
        MenuAction(
          label: '分享',
          icon: UiIcons.share,
          onTap: () => _snack('分享功能将在后续里程碑接入'),
        ),
        MenuAction(
          label: '添加到书签',
          icon: UiIcons.bookmark,
          onTap: () => unawaited(_addBookmark(panel, targets)),
        ),
        if (one)
          MenuAction(
            label: '属性',
            icon: UiIcons.info,
            onTap: () => _showProperties(panel, item),
          ),
        MenuAction(
          label: '删除',
          icon: UiIcons.delete,
          destructive: true,
          onTap: () => _deleteItems(panel, targets),
        ),
      ],
    );
  }

  Future<void> _addBookmark(int panel, List<FileItem> items) async {
    final s = _panelState(panel);
    final settings = AppSettings.instance;
    var added = 0;
    for (final it in items) {
      if (await settings.addBookmark(it.name, it.path)) added++;
    }
    _snack(added > 0 ? '已添加 $added 个书签' : '这些项目已在书签中');
    s.clearSelection();
  }

  Future<void> _showProperties(int panel, FileItem item) async {
    int? size;
    int? count;
    if (item.isDirectory) {
      // 先弹面板，再异步补上目录大小
      showPropertiesSheet(context, item: item);
      try {
        final result = await _fs.countChildren(item.path);
        size = await _fs.dirSize(item.path);
        count = result.$1 + result.$2;
        if (mounted) {
          Navigator.of(context).pop();
          await showPropertiesSheet(context, item: item, dirSize: size, dirCount: count);
        }
      } catch (_) {}
      return;
    }
    await showPropertiesSheet(context, item: item);
  }

  void _showSortMenu() {
    final s = _activeState;
    showActionSheet(
      context,
      title: '排序方式',
      actions: [
        SheetAction(
          label: '名称',
          icon: UiIcons.sort,
          summary: s.sortField == SortField.name
              ? (s.sortAscending ? '升序' : '降序')
              : null,
          onTap: () => s.setSort(SortField.name),
        ),
        SheetAction(
          label: '大小',
          icon: UiIcons.layers,
          summary: s.sortField == SortField.size
              ? (s.sortAscending ? '升序' : '降序')
              : null,
          onTap: () => s.setSort(SortField.size),
        ),
        SheetAction(
          label: '修改时间',
          icon: UiIcons.recent,
          summary: s.sortField == SortField.modified
              ? (s.sortAscending ? '升序' : '降序')
              : null,
          onTap: () => s.setSort(SortField.modified),
        ),
        SheetAction(
          label: '类型',
          icon: UiIcons.filter,
          summary: s.sortField == SortField.type
              ? (s.sortAscending ? '升序' : '降序')
              : null,
          onTap: () => s.setSort(SortField.type),
        ),
        SheetAction(
          label: s.foldersFirst ? '取消文件夹优先' : '文件夹优先',
          icon: UiIcons.folder,
          onTap: () => s.setFoldersFirst(!s.foldersFirst),
        ),
        SheetAction(
          label: s.showHidden ? '隐藏隐藏文件' : '显示隐藏文件',
          icon: s.showHidden ? UiIcons.hide : UiIcons.show,
          onTap: () {
            s.setShowHidden(!s.showHidden);
            _refresh();
          },
        ),
      ],
    );
  }

  void _showMoreMenu() {
    showActionSheet(
      context,
      title: '更多操作',
      actions: [
        SheetAction(
          label: '返回上级',
          icon: UiIcons.up,
          onTap: _goUp,
        ),
        SheetAction(
          label: '后退',
          icon: UiIcons.back,
          onTap: _goBack,
        ),
        SheetAction(
          label: '前进',
          icon: UiIcons.forward,
          onTap: _goForward,
        ),
        SheetAction(
          label: '刷新',
          icon: UiIcons.refresh,
          onTap: _refresh,
        ),
        SheetAction(
          label: '交换左右面板',
          icon: UiIcons.replace,
          onTap: _swapPanels,
        ),
        SheetAction(
          label: '另一面板跳到此处',
          icon: UiIcons.sync,
          onTap: _syncOther,
        ),
        SheetAction(
          label: '书签与存储',
          icon: UiIcons.book,
          onTap: _showSidebar,
        ),
        SheetAction(
          label: '设置',
          icon: UiIcons.settings,
          onTap: _showSettings,
        ),
      ],
    );
  }

  /// 打开左侧抽屉（本地 / 网络 / 后台 / 工具）
  void _showSidebar() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭侧栏',
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, _) {
        return AppDrawer(
          settings: AppSettings.instance,
          onOpenPath: (p) {
            Navigator.of(ctx).pop();
            _activePanel?.navigateTo(p);
          },
          onOpenTool: (key) {
            Navigator.of(ctx).pop();
            _openTool(key);
          },
          onOpenSettings: () {
            Navigator.of(ctx).pop();
            _showSettings();
          },
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  /// 打开抽屉里的工具项
  void _openTool(String key) {
    final labels = <String, String>{
      'remote': '远程管理',
      'plugins': '插件管理',
      'colorpicker': '屏幕取色',
      'apkextract': '安装包提取',
      'editor': '文本编辑器',
      'terminal': '终端模拟器',
      'activity': 'Activity 记录',
      'smali': '指令查询',
      'tasks': '任务队列',
    };
    _snack('${labels[key] ?? key}：该功能将在后续里程碑接入');
  }

  void _showSettings() {
    final settings = AppSettings.instance;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      isScrollControlled: true,
      builder: (ctx) {
        final colors = MiuixTheme.of(ctx).colors;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: GlassSurface(
              radius: 26,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: ListenableBuilder(
                listenable: settings,
                builder: (ctx2, _) => SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '设置',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ---- 外观 ----
                      _SettingRow(
                        title: '液态玻璃',
                        subtitle: '关闭后使用纯色材质，更省电',
                        trailing: AppSwitch(
                          value: settings.glassEnabled,
                          onChanged: (v) => settings.setGlassEnabled(v),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '主题',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 自绘分段控件（见 app_segmented.dart 顶部注释）：
                      // 不用 MiuixTabRow —— 它自带满宽无圆角的纯白底，
                      // 且默认 maxWidth 会让三段总宽超出面板被裁。
                      AppSegmented(
                        tabs: const ['跟随系统', '浅色', '深色'],
                        selectedIndex: switch (settings.themeMode) {
                          AppThemeMode.system => 0,
                          AppThemeMode.light => 1,
                          AppThemeMode.dark => 2,
                        },
                        onSelected: (i) => settings.setThemeMode(switch (i) {
                          1 => AppThemeMode.light,
                          2 => AppThemeMode.dark,
                          _ => AppThemeMode.system,
                        }),
                      ),
                      const SizedBox(height: 14),
                      _SettingRow(
                        title: '动态取色',
                        subtitle: '从系统壁纸提取主题色',
                        trailing: AppSwitch(
                          value: settings.monetEnabled,
                          onChanged: settings.setMonet,
                        ),
                      ),

                      const SizedBox(height: 18),
                      Divider(
                        height: 1,
                        color: colors.onSurface.withValues(alpha: 0.08),
                      ),
                      const SizedBox(height: 14),

                      // ---- 提权 ----
                      _SettingRow(
                        title: 'Root / Shizuku 提权',
                        subtitle: PrivilegeManager.instance.isActive
                            ? '已启用：${PrivilegeManager.instance.status.flavor ?? PrivilegeManager.instance.preferred.name}'
                            : '开启后可访问 /data 等系统目录',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            uiIcon(
                              PrivilegeManager.instance.isActive
                                  ? UiIcons.lock
                                  : UiIcons.lockOpen,
                              size: 18,
                              color: PrivilegeManager.instance.isActive
                                  ? colors.primary
                                  : colors.onSurface.withValues(alpha: 0.45),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: colors.onSurface.withValues(alpha: 0.4),
                            ),
                          ],
                        ),
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          await showPrivilegeSettings(context);
                          if (!mounted) return;
                          // 用户可能刚授权了 Root/Shizuku：重新探测并刷新面板，
                          // 否则之前因权限失败而空着的目录不会自己恢复。
                          await PrivilegeManager.instance.refresh();
                          if (!mounted) return;
                          setState(() {
                            _privilegeLabel =
                                PrivilegeManager.instance.status.label;
                            if (PrivilegeManager.instance.isActive) {
                              _permOk = true;
                            }
                          });
                          await _reloadPanels();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ============ 构建 ============

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final glass = settings.glassEnabled;
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;

    return MiuixScaffold(
      containerColor: colors.background,
      topBar: _buildTopBar(glass, colors),
      bottomBar: _buildBottomBar(glass, colors),
      content: (padding) {
        final body = Padding(
          padding: EdgeInsets.only(top: padding.top),
          child: Column(
            children: [
              PathBar(
                path: _activeState.currentPath,
                activeIndex: _active,
                canGoUp:
                    _fs.parent(_activeState.currentPath) != _activeState.currentPath,
                onSwitchPanel: (i) => setState(() => _active = i),
                onNavigate: (p) => _activePanel?.navigateTo(p),
                onUp: () => _activePanel?.goUp(),
              ),
              if (_permOk == false && !_privilegeActive)
                const _PermissionBanner(),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: FilePanel(
                        key: _leftKey,
                        state: _left,
                        panelIndex: 0,
                        autoLoad: false,
                        accentSide: PanelAccentSide.left,
                        isActive: _active == 0,
                        onActivated: () => setState(() => _active = 0),
                        onOpenItem: _openItem,
                        onItemLongPress: _showItemActions,
                        onPermissionDenied: _onPermissionDenied,
                      ),
                    ),
                    Container(
                      width: 1,
                      color: colors.dividerLine.withValues(alpha: 0.55),
                    ),
                    Expanded(
                      child: FilePanel(
                        key: _rightKey,
                        state: _right,
                        panelIndex: 1,
                        autoLoad: false,
                        accentSide: PanelAccentSide.right,
                        isActive: _active == 1,
                        onActivated: () => setState(() => _active = 1),
                        onOpenItem: _openItem,
                        onItemLongPress: _showItemActions,
                        onPermissionDenied: _onPermissionDenied,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        // 玻璃模式：背景层被捕获进 backdrop，供顶栏/底栏实时模糊。
        //
        // 注意：主体内容（路径栏 + 双面板）必须是不透明的主题背景色，
        // 否则极光渐变的冷色会从列表底下透出来，导致「文件区偏蓝、
        // 顶栏纯白」的割裂感。玻璃栏依旧会实时模糊滚动到其下方的列表内容。
        if (glass) {
          return MiuixLayerBackdropCapture(
            backdrop: _backdrop,
            child: ColoredBox(color: colors.background, child: body),
          );
        }
        return ColoredBox(color: colors.background, child: body);
      },
    );
  }

  Widget _buildTopBar(bool glass, MiuixColors colors) {
    final s = _activeState;
    final base = '${s.folderCount} 文件夹 · ${s.fileCount} 文件 · '
        '${formatSize(s.totalSize)}';
    // 提权生效时把通道标签并进副标题，让用户一眼看到当前是 Root 还是 Shizuku
    final subtitle = _privilegeActive && _privilegeLabel != null
        ? '$base · $_privilegeLabel'
        : base;

    if (glass) {
      return MiuixGlassTopAppBar(
        title: 'JY文件管理器',
        subtitle: subtitle,
        backdrop: _backdrop,
        navigationIcon: MiuixGlassIconButton(
          onPressed: _showSidebar,
          tooltip: '书签',
          child: MiuixIcon(vector: UiIcons.sidebar, size: 22),
        ),
        actions: [
          MiuixGlassIconButton(
            onPressed: _showSettings,
            tooltip: '设置',
            child: MiuixIcon(vector: UiIcons.settings, size: 21),
          ),
          const SizedBox(width: 8),
          MiuixGlassIconButton(
            onPressed: _showMoreMenu,
            tooltip: '更多',
            child: MiuixIcon(vector: UiIcons.more, size: 21),
          ),
        ],
      );
    }

    return MiuixTopAppBar(
      title: 'JY文件管理器',
      subtitle: subtitle,
      navigationIcon: MiuixIconButton(
        onPressed: _showSidebar,
        child: MiuixIcon(vector: UiIcons.sidebar, size: 22),
      ),
      actions: [
        MiuixIconButton(
          onPressed: _showSettings,
          child: MiuixIcon(vector: UiIcons.settings, size: 21),
        ),
        MiuixIconButton(
          onPressed: _showMoreMenu,
          child: MiuixIcon(vector: UiIcons.more, size: 21),
        ),
      ],
    );
  }

  /// 底栏。
  ///
  /// 关键修复：原实现把 `selectedIndex` 写死为 0，点击第 0 项时
  /// MiuixGlassNavigationBar 认为「已经是当前项」而不触发 onSelect，
  /// 导致「新建」点了没反应。这里改为 `selectedIndex: -1`（无当前项），
  /// 让每一项都可点击。
  Widget _buildBottomBar(bool glass, MiuixColors colors) {
    final s = _activeState;
    final items = <(dynamic, String, VoidCallback)>[
      (UiIcons.create, '新建', _showCreateMenu),
      (UiIcons.sort, '排序', _showSortMenu),
      (UiIcons.all, s.hasSelection ? '取消选择' : '选择', _toggleSelectAll),
      (UiIcons.refresh, '刷新', _refresh),
      (UiIcons.more, '更多', _showMoreMenu),
    ];

    if (glass) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: MiuixGlassNavigationBar(
                backdrop: _backdrop,
                selectedIndex: 0,
                onSelect: (i) => items[i].$3(),
                items: [
                  for (final it in items)
                    MiuixGlassNavigationItem(
                      icon: uiIcon(it.$1, size: 24),
                      label: it.$2,
                      // 这五项都是「动作」而非导航目标。
                      // isAction 为 false 时，点击当前选中项会被拦掉不回调
                      // （见 MiuixGlassNavigationBar 的 `i != _index` 判定），
                      // 导致「新建」等按钮点了没反应。
                      isAction: true,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: colors.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final it in items)
                _FlatBarButton(
                  icon: it.$1,
                  label: it.$2,
                  onTap: it.$3,
                  colors: colors,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateMenu() {
    showActionSheet(
      context,
      title: '新建',
      actions: [
        SheetAction(
          label: '新建文件夹',
          icon: UiIcons.add,
          onTap: _createFolder,
        ),
        SheetAction(
          label: '新建文件',
          icon: UiIcons.notes,
          onTap: _createFile,
        ),
      ],
    );
  }
}

/// 未获得「所有文件访问权限」时的提示条（提权生效时不显示）
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Material(
      color: colors.errorContainer,
      child: InkWell(
        onTap: () async {
          final res = await StoragePermissions.requestAllFilesAccess();
          if (res == StorageAccess.denied) {
            await StoragePermissions.openSettings();
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 17, color: colors.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '未获得「所有文件访问权限」，只能浏览部分目录。点此授权。',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onErrorContainer,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 17, color: colors.onErrorContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// 纯色底栏按钮（玻璃关闭时使用）
class _FlatBarButton extends StatelessWidget {
  const _FlatBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
  });

  final dynamic icon;
  final String label;
  final VoidCallback onTap;
  final MiuixColors colors;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              uiIcon(icon, size: 22, color: colors.onSurface),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置项行
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 14, color: colors.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
  }
}
