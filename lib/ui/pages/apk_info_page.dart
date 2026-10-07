// APK 信息页：展示安装包的详细信息（应用名、包名、版本、SDK、权限、组件、DEX、ABI）。
//
// 全部用纯 Dart 解析（见 services/apk_parser.dart），不依赖原生。

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/utils/format.dart';
import '../../core/utils/ui_icons.dart';
import '../../services/apk_parser.dart';
import '../../services/fs/fs_provider.dart';

/// 打开 APK 信息页
Future<void> showApkInfoPage(
  BuildContext context, {
  required String path,
  required String name,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ApkInfoPage(path: path, name: name),
      fullscreenDialog: true,
    ),
  );
}

class ApkInfoPage extends StatefulWidget {
  const ApkInfoPage({super.key, required this.path, required this.name});

  final String path;
  final String name;

  @override
  State<ApkInfoPage> createState() => _ApkInfoPageState();
}

class _ApkInfoPageState extends State<ApkInfoPage> {
  final _fs = appFs;

  ApkInfo? _info;
  int _fileSize = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await _fs.readBytes(widget.path);
      _fileSize = bytes.length;
      final info = await ApkParser.parse(bytes);
      if (!mounted) return;
      if (info == null) {
        setState(() {
          _error = '无法解析该安装包（可能不是有效的 APK）';
          _loading = false;
        });
        return;
      }
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
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
                child: Text(
                  '安装包信息',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      content: (padding) => Padding(
        padding: EdgeInsets.only(top: padding.top),
        child: _buildBody(colors),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              uiIcon(UiIcons.error, size: 40, color: colors.error),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: colors.error),
              ),
              const SizedBox(height: 16),
              MiuixButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final info = _info!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 60),
      children: [
        // 头部：图标 + 名称 + 包名
        Row(
          children: [
            _iconBox(info, colors),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    info.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    info.packageName,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        _section('版本信息', colors, [
          ('版本名', info.versionName.isEmpty ? '未知' : info.versionName),
          ('版本号', '${info.versionCode}'),
          ('最低 SDK', info.minSdk > 0 ? 'API ${info.minSdk}' : '未声明'),
          ('目标 SDK', info.targetSdk > 0 ? 'API ${info.targetSdk}' : '未声明'),
          ('文件大小', formatSize(_fileSize)),
        ]),

        if (info.abis.isNotEmpty)
          _section('支持的架构', colors, [
            ('ABI', info.abis.join('、')),
          ]),

        if (info.signatureSchemes.isNotEmpty)
          _section('签名', colors, [
            ('签名方案', info.signatureSchemes.join(' / ')),
          ]),

        _section('组件', colors, [
          ('Activity', '${info.activities}'),
          ('Service', '${info.services}'),
          ('Receiver', '${info.receivers}'),
          ('Provider', '${info.providers}'),
          if (info.mainActivity != null) ('启动 Activity', info.mainActivity!),
        ]),

        if (info.dexFiles.isNotEmpty)
          _section('DEX 文件', colors, [
            ('数量', '${info.dexFiles.length}'),
            for (final d in info.dexFiles.take(10)) (d, ''),
          ]),

        if (info.permissions.isNotEmpty)
          _section('权限（${info.permissions.length}）', colors, [
            for (final p in info.permissions) (p, ''),
          ]),
      ],
    );
  }

  Widget _iconBox(ApkInfo info, MiuixColors colors) {
    const size = 68.0;
    if (info.iconPng != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          info.iconPng!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _placeholder(colors, size),
        ),
      );
    }
    return _placeholder(colors, size);
  }

  Widget _placeholder(MiuixColors colors, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: uiIcon(UiIcons.archive, size: 30, color: colors.primary),
      ),
    );
  }

  Widget _section(
    String title,
    MiuixColors colors,
    List<(String, String)> rows,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: colors.onSurface.withValues(alpha: 0.06),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            rows[i].$1,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.onSurfaceVariantSummary,
                            ),
                          ),
                        ),
                        if (rows[i].$2.isNotEmpty)
                          Expanded(
                            flex: 5,
                            child: Text(
                              rows[i].$2,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
