// 长按菜单：贴近手指弹出的玻璃质感菜单
//
// 形态参照成熟文件管理器的操作习惯：长按文件后在手指附近弹出
// 两列按钮，每项「图标在左、文字在右」，一屏内即可完成常用操作。
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/utils/ui_icons.dart';

/// 菜单中的一项
class MenuAction {
  const MenuAction({
    required this.label,
    required this.icon,
    this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  final String label;
  final dynamic icon;
  final VoidCallback? onTap;
  final bool enabled;
  final bool destructive;
}

/// 在 [globalPosition] 附近弹出菜单。
///
/// 菜单会自动避开屏幕边缘；点击外部或选择某项后关闭。
Future<void> showItemMenu(
  BuildContext context, {
  required Offset globalPosition,
  required List<MenuAction> actions,
  String? title,
  String? subtitle,
  int columns = 2,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭菜单',
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, _) {
      return _MenuLayer(
        anchor: globalPosition,
        title: title,
        subtitle: subtitle,
        actions: actions,
        columns: columns,
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          alignment: Alignment.topLeft,
          child: child,
        ),
      );
    },
  );
}

class _MenuLayer extends StatelessWidget {
  const _MenuLayer({
    required this.anchor,
    required this.actions,
    required this.columns,
    this.title,
    this.subtitle,
  });

  final Offset anchor;
  final List<MenuAction> actions;
  final int columns;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final media = MediaQuery.of(context);
    final size = media.size;
    final padding = media.padding;

    // 面板宽度：两列时约占屏幕 92%，列数更多时按比例收窄
    final contentWidth = columns <= 2
        ? (size.width * 0.92).clamp(240.0, 460.0)
        : (columns * 92.0).clamp(240.0, size.width * 0.94);

    final rows = (actions.length / columns).ceil();
    final hasHeader = title != null && title!.isNotEmpty;
    final headerHeight = hasHeader ? (subtitle != null ? 64.0 : 44.0) : 0.0;
    const rowHeight = 46.0;
    final gridHeight = rows * rowHeight + 12;
    final panelHeight = headerHeight + gridHeight;

    // 锚点定位：默认让菜单贴着手指，越界则翻转/夹紧
    var left = anchor.dx - 14;
    var top = anchor.dy - 14;
    if (left + contentWidth > size.width - 8) {
      left = size.width - contentWidth - 8;
    }
    if (top + panelHeight > size.height - padding.bottom - 8) {
      top = anchor.dy - panelHeight + 14;
    }
    left = left.clamp(8.0, (size.width - contentWidth - 8).clamp(8.0, size.width));
    top = top.clamp(
      padding.top + 8,
      (size.height - panelHeight - 8).clamp(padding.top + 8, size.height),
    );

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: contentWidth,
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colors.outline.withValues(alpha: 0.16),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasHeader) _header(colors),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                        child: Wrap(
                          children: [
                            for (final a in actions)
                              SizedBox(
                                width: (contentWidth - 16) / columns,
                                child: _MenuButton(
                                  action: a,
                                  colors: colors,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(MiuixColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: colors.onSurface,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单个按钮：图标在左、文字在右
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.action, required this.colors});

  final MenuAction action;
  final MiuixColors colors;

  @override
  Widget build(BuildContext context) {
    final enabled = action.enabled && action.onTap != null;
    final tint = !enabled
        ? colors.onSurfaceVariantSummary.withValues(alpha: 0.38)
        : (action.destructive ? colors.error : colors.onSurface);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled
            ? () {
                Navigator.of(context).pop();
                action.onTap!();
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            children: [
              uiIcon(action.icon, size: 20, color: tint),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.1,
                    color: tint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
