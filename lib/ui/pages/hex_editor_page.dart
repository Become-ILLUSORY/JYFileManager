// Hex 编辑器：以十六进制查看与编辑文件。
//
// 适用场景：看二进制文件头、改几个字节、确认文件是否损坏。
// 性能：只把**当前可见区域**的字节读进内存并渲染，
// 因此打开几百 MB 的文件也不会卡（配合 Vfs.openRead 的区间读取）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/utils/format.dart';
import '../../core/utils/ui_icons.dart';
import '../../services/fs/fs_provider.dart';

/// 每行显示的字节数（16 是通用惯例）
const int kHexBytesPerLine = 16;

/// 打开 Hex 编辑器
Future<void> showHexEditor(
  BuildContext context, {
  required String path,
  required String name,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HexEditorPage(path: path, name: name),
      fullscreenDialog: true,
    ),
  );
}

class HexEditorPage extends StatefulWidget {
  const HexEditorPage({super.key, required this.path, required this.name});

  final String path;
  final String name;

  @override
  State<HexEditorPage> createState() => _HexEditorPageState();
}

class _HexEditorPageState extends State<HexEditorPage> {
  final _scroll = ScrollController();
  final _fs = appFs;

  int _fileSize = 0;
  bool _loading = true;
  String? _error;

  /// 已加载的字节（按行缓存，只保留可见窗口）
  Uint8List _window = Uint8List(0);

  /// 窗口起始偏移
  int _windowStart = 0;

  /// 每行高度（固定，便于按滚动位置反算行号）
  static const double _rowHeight = 20;

  /// 是否处于编辑模式（编辑时会缓存整块数据，仅对小文件开放）
  bool _editing = false;

  /// 跳转输入
  final _gotoCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _gotoCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stat = await _fs.stat(widget.path);
      _fileSize = stat.size;
      // 小文件直接全读，方便编辑
      if (_fileSize <= 512 * 1024) {
        _window = await _fs.readBytes(widget.path);
        _windowStart = 0;
      } else {
        await _loadWindow(0);
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 加载指定偏移开始的窗口
  Future<void> _loadWindow(int start) async {
    const windowBytes = 64 * 1024;
    final end = (start + windowBytes).clamp(0, _fileSize);
    final chunks = <int>[];
    await for (final chunk in _fs.openRead(widget.path, start: start, end: end)) {
      chunks.addAll(chunk);
    }
    _window = Uint8List.fromList(chunks);
    _windowStart = start;
  }

  void _onScroll() {
    if (_fileSize <= 512 * 1024) return; // 全量加载模式不用换窗
    final firstRow = (_scroll.offset / _rowHeight).floor();
    final byteOffset = firstRow * kHexBytesPerLine;
    // 接近窗口边界时预取下一段
    const margin = 4096;
    if (byteOffset < _windowStart + margin ||
        byteOffset > _windowStart + _window.length - margin * 2) {
      final newStart =
          ((byteOffset - 32 * kHexBytesPerLine).clamp(0, _fileSize) ~/
                  kHexBytesPerLine) *
              kHexBytesPerLine;
      _loadWindow(newStart).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  int get _totalRows => (_fileSize / kHexBytesPerLine).ceil();

  /// 取第 row 行的 16 字节
  Uint8List _rowBytes(int row) {
    final offset = row * kHexBytesPerLine;
    final rel = offset - _windowStart;
    if (rel < 0 || rel >= _window.length) return Uint8List(0);
    final end = (rel + kHexBytesPerLine).clamp(0, _window.length);
    return Uint8List.sublistView(_window, rel, end);
  }

  /// 修改一个字节（仅小文件编辑模式）
  Future<void> _editByte(int offset, int value) async {
    if (!_editing) return;
    final rel = offset - _windowStart;
    if (rel < 0 || rel >= _window.length) return;
    setState(() => _window[rel] = value);
  }

  Future<void> _save() async {
    try {
      await _fs.writeBytes(widget.path, _window);
      if (!mounted) return;
      _snack('已保存');
      setState(() => _editing = false);
    } catch (e) {
      _snack('保存失败：$e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  /// 跳转到指定偏移
  void _goto(int offset) {
    if (offset < 0) offset = 0;
    if (offset > _fileSize) offset = _fileSize;
    final row = offset ~/ kHexBytesPerLine;
    final target = (row * _rowHeight).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.jumpTo(target);
    if (_fileSize > 512 * 1024) {
      _loadWindow(row * kHexBytesPerLine).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _showGoto() async {
    _gotoCtl.clear();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到偏移'),
        content: TextField(
          controller: _gotoCtl,
          autofocus: true,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(
            hintText: '支持十进制与 0x 十六进制',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_gotoCtl.text.trim()),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    final n = v.startsWith('0x') || v.startsWith('0X')
        ? int.tryParse(v.substring(2), radix: 16)
        : int.tryParse(v);
    if (n == null) {
      _snack('无法解析偏移');
      return;
    }
    _goto(n);
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
    final canEdit = _fileSize <= 512 * 1024;
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
                    '${formatSize(_fileSize)} · $_totalRows 行'
                    '${_editing ? ' · 编辑中' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '跳转',
              onPressed: _showGoto,
              icon: uiIcon(UiIcons.search, size: 20, color: colors.onSurface),
            ),
            if (canEdit)
              IconButton(
                tooltip: _editing ? '保存' : '编辑',
                onPressed: _editing ? _save : () => setState(() => _editing = true),
                icon: uiIcon(
                  _editing ? UiIcons.save : UiIcons.edit,
                  size: 20,
                  color: _editing ? colors.primary : colors.onSurface,
                ),
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
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: colors.error),
          ),
        ),
      );
    }

    final mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['monospace'],
      fontSize: 11.5,
      height: 1.4,
      color: colors.onSurface,
    );

    return LayoutBuilder(
      builder: (ctx, c) {
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: _totalRows,
          itemExtent: _rowHeight,
          itemBuilder: (ctx2, row) {
            final bytes = _rowBytes(row);
            final offset = row * kHexBytesPerLine;
            return _hexRow(offset, bytes, mono, colors);
          },
        );
      },
    );
  }

  Widget _hexRow(
    int offset,
    Uint8List bytes,
    TextStyle mono,
    MiuixColors colors,
  ) {
    final hex = StringBuffer();
    final ascii = StringBuffer();
    for (var i = 0; i < kHexBytesPerLine; i++) {
      if (i < bytes.length) {
        hex.write(bytes[i].toRadixString(16).padLeft(2, '0'));
        final b = bytes[i];
        ascii.write(b >= 0x20 && b < 0x7F ? String.fromCharCode(b) : '.');
      } else {
        hex.write('  ');
        ascii.write(' ');
      }
      if (i == 7) hex.write('  '); // 中间分组，便于阅读
      hex.write(' ');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          // 偏移
          SizedBox(
            width: 62,
            child: Text(
              offset.toRadixString(16).padLeft(8, '0'),
              style: mono.copyWith(color: colors.onSurfaceVariantSummary),
            ),
          ),
          // 十六进制
          Expanded(
            child: _editing
                ? _editableHex(offset, bytes, mono)
                : Text(hex.toString(), style: mono),
          ),
          // ASCII
          SizedBox(
            width: 118,
            child: Text(
              ascii.toString(),
              style: mono.copyWith(color: colors.onSurfaceVariantSummary),
            ),
          ),
        ],
      ),
    );
  }

  /// 编辑模式下：每字节可点（弹出单字节修改）
  Widget _editableHex(int offset, Uint8List bytes, TextStyle mono) {
    return Wrap(
      children: [
        for (var i = 0; i < kBytesShown(bytes); i++)
          GestureDetector(
            onTap: () => _editByteDialog(offset + i, bytes[i]),
            child: Text(
              '${bytes[i].toRadixString(16).padLeft(2, '0')} ',
              style: mono.copyWith(
                backgroundColor: Colors.transparent,
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted,
                decorationColor: Colors.grey.withValues(alpha: 0.5),
              ),
            ),
          ),
      ],
    );
  }

  int kBytesShown(Uint8List b) => b.length;

  Future<void> _editByteDialog(int offset, int current) async {
    final ctl = TextEditingController(
      text: current.toRadixString(16).padLeft(2, '0'),
    );
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('偏移 0x${offset.toRadixString(16)}'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '十六进制字节，如 ff',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
            child: const Text('修改'),
          ),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    final n = int.tryParse(v, radix: 16);
    if (n == null || n < 0 || n > 255) {
      _snack('需要 00~ff 之间的十六进制值');
      return;
    }
    await _editByte(offset, n);
  }
}
