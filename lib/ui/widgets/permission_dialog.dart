import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../services/app_settings.dart';
import '../../services/privilege.dart';
import '../pages/privilege_settings.dart';

/// 「没有访问权限」提示。
///
/// 设计要点：
/// - 不用刺眼的红色弹窗，而是与 App 一致的卡片式对话框；
/// - 明确告诉用户「为什么」被拒绝，而不是甩一句 Permission denied；
/// - 给出可执行的下一步：开启提权 / 换一个目录，而不是让用户干瞪眼；
/// - 若用户尚未配置提权，一键直达提权设置页。
Future<void> showPermissionDeniedDialog(
  BuildContext context, {
  required String path,
  String? reason,
}) {
  final settings = AppSettings.instance;
  // 用真实可用状态而不是「设置里选过」，否则提权其实没生效时
  // 用户会看到一个不给出路的死胡同提示。
  final enabled = PrivilegeManager.instance.isActive ||
      settings.privilegeMode != 0;
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final colors = MiuixTheme.of(ctx).colors;
      return Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 21,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '没有访问权限',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                reason ?? '系统拒绝了本次访问请求。该目录属于受保护区域，普通应用无法读取。',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  path,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontFamily: 'monospace',
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (!enabled) ...[
                Text(
                  '可以开启 Root 或 Shizuku 提权来访问此目录',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('知道了'),
                  ),
                  const SizedBox(width: 4),
                  if (!enabled)
                    FilledButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        showPrivilegeSettings(context);
                      },
                      child: const Text('去开启提权'),
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
