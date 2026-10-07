// 安装包提取：扫描设备上的 APK、查看信息、导出到指定目录。
//
// 两个数据来源：
//   1. 已安装应用（PackageManager，能拿到应用名与图标）
//   2. 指定目录下的 .apk 文件（纯 Dart 解析，无需系统 API）
//
// 导出即把 sourceDir 上的 APK 复制到目标目录（多 APK 拆分包一并复制）。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/format.dart';
import '../../core/utils/ui_icons.dart';
import '../../services/apk_installer_service.dart';
import '../../services/apk_parser.dart';
import '../../services/app_manager_service.dart';
import '../../services/fs/fs_provider.dart';
import '../widgets/sheets.dart';

/// 打开安装包提取页
Future<void> showApkExtractPage(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const ApkExtractPage(),
      fullscreenDialog: true,
    ),
  );
}

/// 列表项的统一模型（已安装应用 / 目录里的 APK）
class _Entry {
  _Entry({
    required this.title,
    required this.subtitle,
    required this.path,
    this.packageName,
    this.version,
    this.size = 0,
    this.isSystem = false,
    this.splitPaths = const [],
  });

  final String title;
  final String subtitle;
  final String path;
  final String? packageName;
  final String? version;
  final int size;
  final bool isSystem;
  Uint8List? iconBytes;
  final List<String> splitPaths;
}

class ApkExtractPage extends StatefulWidget {
  const ApkExtractPage({super.key});

  @override
  State<ApkExtractPage> createState() => _ApkExtractPageState();
}

class _ApkExtractPageState extends State<ApkExtractPage> {
  final _fs = appFs;

  /// 0=已安装应用 1=目录扫描
  int _tab = 0;

  bool _loading = true;
  String? _error;
  List<_Entry> _apps = [];
  List<_Entry> _files = [];

  /// 目录扫描的当前目录
  String _scanDir = '/storage/emulated/0';

  bool _includeSystem = false;
  final _searchCtl = TextEditingController();
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(() {
      setState(() => _keyword = _searchCtl.text.trim());
    });
    _loadApps();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await AppManagerService.getInstalledApps(
        includeSystem: _includeSystem,
      );
      final entries = [
        for (final a in list)
          _Entry(
            title: a.name.isEmpty ? a.packageName : a.name,
            subtitle: a.packageName,
            path: a.sourceDir,
            packageName: a.packageName,
            version: a.version,
            size: a.apkSize,
            isSystem: a.isSystem,
            splitPaths: a.splitSourceDirs,
          ),
      ];
      if (!mounted) return;
      setState(() {
        _apps = entries;
        _loading = false;
      });
      _loadIcons(entries);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '读取应用列表失败：$e';
        _loading = false;
      });
    }
  }

  /// 图标异步补上（不阻塞列表显示）
  Future<void> _loadIcons(List<_Entry> entries) async {
    for (final e in entries) {
      if (!mounted) return;
      if (e.packageName == null) continue;
      try {
        final icon = await AppManagerService.getAppIcon(e.packageName!);
        if (icon == null || !mounted) continue;
        setState(() => e.iconBytes = icon);
      } catch (_) {}
    }
  }

  /// 扫描目录下的 APK 文件
  Future<void> _doScan() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _fs.list(_scanDir);
      final entries = <_Entry>[];
      for (final it in items) {
        if (it.isDirectory) continue;
        if (!ApkInstallerService.isApk(it.path)) continue;
        entries.add(
          _Entry(
            title: it.name,
            subtitle: formatSize(it.size),
            path: it.path,
            size: it.size,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _files = entries;
        _loading = false;
      });
      _parseFileInfo(entries);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '扫描失败：$e';
        _loading = false;
      });
    }
  }

  /// 解析 APK 内的应用名/图标（纯 Dart）
  Future<void> _parseFileInfo(List<_Entry> entries) async {
    for (final e in entries) {
      if (!mounted) return;
      try {
        final bytes = await _fs.readBytes(e.path);
        final info = await ApkParser.parse(bytes);
        if (info == null || !mounted) continue;
        setState(() {
          e.iconBytes = info.iconPng;
        });
      } catch (_) {}
    }
  }

  /// 导出 APK 到下载目录
  Future<void> _export(_Entry e) async {
    try {
      final dir = await getExternalStorageDirectory();
      final base = dir?.path ?? (await getTemporaryDirectory()).path;
      final outDir = Directory(p.join(base, 'apk_export'));
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      final src = File(e.path);
      if (!src.existsSync()) {
        _snack('源文件不存在：${e.path}');
        return;
      }
      final dst = p.join(outDir.path, p.basename(e.path));
      await src.copy(dst);

      // 拆分包（split APKs）一并导出
      var extra = 0;
      for (final sp in e.splitPaths) {
        final f = File(sp);
        if (!f.existsSync()) continue;
        await f.copy(p.join(outDir.path, p.basename(sp)));
        extra++;
      }

      _snack('已导出到 ${outDir.path}${extra > 0 ? '（含 $extra 个拆分包）' : ''}');
    } catch (err) {
      _snack('导出失败：$err');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800),
      ),
    );
  }

  List<_Entry> get _visible {
    final src = _tab == 0 ? _apps : _files;
    if (_keyword.isEmpty) return src;
    final k = _keyword.toLowerCase();
    return src
        .where((e) =>
            e.title.toLowerCase().contains(k) ||
            (e.packageName?.toLowerCase().contains(k) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;

    return MiuixScaffold(
      containerColor: colors.background,
      topBar: _buildTopBar(colors),
      content: (padding) => Padding(
        padding: EdgeInsets.only(top: padding.top),
        child: Column(
          children: [
            _buildTabs(colors),
            _buildSearchBar(colors),
            if (_tab == 1) _buildDirBar(colors),
            Expanded(child: _buildList(colors)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(MiuixColors colors) {
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: uiIcon(UiIcons.back, size: 22, color: colors.onSurface),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '安装包提取',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _tab == 0
                        ? '共 ${_apps.length} 个应用'
                        : '共 ${_files.length} 个安装包',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
            if (_tab == 0)
              IconButton(
                tooltip: _includeSystem ? '隐藏系统应用' : '显示系统应用',
                onPressed: () {
                  setState(() => _includeSystem = !_includeSystem);
                  _loadApps();
                },
                icon: uiIcon(
                  _includeSystem ? UiIcons.show : UiIcons.hide,
                  size: 21,
                  color: colors.onSurface,
                ),
              ),
            IconButton(
              tooltip: '刷新',
              onPressed: _tab == 0 ? _loadApps : _doScan,
              icon: uiIcon(UiIcons.refresh, size: 21, color: colors.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs(MiuixColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _tab = i);
                  if (i == 1 && _files.isEmpty) _doScan();
                },
                child: Container(
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _tab == i
                        ? colors.primary
                        : colors.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: Text(
                    i == 0 ? '已安装应用' : '扫描目录',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          _tab == i ? FontWeight.w600 : FontWeight.w400,
                      color: _tab == i
                          ? colors.onPrimary
                          : colors.onSurfaceVariantSummary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar(MiuixColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: TextField(
        controller: _searchCtl,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: '搜索应用名或包名',
          hintStyle: const TextStyle(fontSize: 13),
          isDense: true,
          prefixIcon: Padding(
            padding: const EdgeInsets.all(10),
            child: uiIcon(UiIcons.search,
                size: 18, color: colors.onSurfaceVariantSummary),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 40),
          filled: true,
          fillColor: colors.onSurface.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildDirBar(MiuixColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _scanDir,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          MiuixButton(
            onPressed: () => _pickDir(),
            minWidth: 66,
            minHeight: 34,
            child: const Text('选择目录'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDir() async {
    // 用内置的简单目录选择：列出子目录让用户逐层进入
    final picked = await _showDirPicker(_scanDir);
    if (picked == null || picked == _scanDir) return;
    setState(() => _scanDir = picked);
    await _doScan();
  }

  Future<String?> _showDirPicker(String start) async {
    var current = start;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final colors = MiuixTheme.of(ctx).colors;
          return AlertDialog(
            title: const Text('选择目录'),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: FutureBuilder(
                future: _fs.list(current),
                builder: (ctx2, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final dirs =
                      snap.data!.where((e) => e.isDirectory).toList();
                  return ListView(
                    children: [
                      ListTile(
                        dense: true,
                        leading: uiIcon(UiIcons.up,
                            size: 20, color: colors.primary),
                        title: Text('上级：${_fs.parent(current)}',
                            style: const TextStyle(fontSize: 12.5)),
                        onTap: () {
                          final up = _fs.parent(current);
                          if (up != current) setLocal(() => current = up);
                        },
                      ),
                      for (final d in dirs)
                        ListTile(
                          dense: true,
                          leading: uiIcon(UiIcons.folder,
                              size: 20, color: colors.primary),
                          title: Text(d.name,
                              style: const TextStyle(fontSize: 13)),
                          onTap: () =>
                              setLocal(() => current = d.path),
                        ),
                    ],
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(current),
                child: const Text('选择此目录'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(MiuixColors colors) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              uiIcon(UiIcons.error, size: 38, color: colors.error),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final list = _visible;
    if (list.isEmpty) {
      return Center(
        child: Text(
          _tab == 0 ? '没有找到应用' : '该目录下没有安装包',
          style: TextStyle(
            fontSize: 13,
            color: colors.onSurfaceVariantSummary,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: list.length,
      itemBuilder: (ctx, i) => _tile(list[i], colors),
    );
  }

  Widget _tile(_Entry e, MiuixColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showActions(e),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: Row(
              children: [
                _iconBox(e, colors),
                const SizedBox(width: 12),
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
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (e.packageName != null) e.packageName!,
                          if (e.version != null && e.version!.isNotEmpty)
                            'v${e.version}',
                          if (e.size > 0) formatSize(e.size),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: colors.onSurfaceVariantSummary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (e.isSystem)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '系统',
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBox(_Entry e, MiuixColors colors) {
    const size = 44.0;
    if (e.iconBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image.memory(
          e.iconBytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _fallbackIcon(colors, size),
        ),
      );
    }
    return _fallbackIcon(colors, size);
  }

  Widget _fallbackIcon(MiuixColors colors, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Center(
        child: uiIcon(UiIcons.archive, size: 21, color: colors.primary),
      ),
    );
  }

  void _showActions(_Entry e) {
    showActionSheet(
      context,
      title: e.title,
      subtitle: e.packageName ?? e.path,
      actions: [
        if (e.packageName != null)
          SheetAction(
            label: '启动应用',
            icon: UiIcons.play,
            onTap: () async {
              final ok = await AppManagerService.launchApp(e.packageName!);
              if (!ok) _snack('无法启动该应用');
            },
          ),
        SheetAction(
          label: '导出安装包',
          icon: UiIcons.download,
          onTap: () => _export(e),
        ),
        if (e.packageName != null)
          SheetAction(
            label: '应用详情',
            icon: UiIcons.info,
            onTap: () async {
              await AppManagerService.openAppDetails(e.packageName!);
            },
          ),
        SheetAction(
          label: '复制路径',
          icon: UiIcons.copy,
          onTap: () => _snack(e.path),
        ),
      ],
    );
  }
}
