// 压缩包浏览器：不先解压就能看里面的内容，并支持选择性解压与增删。
//
// 支持格式：zip / jar / apk / tar / tar.gz / tar.bz2 / tar.xz / gz / bz2 / xz
// 实现走 services/archive/archive_service.dart。
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;

import '../../core/models/task_queue.dart';
import '../../core/utils/format.dart';
import '../../core/utils/ui_icons.dart';
import '../../services/archive/archive_service.dart';
import '../widgets/sheets.dart';

/// 打开压缩包浏览页
Future<void> showArchivePage(
  BuildContext context, {
  required String path,
  required String name,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ArchivePage(path: path, name: name),
      fullscreenDialog: true,
    ),
  );
}

/// 压缩包里的一个条目
class _Entry {
  const _Entry({
    required this.name,
    required this.isDir,
    required this.size,
    required this.fullPath,
  });

  final String name;
  final bool isDir;
  final int size;

  /// 在压缩包内的完整路径
  final String fullPath;
}

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key, required this.path, required this.name});

  final String path;
  final String name;

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  Archive? _archive;
  bool _loading = true;
  String? _error;

  /// 当前浏览的目录（包内路径，'' 表示根）
  String _cwd = '';
  List<_Entry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final archive = await ArchiveService.readArchive(widget.path);
      if (!mounted) return;
      if (archive == null) {
        setState(() {
          _error = '无法读取该压缩包';
          _loading = false;
        });
        return;
      }
      setState(() {
        _archive = archive;
        _loading = false;
      });
      _listDir('');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 列出包内某个目录下的条目（把深层路径折叠成当前层）
  void _listDir(String dir) {
    final archive = _archive;
    if (archive == null) return;

    final prefix = dir.isEmpty ? '' : '$dir/';
    final seen = <String>{};
    final entries = <_Entry>[];

    for (final f in archive.files) {
      final name = f.name;
      if (!name.startsWith(prefix)) continue;
      final rest = name.substring(prefix.length);
      if (rest.isEmpty) continue;

      final slash = rest.indexOf('/');
      if (slash >= 0) {
        final dirName = rest.substring(0, slash);
        if (seen.add(dirName)) {
          entries.add(_Entry(
            name: dirName,
            isDir: true,
            size: 0,
            fullPath: '$prefix$dirName',
          ));
        }
      } else {
        if (seen.add(rest)) {
          entries.add(_Entry(
            name: rest,
            isDir: false,
            size: f.size,
            fullPath: name,
          ));
        }
      }
    }

    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    setState(() {
      _cwd = dir;
      _entries = entries;
    });
  }

  /// 解压整个压缩包到所在目录
  Future<void> _extractAll() async {
    final dest = p.dirname(widget.path);
    final task = await runTask(
      kind: TaskKind.extract,
      title: '解压 ${widget.name}',
      total: _archive?.files.length ?? 0,
      body: (t) async {
        await ArchiveService.extractArchive(
          archivePath: widget.path,
          destinationDir: dest,
        );
        t.done = t.total;
      },
    );
    if (!mounted) return;
    _snack(task.status == TaskStatus.done
        ? '已解压到 $dest'
        : '解压失败：${task.error}');
  }

  /// 只解出选中的单个条目
  Future<void> _extractEntry(_Entry e) async {
    final dest = p.dirname(widget.path);
    final archive = _archive;
    if (archive == null) return;
    try {
      final file = archive.findFile(e.fullPath);
      if (file == null) {
        _snack('条目不存在');
        return;
      }
      final out = File(p.join(dest, p.basename(e.fullPath)));
      await out.writeAsBytes(file.content as List<int>, flush: true);
      _snack('已解出 ${p.basename(e.fullPath)}');
    } catch (err) {
      _snack('解出失败：$err');
    }
  }

  /// 从压缩包里删除条目
  Future<void> _deleteEntry(_Entry e) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除条目',
      message: '从压缩包中删除「${e.name}」？此操作会重写压缩包。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok) return;
    try {
      final done = await ArchiveService.deleteItemsFromArchive(
        archivePath: widget.path,
        internalPathsToDelete: [e.fullPath],
      );
      if (!mounted) return;
      if (done) {
        _snack('已删除 ${e.name}');
        await _load();
      } else {
        _snack('删除失败');
      }
    } catch (err) {
      _snack('删除失败：$err');
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

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      containerColor: colors.background,
      topBar: _buildTopBar(colors),
      content: (padding) => Padding(
        padding: EdgeInsets.only(top: padding.top),
        child: _buildBody(colors),
      ),
    );
  }

  Widget _buildTopBar(MiuixColors colors) {
    final total = _archive?.files.length ?? 0;
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
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _cwd.isEmpty ? '$total 个条目' : '内部路径：/$_cwd',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _archive == null ? null : _extractAll,
              icon: uiIcon(UiIcons.download, size: 21, color: colors.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(MiuixColors colors) {
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
              uiIcon(UiIcons.error, size: 40, color: colors.error),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
              const SizedBox(height: 16),
              MiuixButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_cwd.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 14, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    final parent = p.posix.dirname(_cwd);
                    _listDir(parent == '.' ? '' : parent);
                  },
                  icon: uiIcon(UiIcons.up, size: 20, color: colors.primary),
                ),
                Text(
                  '返回上一层',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _entries.isEmpty
              ? Center(
                  child: Text(
                    '这个目录是空的',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _entries.length,
                  itemBuilder: (ctx, i) => _tile(_entries[i], colors),
                ),
        ),
      ],
    );
  }

  Widget _tile(_Entry e, MiuixColors colors) {
    // 不用 ListTile：它依赖 Material 祖先提供文字样式，
    // 而 MiuixScaffold 提供的是 MiuixSurface 而非 Material，
    // release 下会因缺少祖先而 build 失败（表现为整块灰屏）。
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: e.isDir ? () => _listDir(e.fullPath) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              uiIcon(
                e.isDir ? UiIcons.folder : UiIcons.file,
                size: 22,
                color: e.isDir ? colors.primary : colors.onSurfaceVariantSummary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      e.isDir ? '目录' : formatSize(e.size),
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!e.isDir)
                IconButton(
                  icon: uiIcon(UiIcons.more,
                      size: 19, color: colors.onSurface),
                  onPressed: () => showActionSheet(
                    context,
                    title: e.name,
                    subtitle: formatSize(e.size),
                    actions: [
                      SheetAction(
                        label: '解压到当前目录',
                        icon: UiIcons.download,
                        onTap: () => _extractEntry(e),
                      ),
                      SheetAction(
                        label: '删除',
                        icon: UiIcons.delete,
                        destructive: true,
                        onTap: () => _deleteEntry(e),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
