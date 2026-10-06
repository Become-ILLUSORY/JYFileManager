// 文件列表项：圆角图标容器 + 名称 + 元信息，选中态整行高亮
//
// [FileRow] 是通用行外壳，[FileListTile]（普通条目）与 [ParentDirTile]（".."）
// 共用同一套排版，保证「上级目录」看起来就是一个普通文件夹对象。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/models/file_item.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icon_utils.dart';

/// 通用文件行外壳：左侧圆角图标容器 + 主标题 + 副标题 + 尾部箭头
class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
    this.multiSelect = false,
    this.showChevron = false,
    this.trailing,
    this.titleWeight = FontWeight.w500,
    this.dense = true,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool multiSelect;
  final bool showChevron;
  final Widget? trailing;
  final FontWeight titleWeight;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final nameColor = selected ? colors.primary : colors.onSurface;
    final subColor = colors.onSurfaceVariantSummary;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 12,
        vertical: dense ? 2 : 3,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(14),
          splashColor: accent.withValues(alpha: 0.10),
          highlightColor: accent.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 8 : 10,
              vertical: dense ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? colors.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? colors.primary.withValues(alpha: 0.35)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                if (multiSelect) ...[
                  _CheckMark(selected: selected, color: colors.primary),
                  const SizedBox(width: 8),
                ],
                _IconBadge(
                  icon: icon,
                  accent: accent,
                  size: dense ? 34 : 38,
                ),
                SizedBox(width: dense ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: dense ? 13.5 : 14.5,
                          height: 1.15,
                          color: nameColor,
                          fontWeight: titleWeight,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: dense ? 10.5 : 11,
                          height: 1.1,
                          color: subColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (showChevron)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: subColor.withValues(alpha: 0.7),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个文件/文件夹行
class FileListTile extends StatelessWidget {
  const FileListTile({
    super.key,
    required this.item,
    required this.selected,
    required this.multiSelect,
    required this.onTap,
    required this.onLongPress,
    this.onMore,
    this.dense = true,
  });

  final FileItem item;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onMore;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final info = iconForFile(
      name: item.name,
      isDirectory: item.isDirectory,
      isLink: item.isLink,
    );

    // 文件夹用主题色，其余用类型色（回退到中性色）
    final accent = item.isDirectory
        ? colors.primary
        : (info.color ?? colors.onSurfaceVariantSummary);

    return FileRow(
      icon: info.icon,
      accent: accent,
      title: item.name,
      subtitle: _subtitle(),
      selected: selected,
      multiSelect: multiSelect,
      dense: dense,
      titleWeight: item.isDirectory ? FontWeight.w600 : FontWeight.w500,
      showChevron: item.isDirectory,
      trailing: !item.isDirectory && onMore != null
          ? _MoreButton(onPressed: onMore!, color: colors.onSurfaceVariantSummary)
          : (item.isLink
              ? Icon(
                  Icons.link_rounded,
                  size: 13,
                  color: colors.primary.withValues(alpha: 0.8),
                )
              : null),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  String _subtitle() {
    final time = formatTime(item.modified, withTime: true);
    if (item.isDirectory) return time;
    if (item.isLink) {
      return '${item.linkTarget ?? ''}  ·  $time';
    }
    return '${formatSize(item.size)}  ·  $time';
  }
}

/// 上级目录行：按 Linux 规范以 ".." 表示，视觉上与普通文件夹行完全一致
class ParentDirTile extends StatelessWidget {
  const ParentDirTile({
    super.key,
    required this.parentPath,
    required this.onTap,
    this.dense = true,
  });

  /// 上级目录的完整路径（作为副标题，便于确认将去哪里）
  final String parentPath;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return FileRow(
      icon: Icons.folder_rounded,
      accent: colors.primary,
      title: '..',
      subtitle: parentPath,
      dense: dense,
      titleWeight: FontWeight.w600,
      showChevron: true,
      onTap: onTap,
      onLongPress: null,
    );
  }
}

/// 圆角方块图标容器（带同色淡底，视觉更精致）
class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.accent,
    required this.size,
  });

  final IconData icon;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(
          color: accent.withValues(alpha: 0.18),
          width: 0.8,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.58, color: accent),
    );
  }
}

class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.selected, required this.color});

  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 19,
      height: 19,
      decoration: BoxDecoration(
        color: selected ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? color : color.withValues(alpha: 0.45),
          width: 1.6,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : null,
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onPressed, required this.color});

  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(9),
          child: Icon(Icons.more_vert_rounded, size: 17, color: color),
        ),
      ),
    );
  }
}
