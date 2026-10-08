// 通用列表项：替代 Material 的 ListTile。
//
// 为什么不用 ListTile：它依赖 Material 祖先来解析文字样式与涟漪，
// 而 MiuixScaffold 提供的是 MiuixSurface 而非 Material，
// release 构建下会因缺少祖先而 build 失败（表现为整块区域变灰、点击无反应）。
// 这里自己拼装，只依赖 Miuix 主题色，不要求 Material 祖先。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.dense = false,
  });

  /// 标题：可直接传字符串（自动套用样式），也可传自定义 Widget
  final Object title;

  /// 副标题：字符串或 Widget
  final Object? subtitle;

  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 紧凑模式：上下内边距更小
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;

    Widget buildText(Object v, {required bool isTitle}) {
      if (v is Widget) return v;
      return Text(
        '$v',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: isTitle ? (dense ? 13 : 13.5) : 11,
          color: isTitle ? colors.onSurface : colors.onSurfaceVariantSummary,
        ),
      );
    }

    final content = Padding(
      padding: EdgeInsets.fromLTRB(16, dense ? 8 : 11, 8, dense ? 8 : 11),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                buildText(title, isTitle: true),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  buildText(subtitle!, isTitle: false),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );

    // onTap 为 null 时也要能容纳 trailing 里的按钮
    return Material(
      color: Colors.transparent,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}
