// 文件列表项：图标 + 名称 + 修改时间/大小
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/models/file_item.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icon_utils.dart';

class FileListTile extends StatelessWidget {
  const FileListTile({
    super.key,
    required this.item,
    required this.selected,
    required this.multiSelect,
    required this.onTap,
    required this.onLongPress,
    this.dense = false,
  });

  final FileItem item;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;

    final iconInfo = iconForFile(
      name: item.name,
      isDirectory: item.isDirectory,
      isLink: item.isLink,
    );
    final iconColor = item.isDirectory
        ? colors.primary
        : (iconInfo.color ?? colors.onSurfaceVariantSummary);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: selected
            ? colors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: dense ? 6 : 8,
        ),
        child: Row(
          children: [
            if (multiSelect) ...[
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? colors.primary : colors.outline,
              ),
              const SizedBox(width: 8),
            ],
            Icon(iconInfo.icon, size: dense ? 26 : 30, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: dense ? 12.5 : 13.5,
                            color: colors.onSurface,
                            fontWeight: item.isDirectory
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (item.isLink) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.link_rounded,
                          size: 12,
                          color: colors.primary.withValues(alpha: 0.7),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: dense ? 10 : 10.5,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final time = formatTime(item.modified, withTime: true);
    if (item.isDirectory) return time;
    return '$time · ${formatSize(item.size)}';
  }
}
