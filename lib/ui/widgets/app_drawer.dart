// 侧边抽屉：参照成熟文件管理器的信息架构
//
// 四个分组：本地 / 网络 / 后台 / 工具。
// 从左侧滑出，占宽约 82%，不遮挡状态栏；右侧留出遮罩可点击关闭。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/models/bookmark.dart';
import '../../core/utils/format.dart';
import '../../core/utils/ui_icons.dart';
import '../../services/app_settings.dart';
import '../../services/storage_info.dart';

/// 抽屉里的一项
class _Entry {
  const _Entry({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final dynamic icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;
}

/// 左侧抽屉
class AppDrawer extends StatefulWidget {
  const AppDrawer({
    super.key,
    required this.settings,
    required this.onOpenPath,
    required this.onOpenTool,
    required this.onOpenSettings,
  });

  final AppSettings settings;

  /// 打开某个路径（会替换焦点面板的目录）
  final ValueChanged<String> onOpenPath;

  /// 打开某个工具页（工具 key）
  final ValueChanged<String> onOpenTool;

  final VoidCallback onOpenSettings;

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final Map<String, bool> _expanded = {
    'local': true,
    'network': true,
    'background': true,
    'tools': true,
  };

  StorageUsage? _internal;
  StorageUsage? _root;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    final internal = await storageUsageOf('/storage/emulated/0');
    final root = await storageUsageOf('/');
    if (!mounted) return;
    setState(() {
      _internal = internal;
      _root = root;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final width = MediaQuery.sizeOf(context).width * 0.82;
    final padding = MediaQuery.paddingOf(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: colors.background,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: padding.top + 14),
              _header(colors),
              const SizedBox(height: 6),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
                  children: [
                    ..._localGroup(colors),
                    ..._networkGroup(colors),
                    ..._backgroundGroup(colors),
                    ..._toolsGroup(colors),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============ 头部 ============

  Widget _header(MiuixColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: uiIcon(
                UiIcons.folder,
                size: 21,
                color: colors.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'JY文件管理器',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '双面板 · Liquid Glass',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
          MiuixIconButton(
            onPressed: widget.onOpenSettings,
            child: MiuixIcon(vector: UiIcons.settings, size: 20),
          ),
        ],
      ),
    );
  }

  // ============ 分组 ============

  Widget _groupTitle(String key, String title, MiuixColors colors) {
    final open = _expanded[key] ?? true;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _expanded[key] = !open),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 8, 6),
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: open ? 0 : -0.5,
                duration: const Duration(milliseconds: 160),
                child: uiIcon(
                  UiIcons.arrowUp,
                  size: 15,
                  color: colors.onSurfaceVariantSummary
                      .withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _localGroup(MiuixColors colors) {
    final items = <_Entry>[
      _Entry(
        icon: UiIcons.storage,
        title: '内部存储',
        subtitle: '/storage/emulated/0',
        trailing: _usageText(_internal),
        onTap: () => widget.onOpenPath('/storage/emulated/0'),
      ),
      _Entry(
        icon: UiIcons.home,
        title: '根目录',
        subtitle: '/',
        trailing: _usageText(_root),
        onTap: () => widget.onOpenPath('/'),
      ),
      for (final b in BookmarkStore.builtin)
        if (b.path != '/storage/emulated/0' && b.path != '/')
          _Entry(
            icon: b.icon,
            title: b.name,
            subtitle: b.path,
            onTap: () => widget.onOpenPath(b.path),
          ),
    ];

    return [
      _groupTitle('local', '本地', colors),
      if (_expanded['local'] ?? true)
        for (final e in items) _entryTile(e, colors),
      if ((_expanded['local'] ?? true) && !_loaded)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            '正在读取存储容量…',
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurfaceVariantSummary,
            ),
          ),
        ),
    ];
  }

  List<Widget> _networkGroup(MiuixColors colors) {
    return [
      _groupTitle('network', '网络', colors),
      if (_expanded['network'] ?? true)
        _entryTile(
          _Entry(
            icon: UiIcons.layers,
            title: '添加远程位置',
            subtitle: 'FTP / SFTP / WebDAV / SMB',
            onTap: () => widget.onOpenTool('remote'),
          ),
          colors,
        ),
      if (_expanded['network'] ?? true)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
          child: Text(
            '尚未添加远程位置',
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurfaceVariantSummary.withValues(alpha: 0.75),
            ),
          ),
        ),
    ];
  }

  List<Widget> _backgroundGroup(MiuixColors colors) {
    return [
      _groupTitle('background', '后台', colors),
      if (_expanded['background'] ?? true)
        _entryTile(
          _Entry(
            icon: UiIcons.tasks,
            title: '任务队列',
            subtitle: '没有正在进行的任务',
            onTap: () => widget.onOpenTool('tasks'),
          ),
          colors,
        ),
    ];
  }

  List<Widget> _toolsGroup(MiuixColors colors) {
    final tools = <(dynamic, String, String)>[
      (UiIcons.store, '远程管理', 'remote'),
      (UiIcons.download, '安装包提取', 'apkextract'),
      (UiIcons.notes, '文本编辑器', 'editor'),
      (UiIcons.terminal, '终端模拟器', 'terminal'),
    ];
    return [
      _groupTitle('tools', '工具', colors),
      if (_expanded['tools'] ?? true)
        for (final t in tools)
          _entryTile(
            _Entry(
              icon: t.$1,
              title: t.$2,
              onTap: () => widget.onOpenTool(t.$3),
            ),
            colors,
          ),
    ];
  }

  String? _usageText(StorageUsage? u) {
    if (u == null || u.total <= 0) return null;
    return '${u.usedPercent}% · ${formatSize(u.free)} 可用';
  }

  // ============ 单项 ============

  Widget _entryTile(_Entry e, MiuixColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: e.onTap,
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Center(
                    child: uiIcon(
                      e.icon,
                      size: 19,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.2,
                          color: colors.onSurface,
                        ),
                      ),
                      if (e.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          e.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.2,
                            color: colors.onSurfaceVariantSummary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (e.trailing != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    e.trailing!,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
