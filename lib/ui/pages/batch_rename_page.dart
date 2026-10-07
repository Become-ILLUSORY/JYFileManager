// 批量重命名页面：输入表达式模板，实时预览结果，确认后执行。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/models/file_item.dart';
import '../../core/utils/batch_rename.dart';
import '../../core/utils/ui_icons.dart';
import '../../services/fs/fs_provider.dart';

/// 打开批量重命名页；返回 true 表示执行过改名
Future<bool?> showBatchRenamePage(
  BuildContext context, {
  required List<FileItem> items,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => BatchRenamePage(items: items),
      fullscreenDialog: true,
    ),
  );
}

class BatchRenamePage extends StatefulWidget {
  const BatchRenamePage({super.key, required this.items});

  final List<FileItem> items;

  @override
  State<BatchRenamePage> createState() => _BatchRenamePageState();
}

class _BatchRenamePageState extends State<BatchRenamePage> {
  final _tplCtl = TextEditingController(text: '{P}_{z3}');
  final _startCtl = TextEditingController(text: '1');
  final _stepCtl = TextEditingController(text: '1');

  final _fs = appFs;

  List<RenamePlan> _plans = [];
  List<String> _errors = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tplCtl.addListener(_replan);
    _startCtl.addListener(_replan);
    _stepCtl.addListener(_replan);
    _replan();
  }

  @override
  void dispose() {
    _tplCtl.dispose();
    _startCtl.dispose();
    _stepCtl.dispose();
    super.dispose();
  }

  void _replan() {
    final plans = BatchRename.plan(
      files: [
        for (final it in widget.items)
          (
            path: it.path,
            name: it.name,
            modified: it.modified,
            size: it.size,
          ),
      ],
      template: _tplCtl.text,
      startNumber: int.tryParse(_startCtl.text) ?? 1,
      step: int.tryParse(_stepCtl.text) ?? 1,
    );
    setState(() {
      _plans = plans;
      _errors = BatchRename.validate(plans);
    });
  }

  Future<void> _apply() async {
    if (_errors.isNotEmpty || _busy) return;
    setState(() => _busy = true);
    var ok = 0;
    final failed = <String>[];

    for (final plan in _plans) {
      if (!plan.changed) {
        ok++;
        continue;
      }
      try {
        final newPath = '${BatchRename.dirOf(plan.oldPath)}/${plan.newName}';
        await _fs.rename(plan.oldPath, newPath);
        ok++;
      } catch (e) {
        failed.add('${plan.oldName}: $e');
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);

    if (failed.isEmpty) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$ok 项成功，${failed.length} 项失败'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final changed = _plans.where((p) => p.changed).length;

    return MiuixScaffold(
      containerColor: colors.background,
      topBar: Container(
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
                      '批量重命名',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.items.length} 项 · $changed 项将改名',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: (_errors.isEmpty && !_busy) ? _apply : null,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('执行'),
              ),
            ],
          ),
        ),
      ),
      content: (padding) => Padding(
        padding: EdgeInsets.only(top: padding.top),
        child: Column(
          children: [
            _buildEditor(colors),
            if (_errors.isNotEmpty) _buildErrors(colors),
            const Divider(height: 1),
            Expanded(child: _buildPreview(colors)),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(MiuixColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _tplCtl,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
            ),
            decoration: InputDecoration(
              labelText: '重命名表达式',
              hintText: '{P}_{z3}',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: '可用占位符',
                icon: uiIcon(UiIcons.info,
                    size: 19, color: colors.onSurfaceVariantSummary),
                onPressed: _showTokens,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startCtl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: const InputDecoration(
                    labelText: '起始序号',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _stepCtl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: const InputDecoration(
                    labelText: '步长',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showTokens() {
    final colors = MiuixTheme.of(context).colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(22),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '可用占位符',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                for (final t in const [
                  ('{P}', '原文件名（不含扩展名）'),
                  ('{E}', '原扩展名'),
                  ('{N}', '序号'),
                  ('{z3}', '序号补零到 3 位 → 001'),
                  ('{T}', '时间戳 yyyyMMdd_HHmmss'),
                  ('{T:yyyy-MM-dd}', '自定义日期格式'),
                  ('{D}', '修改日期 yyyyMMdd'),
                  ('{S}', '文件大小（1.2MB）'),
                  ('{AN}', '按名称排序的序号'),
                  ('{AD}', '按日期排序的序号'),
                  ('{AS}', '按大小排序的序号'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            t.$1,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              color: colors.primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            t.$2,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.onSurfaceVariantSummary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  '日期格式：yyyy yy MMMM MMM MM dd EEE HH hh mm ss SSS Q',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrors(MiuixColors colors) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in _errors.take(3))
            Text(
              e,
              style: TextStyle(fontSize: 12, color: colors.error),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview(MiuixColors colors) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 40),
      itemCount: _plans.length,
      itemBuilder: (ctx, i) {
        final plan = _plans[i];
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: plan.changed
                  ? colors.primary.withValues(alpha: 0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.oldName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariantSummary,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    uiIcon(UiIcons.chevronRight,
                        size: 14, color: colors.primary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        plan.newName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: plan.changed
                              ? colors.onSurface
                              : colors.onSurfaceVariantSummary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
