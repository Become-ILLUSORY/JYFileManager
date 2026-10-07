// 压缩参数对话框：格式、压缩级别、密码、是否删除源文件。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 压缩选项
class CompressOptions {
  const CompressOptions({
    required this.name,
    required this.format,
    required this.level,
    this.password,
    this.deleteSource = false,
  });

  final String name;
  final String format;
  final int level;
  final String? password;
  final bool deleteSource;
}

/// 显示压缩对话框；取消返回 null
Future<CompressOptions?> showCompressDialog(
  BuildContext context, {
  required String defaultName,
  required int count,
}) {
  return showDialog<CompressOptions>(
    context: context,
    builder: (_) => _CompressDialog(defaultName: defaultName, count: count),
  );
}

class _CompressDialog extends StatefulWidget {
  const _CompressDialog({required this.defaultName, required this.count});

  final String defaultName;
  final int count;

  @override
  State<_CompressDialog> createState() => _CompressDialogState();
}

class _CompressDialogState extends State<_CompressDialog> {
  late final _nameCtl = TextEditingController(text: widget.defaultName);
  final _passCtl = TextEditingController();

  String _format = 'zip';
  int _level = 6;
  bool _deleteSource = false;
  bool _usePassword = false;

  /// 格式 → 是否支持密码（zip 支持；tar 系列不支持）
  bool get _supportsPassword => _format == 'zip';

  @override
  void dispose() {
    _nameCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return AlertDialog(
      title: Text('压缩 ${widget.count} 个项目'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtl,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: '文件名',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '格式',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in const [
                  ('zip', 'ZIP'),
                  ('tar', 'TAR'),
                  ('tar.gz', 'TAR.GZ'),
                  ('tar.bz2', 'TAR.BZ2'),
                ])
                  GestureDetector(
                    onTap: () => setState(() {
                      _format = f.$1;
                      if (!_supportsPassword) _usePassword = false;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _format == f.$1
                            ? colors.primary
                            : colors.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        f.$2,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _format == f.$1
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: _format == f.$1
                              ? colors.onPrimary
                              : colors.onSurfaceVariantSummary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '压缩级别',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (final lv in const [
                  (0, '不压缩'),
                  (3, '快速'),
                  (6, '标准'),
                  (9, '最大'),
                ])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _level = lv.$1),
                      child: Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _level == lv.$1
                              ? colors.primary.withValues(alpha: 0.14)
                              : Colors.transparent,
                          border: Border.all(
                            color: _level == lv.$1
                                ? colors.primary
                                : colors.outline.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          lv.$2,
                          style: TextStyle(
                            fontSize: 11,
                            color: _level == lv.$1
                                ? colors.primary
                                : colors.onSurfaceVariantSummary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (_supportsPassword) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: _usePassword,
                    onChanged: (v) =>
                        setState(() => _usePassword = v ?? false),
                  ),
                  const Text('设置密码', style: TextStyle(fontSize: 13)),
                ],
              ),
              if (_usePassword)
                TextField(
                  controller: _passCtl,
                  obscureText: true,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: const InputDecoration(
                    hintText: '密码',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _deleteSource,
                  onChanged: (v) =>
                      setState(() => _deleteSource = v ?? false),
                ),
                const Text('压缩后删除源文件', style: TextStyle(fontSize: 13)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameCtl.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop(
              CompressOptions(
                name: name,
                format: _format,
                level: _level,
                password: _usePassword && _passCtl.text.isNotEmpty
                    ? _passCtl.text
                    : null,
                deleteSource: _deleteSource,
              ),
            );
          },
          child: const Text('开始压缩'),
        ),
      ],
    );
  }
}
