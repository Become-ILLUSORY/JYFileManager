// 主界面：双面板文件管理器（Liquid Glass 设计）
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;

import '../../core/models/bookmark.dart';
import '../../core/models/file_item.dart';
import '../../core/models/mount.dart';
import '../../core/models/mount_edits.dart';
import '../../core/models/panel_state.dart';
import '../../core/models/remote_location.dart';
import '../../core/models/task_queue.dart';
import '../../core/utils/format.dart';
import '../../core/utils/text_file_kinds.dart';
import '../../core/utils/ui_icons.dart';
import '../../services/app_settings.dart';
import '../../services/archive/archive_service.dart';
import '../../services/privilege.dart';
import '../../services/remote/ftp_client.dart';
import '../../services/remote/remote_client.dart';
import '../../services/remote/sftp_client.dart';
import '../../services/remote/webdav_client.dart';
import '../../services/fs/fs_provider.dart';
import '../../services/fs/mount_aware_fs.dart';
import '../../services/fs/permissions.dart';
import '../../services/open_with.dart';
import 'privilege_settings.dart';
import 'apk_extract_page.dart';
import 'apk_info_page.dart';
import 'diff_page.dart';
import 'batch_rename_page.dart';
import 'hex_editor_page.dart';
import 'text_editor_page.dart';
import 'terminal_page.dart';
import 'remote_page.dart';
import 'tasks_page.dart';
import '../widgets/app_drawer.dart';
import '../widgets/file_panel.dart';
import '../widgets/item_menu.dart';
import '../widgets/path_bar.dart';
import '../widgets/predictive_back_card.dart';
import '../widgets/permission_dialog.dart';
import '../widgets/app_segmented.dart';
import '../widgets/compress_dialog.dart';
import '../widgets/app_switch.dart';
import '../widgets/sheets.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent, SystemNavigator;

/// 主页面：左右双面板文件浏览
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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

  /// 预测返回手势进度（0=未开始 1=已到提交点）。
  ///
  /// 用 ValueNotifier 而不是 setState：手势期间每帧都在更新，setState 会
  /// 重建整个脚手架（顶栏 + 双面板 + 列表），必然掉帧；ValueListenableBuilder
  /// 只重建 Transform 那一层。
  final ValueNotifier<double> _backProgress = ValueNotifier<double>(0);

  /// 预测返回手势是否由本页接管（决定要不要跟手位移）
  bool _backHandling = false;

  /// 上次请求退出的时间（用于「再按一次退出」的二次确认）
  DateTime? _lastExitAttempt;

  /// 松手后把位移弹回 0 的动画（提交/取消共用，避免瞬跳）
  late final AnimationController _backSettle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  late final Animation<double> _backSettleValue = Tween<double>(
    begin: 0,
    end: 1,
  ).animate(CurvedAnimation(parent: _backSettle, curve: Curves.easeOutCubic));

  /// 弹回动画的起点进度
  double _backSettleFrom = 0;

  /// 弹回动画的目标进度（提交时 1，取消时 0）
  double _backSettleTo = 0;

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
    WidgetsBinding.instance.addObserver(this);
    _backSettle.addListener(_onBackSettleTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backSettle
      ..removeListener(_onBackSettleTick)
      ..dispose();
    _backdrop.dispose();
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  // ───────────────────────── 预测返回手势 ─────────────────────────
  //
  // 单页应用在根路由上没有可弹出的 Navigator 路由，框架会调用
  // SystemNavigator.setFrameworkHandlesBack(false) 把返回手势交给
  // 观察者（见 flutter/lib/src/widgets/app.dart 对 NavigationNotification
  // 的处理）。所以我们在这里接管「返回」：
  //   1. 有选中项 → 先清空选择
  //   2. 焦点面板不在根目录 → 返回上一级目录
  //   3. 否则返回 false，交还系统播放退出应用的预测动画
  //
  // 底部弹窗与抽屉是独立路由，框架自己会声明并处理，不会走到这里。

  /// 是否有本页可以就地处理的返回动作
  bool _canHandleBack() {
    // 任何时候都接管返回：
    // 有选中 → 清选择；不在根 → 返回上级；在根 → 提示再按一次退出。
    // 若这里返回 false，系统会直接退出应用，就没有「再按一次」的机会了。
    return true;
  }

  /// 返回语义（与系统侧滑、实体返回键共用）：
  ///   1. 有选中项        → 先清空选择
  ///   2. 不在根目录      → 返回上一级目录
  ///   3. 已在根目录      → 第一次提示「再按一次退出」，第二次退出应用
  ///
  /// 返回 true 表示本次返回由本页消费掉（不交给系统）。
  bool _performBack() {
    if (_left.selected.isNotEmpty || _right.selected.isNotEmpty) {
      _left.clearSelection();
      _right.clearSelection();
      return true;
    }

    final panel = _activePanel;
    if (panel == null) return false;

    final parent = appFs.parent(_activeState.currentPath);
    if (parent != _activeState.currentPath) {
      panel.goUp();
      return true;
    }

    // 已到根目录：走「再按一次退出」逻辑
    return _handleExitRequest();
  }

  /// 到根目录后的退出确认
  ///
  /// 第一次返回 → 提示；短时间内再返回一次 → 真正退出。
  bool _handleExitRequest() {
    final now = DateTime.now();
    final last = _lastExitAttempt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      // 二次确认通过，退出应用
      SystemNavigator.pop();
      return true;
    }
    _lastExitAttempt = now;
    if (mounted) _snack('再按一次返回键退出');
    return true;
  }

  /// 手势开始：决定这次返回由谁处理，并据此跟手位移
  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final mine = _canHandleBack();
    _backHandling = mine;
    if (mine) {
      _backSettle.stop();
      _backProgress.value = backEvent.progress;
    }
    return mine;
  }

  /// 手势拖动中：按进度把内容推出去，松手前可随时拖回
  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_backHandling) return;
    _backProgress.value = backEvent.progress;
  }

  /// 松手且越过提交点：内容继续朝手势方向滑出，然后执行返回。
  ///
  /// 注意是「继续滑出」而不是「弹回」—— 系统在提交时会让界面沿手指方向
  /// 滑走并淡出，弹回原位的观感是错的。
  @override
  void handleCommitBackGesture() {
    if (!_backHandling) return;
    _animateBackTo(1.0, () {
      _performBack();
      // 新内容直接以完整尺寸出现，切换的观感交给面板自己的过渡动画
      _backProgress.value = 0;
      if (mounted) setState(() => _backHandling = false);
    }, duration: 160);
  }

  /// 松手但没越过提交点（或手势取消）：内容平滑弹回原位，不做任何事
  @override
  void handleCancelBackGesture() {
    if (!_backHandling) return;
    _animateBackTo(0.0, () {
      if (mounted) setState(() => _backHandling = false);
    }, duration: 200);
  }

  /// 实体返回键 / 三键导航：与手势语义保持一致
  ///
  /// 预测返回手势走 handleCommitBackGesture，而返回键走这里，两条路径
  /// 必须行为一致，否则同一个「返回」在两种操作下结果不同。
  @override
  Future<bool> didPopRoute() async {
    return _performBack();
  }

  /// 把跟手位移从当前进度动画到 [target]
  void _animateBackTo(double target, VoidCallback onDone,
      {required int duration}) {
    _backSettleFrom = _backProgress.value;
    _backSettleTo = target;
    _backSettle
      ..duration = Duration(milliseconds: duration)
      ..stop()
      ..value = 0
      ..forward().whenComplete(onDone);
  }

  void _onBackSettleTick() {
    if (!mounted) return;
    _backProgress.value = _backSettleFrom +
        (_backSettleTo - _backSettleFrom) * _backSettleValue.value;
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

    // 安装包：进信息页（应用名/版本/权限/组件/DEX/签名）
    if (item.name.toLowerCase().endsWith('.apk')) {
      await showApkInfoPage(context, path: item.path, name: item.name);
      return;
    }

    // 压缩包：**在该面板里打开**（挂载成一个目录），
    // 而不是弹全屏页面 —— 这样另一侧面板还能浏览本地目录，
    // 两个面板之间可以直接复制。
    if (ArchiveKinds.isArchive(item.name)) {
      await _mountArchiveInPanel(panel, item);
      return;
    }

    // 文本 / 代码文件：直接用内置编辑器打开。
    // 手机上往往没有能打开 .txt/.yaml/.py 的应用，交给系统会直接失败；
    // 内置编辑器保证这类文件点开就能看、能改。
    if (TextFileKinds.isTextByName(item.name)) {
      await showTextEditor(context, path: item.path, name: item.name);
      // 编辑器里可能改过内容，回来后刷新列表（大小/时间会变）
      await _panelOf(panel)?.refresh();
      return;
    }

    // 扩展名不认识时，嗅探前几 KB：像文本也进编辑器（.conf、无后缀配置等）
    try {
      final head = await _fs.readHead(item.path);
      if (!mounted) return;
      if (TextFileKinds.looksLikeText(head)) {
        await showTextEditor(context, path: item.path, name: item.name);
        await _panelOf(panel)?.refresh();
        return;
      }
    } catch (_) {
      // 读取失败就按原流程走系统打开
    }

    try {
      final error = await openWithSystem(item.path);
      if (error != null) _snack('无法打开该文件：$error');
    } catch (e) {
      _snack('打开失败：$e');
    }
  }

  /// 创建符号链接（指向另一面板的当前目录）
  Future<void> _createLink(int panel, List<FileItem> items) async {
    if (items.isEmpty) return;
    final dest = _otherOf(panel).currentPath;
    var ok = 0;
    for (final it in items) {
      try {
        await _fs.symlink(it.path, '$dest/${it.name}');
        ok++;
      } catch (_) {}
    }
    _panelState(panel).clearSelection();
    if (!mounted) return;
    _snack(ok > 0 ? '已创建 $ok 个链接到 ${_fs.basename(dest)}' : '创建链接失败');
    await _panelOf(panel == 0 ? 1 : 0)?.refresh();
  }

  /// 批量重命名选中项
  Future<void> _batchRename(int panel, List<FileItem> items) async {
    if (items.isEmpty) return;
    final done = await showBatchRenamePage(context, items: items);
    if (done == true) {
      _panelState(panel).clearSelection();
      if (mounted) _snack('重命名完成');
      await _panelOf(panel)?.refresh();
    }
  }

  /// 压缩选中的项目：弹格式选择后执行，走后台任务队列
  Future<void> _compressItems(int panel, List<FileItem> items) async {
    if (items.isEmpty) return;
    final s = _panelState(panel);
    final dest = s.currentPath;

    // 默认名：单个项目用它的名字，多个用当前目录名
    final defaultName = items.length == 1
        ? (items.first.isDirectory
            ? items.first.name
            : p.basenameWithoutExtension(items.first.name))
        : p.basename(dest).isEmpty
            ? 'archive'
            : p.basename(dest);

    final result = await showCompressDialog(
      context,
      defaultName: defaultName,
      count: items.length,
    );
    if (result == null) return;

    final task = await runTask(
      kind: TaskKind.compress,
      title: '压缩 ${items.length} 项',
      total: items.length,
      body: (t) async {
        await ArchiveService.createArchive(
          sourcePaths: items.map((e) => e.path).toList(),
          destinationDir: dest,
          archiveName: result.name,
          format: result.format,
          compressionLevel: result.level,
          password: result.password,
          deleteSource: result.deleteSource,
          separateArchives: false,
        );
        t.done = t.total;
      },
    );

    s.clearSelection();
    if (!mounted) return;
    _snack(task.status == TaskStatus.done
        ? '已创建 ${result.name}.${result.format}'
        : '压缩失败：${task.error}');
    await _panelOf(panel)?.refresh();
  }

  /// 解压压缩包到当前目录
  Future<void> _extractArchive(int panel, FileItem item) async {
    final dest = _panelState(panel).currentPath;
    final task = await runTask(
      kind: TaskKind.extract,
      title: '解压 ${item.name}',
      total: 1,
      body: (t) async {
        await ArchiveService.extractArchive(
          archivePath: item.path,
          destinationDir: dest,
        );
        t.done = 1;
      },
    );
    if (!mounted) return;
    _snack(task.status == TaskStatus.done
        ? '已解压到 ${p.basename(dest)}'
        : '解压失败：${task.error}');
    await _panelOf(panel)?.refresh();
  }

  /// 添加收藏：默认填当前焦点面板的路径
  Future<void> _addBookmarkDialog() async {
    final settings = AppSettings.instance;
    final path = _activeState.currentPath;
    final name = await showInputDialog(
      context,
      title: '添加收藏',
      initial: _fs.basename(path).isEmpty ? path : _fs.basename(path),
      hint: '收藏名称',
      confirmText: '添加',
    );
    if (name == null || name.isEmpty) return;
    final ok = await settings.addBookmark(name, path);
    if (!mounted) return;
    _snack(ok ? '已收藏 $name' : '该路径已在收藏中');
  }

  /// 管理某个收藏：改名 / 换图标 / 上移下移 / 删除
  Future<void> _manageBookmark(Bookmark b) async {
    final settings = AppSettings.instance;
    final items = settings.loadBookmarks();
    final index = items.indexWhere((e) => e.path == b.path);

    await showActionSheet(
      context,
      title: b.name,
      subtitle: b.path,
      actions: [
        SheetAction(
          label: '打开',
          icon: UiIcons.folderOpen,
          onTap: () => _activePanel?.navigateTo(b.path),
        ),
        SheetAction(
          label: '重命名',
          icon: UiIcons.rename,
          onTap: () async {
            final newName = await showInputDialog(
              context,
              title: '重命名收藏',
              initial: b.name,
              confirmText: '保存',
            );
            if (newName == null || newName.isEmpty) return;
            await settings.renameBookmark(b.path, newName);
            if (mounted) _snack('已重命名为 $newName');
          },
        ),
        SheetAction(
          label: '更换图标',
          icon: UiIcons.image,
          onTap: () => _pickBookmarkIcon(b),
        ),
        if (index > 0)
          SheetAction(
            label: '上移',
            icon: UiIcons.up,
            onTap: () async {
              await settings.reorderBookmark(index, index - 1);
            },
          ),
        if (index >= 0 && index < items.length - 1)
          SheetAction(
            label: '下移',
            icon: UiIcons.down,
            onTap: () async {
              await settings.reorderBookmark(index, index + 1);
            },
          ),
        SheetAction(
          label: '从收藏中移除',
          icon: UiIcons.delete,
          destructive: true,
          onTap: () async {
            final ok = await showConfirmDialog(
              context,
              title: '移除收藏',
              message: '从收藏中移除「${b.name}」？（不会删除文件）',
              confirmText: '移除',
              destructive: true,
            );
            if (!ok) return;
            await settings.removeBookmark(b.path);
            if (mounted) _snack('已移除 ${b.name}');
          },
        ),
      ],
    );
  }

  /// 选择收藏图标
  Future<void> _pickBookmarkIcon(Bookmark b) async {
    const icons = <(String, String)>[
      ('folder', '文件夹'),
      ('storage', '存储'),
      ('root', '根目录'),
      ('download', '下载'),
      ('image', '图片'),
      ('camera', '相机'),
      ('document', '文档'),
      ('music', '音乐'),
      ('video', '视频'),
      ('memory', '应用数据'),
      ('system', '系统'),
      ('star', '星标'),
    ];
    final colors = MiuixTheme.of(context).colors;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择图标'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            children: [
              for (final i in icons)
                InkWell(
                  onTap: () => Navigator.of(ctx).pop(i.$1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      uiIcon(bookmarkIcon(i.$1), size: 26, color: colors.primary),
                      const SizedBox(height: 6),
                      Text(i.$2, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await AppSettings.instance.setBookmarkIcon(b.path, picked);
    if (mounted) _snack('已更换图标');
  }

  /// 管理远程位置：重命名 / 删除
  Future<void> _manageRemote(RemoteLocation r) async {
    final store = RemoteLocationStore.instance;
    await showActionSheet(
      context,
      title: r.name,
      subtitle: r.summary,
      actions: [
        SheetAction(
          label: '连接',
          icon: UiIcons.layers,
          onTap: () => showRemotePage(context, initial: r),
        ),
        SheetAction(
          label: '重命名',
          icon: UiIcons.rename,
          onTap: () async {
            final newName = await showInputDialog(
              context,
              title: '重命名远程位置',
              initial: r.name,
              confirmText: '保存',
            );
            if (newName == null || newName.isEmpty) return;
            store.upsert(RemoteLocation(
              name: newName,
              type: r.type,
              host: r.host,
              port: r.port,
              username: r.username,
              password: r.password,
              path: r.path,
            ));
            await AppSettings.instance.saveRemoteLocations();
            if (mounted) _snack('已重命名为 $newName');
          },
        ),
        SheetAction(
          label: '删除',
          icon: UiIcons.delete,
          destructive: true,
          onTap: () async {
            final ok = await showConfirmDialog(
              context,
              title: '删除远程位置',
              message: '删除「${r.name}」的配置？（不影响服务器上的文件）',
              confirmText: '删除',
              destructive: true,
            );
            if (!ok) return;
            store.remove(r.id);
            await AppSettings.instance.saveRemoteLocations();
            if (mounted) _snack('已删除 ${r.name}');
          },
        ),
      ],
    );
  }

  /// 检查并处理挂载点的未保存改动
  ///
  /// 当用户从压缩包内返回到压缩包外时调用：
  /// 有改动 → 询问是否保存；保存则原文件加 .bak、写出新压缩包。
  Future<bool> _handleMountExit(String fromPath) async {
    final mount = MountRegistry.instance.ownerOf(fromPath);
    if (mount == null || mount.kind != MountKind.archive) return true;

    final edits = MountEditStore.instance.peek(mount.root);
    if (edits == null || edits.isEmpty) {
      MountAwareFs.instance.unmount(mount.root);
      MountEditStore.instance.drop(mount.root);
      return true;
    }

    final colors = MiuixTheme.of(context).colors;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存修改？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('在「${mount.label}」里做了 ${edits.count} 处修改。'),
            const SizedBox(height: 10),
            Text(
              '保存后：\n'
              '· 原压缩包改名为 ${mount.label}.bak（备份）\n'
              '· 生成包含修改的新压缩包',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: const Text('放弃修改'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('继续浏览'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (choice == 'cancel' || choice == null) return false;

    if (choice == 'save') {
      try {
        final archive = await MountAwareFs.instance
            .archiveOf(mount.root);
        if (archive != null) {
          await MountEditStore.saveArchive(
            archivePath: mount.sourcePath,
            base: archive,
            changes: edits.changes,
          );
          if (mounted) _snack('已保存，原文件备份为 .bak');
        }
      } catch (e) {
        if (mounted) _snack('保存失败：$e');
        return false;
      }
    }

    MountAwareFs.instance.unmount(mount.root);
    MountEditStore.instance.drop(mount.root);
    return true;
  }

  /// 把压缩包挂载到指定面板里打开
  ///
  /// 路径栏会显示成 `xxx.zip/`，内容直接在该面板列出；
  /// 另一侧面板保持原样，两个面板之间可以直接复制文件。
  Future<void> _mountArchiveInPanel(int panel, FileItem item) async {
    try {
      final root = await MountAwareFs.instance.mountArchive(
        item.path,
        item.name,
      );
      await _panelOf(panel)?.navigateTo(root);
      if (mounted) _snack('已打开 ${item.name}（返回上级即可退出）');
    } catch (e) {
      if (mounted) _snack('打开失败：$e');
    }
  }

  /// 把远程位置挂载到指定面板里打开
  Future<void> _mountRemoteInPanel(int panel, RemoteLocation r) async {
    try {
      final client = _makeRemoteClient(r);
      await client.connect();
      final root = await MountAwareFs.instance.mountRemote(
        client,
        RemoteLocationInfo(label: r.name, sourcePath: r.path),
      );
      await _panelOf(panel)?.navigateTo(root);
      if (mounted) _snack('已连接 ${r.name}（返回上级即可退出）');
    } catch (e) {
      if (mounted) _snack('连接失败：$e');
    }
  }

  RemoteClient _makeRemoteClient(RemoteLocation c) {
    switch (c.type) {
      case 'sftp':
        return SftpRemoteClient(
          host: c.host,
          port: c.port,
          username: c.username,
          password: c.password,
        );
      case 'webdav':
        return WebDavRemoteClient(
          host: c.host,
          port: c.port,
          username: c.username,
          password: c.password,
          rootPath: c.path,
        );
      default:
        return FtpRemoteClient(
          host: c.host,
          port: c.port,
          username: c.username,
          password: c.password,
        );
    }
  }

  /// 跳转到输入的路径；路径不存在时给出提示
  Future<void> _jumpToPath(String path) async {
    final panel = _activePanel;
    if (panel == null) return;
    try {
      final exists = await _fs.exists(path);
      if (!exists) {
        if (mounted) _snack('路径不存在：$path');
        return;
      }
      await panel.navigateTo(path);
    } catch (e) {
      if (mounted) _snack('跳转失败：$e');
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
        if (one && !item.isDirectory)
          MenuAction(
            label: '十六进制查看',
            icon: UiIcons.code,
            onTap: () => showHexEditor(
              context,
              path: item.path,
              name: item.name,
            ),
          ),
        if (count == 2)
          MenuAction(
            label: '对比这两个项目',
            icon: UiIcons.merge,
            onTap: () => showDiffPage(
              context,
              leftPath: targets[0].path,
              leftName: targets[0].name,
              rightPath: targets[1].path,
              rightName: targets[1].name,
            ),
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
          label: '创建链接',
          icon: UiIcons.link,
          onTap: () => _createLink(panel, targets),
        ),
        MenuAction(
          label: one ? '重命名' : '批量重命名',
          icon: UiIcons.rename,
          onTap: () => one
              ? _rename(panel, item)
              : _batchRename(panel, targets),
        ),
        MenuAction(
          label: '重命名',
          icon: UiIcons.rename,
          onTap: () => one ? _rename(panel, item) : _batchRename(panel, targets),
        ),
        MenuAction(
          label: '压缩',
          icon: UiIcons.archive,
          onTap: () => _compressItems(panel, targets),
        ),
        if (one && ArchiveKinds.isArchive(item.name))
          MenuAction(
            label: '解压到此处',
            icon: UiIcons.download,
            onTap: () => _extractArchive(panel, item),
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
          onAddBookmark: () {
            Navigator.of(ctx).pop();
            _addBookmarkDialog();
          },
          onManageBookmark: (b) {
            Navigator.of(ctx).pop();
            _manageBookmark(b);
          },
          onRestoreBookmarks: () async {
            Navigator.of(ctx).pop();
            await AppSettings.instance.restoreDefaultBookmarks();
            if (mounted) _snack('已恢复默认收藏');
          },
          onOpenRemote: (r) {
            Navigator.of(ctx).pop();
            // 直接挂载到焦点面板，另一侧仍可浏览本地目录
            _mountRemoteInPanel(_active, r);
          },
          onManageRemote: (r) {
            Navigator.of(ctx).pop();
            _manageRemote(r);
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
    switch (key) {
      case 'apkextract':
        showApkExtractPage(context);
      case 'editor':
        _snack('请先进入某个目录，点击文本文件即可编辑');
      case 'terminal':
        showTerminalPage(context);
      case 'remote':
        showRemotePage(context);
      case 'tasks':
        showTasksPage(context);
      default:
        _snack('该功能暂未开放');
    }
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

    // 跟手位移包在**整个脚手架**外面（含顶栏/底栏）：
    // 系统预测返回时是整块窗口一起平移+缩放，只动内容区会显得脱节。
    return _wrapBackGesture(
      MiuixScaffold(
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
                filter: _activeState.filter,
                onFilterChanged: (v) => _activeState.setFilter(v),
                onJumpTo: (p) => _jumpToPath(p),
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
                        onLeavingMount: _handleMountExit,
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
                        onLeavingMount: _handleMountExit,
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
      ),
    );
  }

  /// 预测返回手势的跟手位移。
  ///
  /// 根路由上我们把返回「吃掉」用于返回上级目录，系统因此不再播放自己
  /// 的退出动画，位移必须自己画（见 predictive_back_card.dart 的参数说明）。
  /// 手势期间只重建这一层（ValueListenableBuilder），不整树重建。
  Widget _wrapBackGesture(Widget child) {
    return ValueListenableBuilder<double>(
      valueListenable: _backProgress,
      builder: (context, progress, _) {
        if (!_backHandling) return child;
        return PredictiveBackCard(progress: progress, child: child);
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
          child: MiuixIcon(vector: UiIcons.sidebar, size: 22),
        ),
        actions: [
          MiuixGlassIconButton(
            onPressed: _showSettings,
            child: MiuixIcon(vector: UiIcons.settings, size: 21),
          ),
          const SizedBox(width: 8),
          MiuixGlassIconButton(
            onPressed: _showMoreMenu,
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
