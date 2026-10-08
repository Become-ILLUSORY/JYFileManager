// 文件对比页：左右并排显示两个文件的差异（文本）或两个目录的结构差异。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/diff_engine.dart';
import '../../core/utils/format.dart';
import '../../core/utils/text_codec.dart';
import '../../core/utils/ui_icons.dart';
import '../../services/fs/fs_provider.dart';
import '../widgets/app_list_tile.dart';

/// 打开对比页
Future<void> showDiffPage(
  BuildContext context, {
  required String leftPath,
  required String leftName,
  required String rightPath,
  required String rightName,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DiffPage(
        leftPath: leftPath,
        leftName: leftName,
        rightPath: rightPath,
        rightName: rightName,
      ),
      fullscreenDialog: true,
    ),
  );
}

class DiffPage extends StatefulWidget {
  const DiffPage({
    super.key,
    required this.leftPath,
    required this.leftName,
    required this.rightPath,
    required this.rightName,
  });

  final String leftPath;
  final String leftName;
  final String rightPath;
  final String rightName;

  @override
  State<DiffPage> createState() => _DiffPageState();
}

class _DiffPageState extends State<DiffPage> {
  final _fs = appFs;

  bool _loading = true;
  String? _error;

  /// 文本对比结果
  TextDiffResult? _textDiff;

  /// 目录对比结果
  List<DirDiffEntry>? _dirDiff;

  /// 只显示差异行
  bool _onlyDiff = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lStat = await _fs.stat(widget.leftPath);
      final rStat = await _fs.stat(widget.rightPath);

      if (lStat.isDirectory && rStat.isDirectory) {
        await _compareDirs();
      } else {
        await _compareText();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _compareDirs() async {
    Future<Map<String, ({int size, bool isDir})>> snapshot(String dir) async {
      final items = await _fs.list(dir);
      return {
        for (final it in items) it.name: (size: it.size, isDir: it.isDirectory),
      };
    }

    final left = await snapshot(widget.leftPath);
    final right = await snapshot(widget.rightPath);
    if (!mounted) return;
    setState(() {
      _dirDiff = DiffEngine.compareDirs(left: left, right: right);
      _loading = false;
    });
  }

  Future<void> _compareText() async {
    final lBytes = await _fs.readBytes(widget.leftPath);
    final rBytes = await _fs.readBytes(widget.rightPath);
    final lText = TextCodecUtil.decode(
      lBytes,
      TextCodecUtil.detect(lBytes).encoding,
    );
    final rText = TextCodecUtil.decode(
      rBytes,
      TextCodecUtil.detect(rBytes).encoding,
    );
    if (!mounted) return;
    setState(() {
      _textDiff = DiffEngine.compareText(lText, rText);
      _loading = false;
    });
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
    final stats = _textDiff?.stats;
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
                    '文件对比',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _summary(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                  if (stats != null && !stats.identical)
                    Text(
                      '新增 ${stats.added} · 删除 ${stats.removed} · 相同 ${stats.same}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                ],
              ),
            ),
            if (_textDiff != null)
              IconButton(
                onPressed: () => setState(() => _onlyDiff = !_onlyDiff),
                icon: uiIcon(
                  UiIcons.filter,
                  size: 20,
                  color: _onlyDiff ? colors.primary : colors.onSurface,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _summary() {
    final l = p.basename(widget.leftName);
    final r = p.basename(widget.rightName);
    return '$l  ↔  $r';
  }

  Widget _buildBody(MiuixColors colors) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: colors.error),
          ),
        ),
      );
    }
    if (_dirDiff != null) return _buildDirList(colors);
    return _buildTextDiff(colors);
  }

  // ---------- 目录对比 ----------

  Widget _buildDirList(MiuixColors colors) {
    final list = _dirDiff!;
    if (list.isEmpty) {
      return Center(
        child: Text(
          '两个目录都是空的',
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariantSummary),
        ),
      );
    }
    final visible = _onlyDiff
        ? list.where((e) => e.state != DirEntryState.both).toList()
        : list;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 60),
      itemCount: visible.length,
      itemBuilder: (ctx, i) {
        final e = visible[i];
        final (icon, color, label) = switch (e.state) {
          DirEntryState.onlyLeft => (
              UiIcons.delete,
              colors.error,
              '仅左侧',
            ),
          DirEntryState.onlyRight => (
              UiIcons.add,
              colors.primary,
              '仅右侧',
            ),
          DirEntryState.different => (
              UiIcons.edit,
              const Color(0xFFE8A33D),
              '大小不同',
            ),
          DirEntryState.both => (
              e.isDirectory ? UiIcons.folder : UiIcons.file,
              colors.onSurfaceVariantSummary,
              '相同',
            ),
        };

        return AppListTile(
          leading: uiIcon(icon, size: 21, color: color),
          title: Text(
            e.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: Text(
            [
              label,
              if (e.isDirectory) '目录' else ...[
                if (e.leftSize != null) '左 ${formatSize(e.leftSize!)}',
                if (e.rightSize != null) '右 ${formatSize(e.rightSize!)}',
              ],
            ].join(' · '),
            style: const TextStyle(fontSize: 11),
          ),
        );
      },
    );
  }

  // ---------- 文本对比 ----------

  Widget _buildTextDiff(MiuixColors colors) {
    final diff = _textDiff!;
    final visible = _onlyDiff
        ? diff.lines.where((l) => l.kind != DiffKind.same).toList()
        : diff.lines;

    if (diff.stats.identical) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            uiIcon(UiIcons.checkCircle, size: 42, color: colors.primary),
            const SizedBox(height: 14),
            Text(
              '两个文件内容完全相同',
              style: TextStyle(fontSize: 14, color: colors.onSurface),
            ),
          ],
        ),
      );
    }

    if (visible.isEmpty) {
      return Center(
        child: Text(
          '没有差异',
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariantSummary),
        ),
      );
    }

    final mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['monospace'],
      fontSize: 11.5,
      height: 1.45,
      color: colors.onSurface,
    );

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 60),
      itemCount: visible.length,
      itemBuilder: (ctx, i) {
        final line = visible[i];
        final (bg, mark) = switch (line.kind) {
          DiffKind.added => (colors.primary.withValues(alpha: 0.10), '+'),
          DiffKind.removed => (colors.error.withValues(alpha: 0.10), '-'),
          DiffKind.changed => (
              const Color(0xFFE8A33D).withValues(alpha: 0.12),
              '~'
            ),
          DiffKind.same => (Colors.transparent, ' '),
        };

        return Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 行号
              SizedBox(
                width: 34,
                child: Text(
                  '${line.leftNo ?? ''}',
                  textAlign: TextAlign.end,
                  style: mono.copyWith(
                    color: colors.onSurfaceVariantSummary,
                    fontSize: 10.5,
                  ),
                ),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '${line.rightNo ?? ''}',
                  textAlign: TextAlign.end,
                  style: mono.copyWith(
                    color: colors.onSurfaceVariantSummary,
                    fontSize: 10.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(mark, style: mono.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  line.left ?? line.right ?? '',
                  style: mono,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
