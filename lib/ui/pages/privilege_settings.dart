// 提权设置页：Root / Shizuku 的探测、授权与状态展示
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/utils/ui_icons.dart';
import '../../services/app_settings.dart';
import '../../services/privilege.dart';
import '../widgets/sheets.dart';

/// 显示提权设置面板
Future<void> showPrivilegeSettings(BuildContext context) {
  final settings = AppSettings.instance;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: GlassSurface(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: _PrivilegePanel(settings: settings),
        ),
      ),
    ),
  );
}

class _PrivilegePanel extends StatefulWidget {
  const _PrivilegePanel({required this.settings});
  final AppSettings settings;

  @override
  State<_PrivilegePanel> createState() => _PrivilegePanelState();
}

class _PrivilegePanelState extends State<_PrivilegePanel> {
  final _mgr = PrivilegeManager.instance;
  PrivilegeStatus _status = const PrivilegeStatus();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({bool interactive = false}) async {
    setState(() => _busy = true);
    final s = await _mgr.refresh(interactive: interactive);
    if (!mounted) return;
    setState(() {
      _status = s;
      _busy = false;
    });
    // 同步到设置项，便于其它地方读取
    if (s.active) {
      widget.settings.setPrivilegeMode(
        s.mode == PrivilegeMode.root ? 1 : 2,
      );
    }
  }

  Future<void> _enable(PrivilegeMode mode) async {
    setState(() => _busy = true);
    final s = await _mgr.enable(mode);
    if (!mounted) return;
    setState(() {
      _status = s;
      _busy = false;
    });
    widget.settings.setPrivilegeMode(s.active
        ? (s.mode == PrivilegeMode.root ? 1 : 2)
        : 0);
  }

  Future<void> _disable() async {
    await _mgr.disable();
    widget.settings.setPrivilegeMode(0);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final s = _status;
    final ready = s.active;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            uiIcon(UiIcons.lock, size: 20, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              '超级权限',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
            const Spacer(),
            if (_busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '开启后可以浏览 /data、/system 等系统目录，'
          '修改前会再次确认。不开启也能正常使用文件管理功能。',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: colors.onSurfaceVariantSummary,
          ),
        ),
        const SizedBox(height: 16),

        // ---------------- Root ----------------
        _PrivilegeCard(
          title: 'Root 授权',
          subtitle: s.mode == PrivilegeMode.root
              ? (s.detail)
              : '适用于已刷入 Magisk / KernelSU / APatch 的设备',
          flavor: s.mode == PrivilegeMode.root ? s.flavor : null,
          state: s.mode == PrivilegeMode.root
              ? (ready ? _CardState.on : _CardState.off)
              : _CardState.idle,
          onEnable: _busy ? null : () => _enable(PrivilegeMode.root),
        ),
        const SizedBox(height: 10),

        // ---------------- Shizuku ----------------
        _PrivilegeCard(
          title: 'Shizuku 授权',
          subtitle: s.mode == PrivilegeMode.shizuku
              ? (s.detail)
              : '适用于没有 Root、但能使用 adb 调试的设备',
          flavor: s.mode == PrivilegeMode.shizuku ? s.flavor : null,
          state: s.mode == PrivilegeMode.shizuku
              ? (ready ? _CardState.on : _CardState.off)
              : _CardState.idle,
          onEnable: _busy ? null : () => _enable(PrivilegeMode.shizuku),
        ),

        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),

        _SettingRow(
          title: '无权限时自动提权',
          subtitle: '遇到打不开的目录时，自动改用超级权限访问',
          trailing: MiuixSwitch(
            value: widget.settings.autoFallback,
            onChanged: widget.settings.setAutoFallback,
          ),
        ),
        const SizedBox(height: 10),
        _SettingRow(
          title: '修改前二次确认',
          subtitle: '在系统目录中删除、重命名等操作前先确认',
          trailing: MiuixSwitch(
            value: widget.settings.confirmRoot,
            onChanged: widget.settings.setConfirmRoot,
          ),
        ),

        if (ready) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: MiuixButton(
              onPressed: _busy ? null : _disable,
              minHeight: 42,
              child: const Text('关闭超级权限'),
            ),
          ),
        ],
      ],
    );
  }
}

enum _CardState { idle, on, off }

class _PrivilegeCard extends StatelessWidget {
  const _PrivilegeCard({
    required this.title,
    required this.subtitle,
    required this.state,
    required this.onEnable,
    this.flavor,
  });

  final String title;
  final String subtitle;
  final _CardState state;
  final String? flavor;
  final VoidCallback? onEnable;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final on = state == _CardState.on;
    final off = state == _CardState.off;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: on
              ? colors.primary.withValues(alpha: 0.55)
              : colors.dividerLine.withValues(alpha: 0.4),
          width: on ? 1.4 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            on ? Icons.verified_user_rounded : Icons.shield_outlined,
            size: 20,
            color: on ? colors.primary : colors.onSurfaceVariantSummary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    if (flavor != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          flavor!,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (on)
            Text(
              '已授权',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            )
          else
            MiuixButton(
              onPressed: onEnable,
              minWidth: 66,
              minHeight: 32,
              child: Text(off ? '重试' : '授权'),
            ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 13.5, color: colors.onSurface),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.3,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        trailing,
      ],
    );
  }
}
