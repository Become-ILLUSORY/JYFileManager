// 弹出层：玻璃质感底部动作面板 / 输入框 / 确认框 / 属性面板
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/models/file_item.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icon_utils.dart';
import '../../core/utils/ui_icons.dart';

/// 动作面板中的一个条目
class SheetAction {
  const SheetAction({
    required this.label,
    required this.icon,
    this.onTap,
    this.destructive = false,
    this.summary,
  });

  final String label;
  final dynamic icon;
  final VoidCallback? onTap;
  final bool destructive;
  final String? summary;
}

/// 玻璃底板：模糊 + 半透明
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 26,
    this.alpha = 0.78,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final double alpha;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: colors.outline.withValues(alpha: 0.14),
              width: 0.8,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 显示玻璃动作面板，返回是否执行了某个动作
Future<void> showActionSheet(
  BuildContext context, {
  String? title,
  String? subtitle,
  required List<SheetAction> actions,
}) async {
  final colors = MiuixTheme.of(context).colors;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: GlassSurface(
            radius: 26,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖拽指示条
                Container(
                  width: 34,
                  height: 4,
                  margin: const EdgeInsets.only(top: 6, bottom: 12),
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariantSummary
                        .withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurface,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colors.onSurfaceVariantSummary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (title != null)
                  Divider(
                    height: 14,
                    color: colors.dividerLine.withValues(alpha: 0.5),
                  ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final a in actions)
                          _SheetRow(
                            action: a,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              a.onTap?.call();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.action, required this.onTap});

  final SheetAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final enabled = action.onTap != null;
    final tint = action.destructive
        ? colors.error
        : (enabled ? colors.onSurface : colors.disabledOnSurface);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: uiIcon(action.icon, size: 21, color: tint),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action.label,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: tint,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (action.summary != null)
                      Text(
                        action.summary!,
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
            ],
          ),
        ),
      ),
    );
  }
}

/// 输入对话框（新建/重命名）
Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirmText = '确定',
}) {
  final controller = TextEditingController(text: initial);
  final colors = MiuixTheme.of(context).colors;

  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: GlassSurface(
          radius: 24,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(fontSize: 14, color: colors.onSurface),
                decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  filled: true,
                  fillColor: colors.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      '取消',
                      style: TextStyle(color: colors.onSurfaceVariantSummary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(ctx).pop(controller.text.trim()),
                    child: Text(
                      confirmText,
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
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

/// 确认对话框
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = '确定',
  bool destructive = false,
}) async {
  final colors = MiuixTheme.of(context).colors;
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: GlassSurface(
          radius: 24,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 10),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(
                      '取消',
                      style: TextStyle(color: colors.onSurfaceVariantSummary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(
                      confirmText,
                      style: TextStyle(
                        color: destructive ? colors.error : colors.primary,
                        fontWeight: FontWeight.w600,
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
  return result ?? false;
}

/// 文件属性面板
Future<void> showPropertiesSheet(
  BuildContext context, {
  required FileItem item,
  int? dirSize,
  int? dirCount,
}) async {
  final colors = MiuixTheme.of(context).colors;
  final info = iconForFile(
    name: item.name,
    isDirectory: item.isDirectory,
    isLink: item.isLink,
  );

  final rows = <(String, String)>[
    ('名称', item.name),
    ('路径', item.path),
    ('类型', fileTypeDescription(item.name, isDirectory: item.isDirectory)),
    (
      '大小',
      item.isDirectory
          ? (dirSize == null
              ? '计算中…'
              : '${formatSize(dirSize)}${dirCount == null ? '' : '  ($dirCount 项)'}')
          : formatSizeExact(item.size)
    ),
    ('修改时间', formatTimeFull(item.modified)),
    if (item.accessed != null) ('访问时间', formatTimeFull(item.accessed!)),
    ('权限', '${item.modeString}  (${item.modeOctal})'),
    if (item.isLink) ('链接目标', item.linkTarget ?? '未知'),
  ];

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: GlassSurface(
            radius: 26,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: (item.isDirectory
                                ? colors.primary
                                : (info.color ?? colors.onSurfaceVariantSummary))
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        info.icon,
                        size: 23,
                        color: item.isDirectory
                            ? colors.primary
                            : (info.color ?? colors.onSurfaceVariantSummary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  color: colors.dividerLine.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final r in rows)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 66,
                                  child: Text(
                                    r.$1,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: colors.onSurfaceVariantSummary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: SelectableText(
                                    r.$2,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.35,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
