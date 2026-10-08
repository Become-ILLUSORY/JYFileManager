// 远程管理：添加 FTP / SFTP / WebDAV 位置，浏览并传输文件。
//
// 客户端实现在 services/remote/ 下（ftpconnect / dartssh2 / 自实现 WebDAV），
// 这里只做界面：连接配置、连接列表、远端目录浏览、上传下载。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/format.dart';
import '../../core/utils/ui_icons.dart';
import '../../services/remote/ftp_client.dart';
import '../../services/remote/remote_client.dart';
import '../../services/remote/sftp_client.dart';
import '../../services/remote/webdav_client.dart';
import '../widgets/app_list_tile.dart';

/// 打开远程管理
Future<void> showRemotePage(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const RemotePage(),
      fullscreenDialog: true,
    ),
  );
}

/// 远端连接配置
class RemoteConfig {
  RemoteConfig({
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.path = '/',
  });

  final String name;

  /// ftp / sftp / webdav
  final String type;
  final String host;
  final int port;
  final String username;
  final String password;
  final String path;

  String get typeLabel => switch (type) {
        'ftp' => 'FTP',
        'sftp' => 'SFTP',
        'webdav' => 'WebDAV',
        _ => type.toUpperCase(),
      };

  String get summary => '$host:$port';
}

class RemotePage extends StatefulWidget {
  const RemotePage({super.key});

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  final _configs = <RemoteConfig>[];

  /// 当前已连接
  RemoteClient? _client;
  RemoteConfig? _current;
  String _remotePath = '/';
  List<RemoteFileItem> _items = [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _client?.disconnect();
    super.dispose();
  }

  // ---------- 连接管理 ----------

  RemoteClient _makeClient(RemoteConfig c) {
    switch (c.type) {
      case 'sftp':
        return SftpRemoteClient(
          host: c.host,
          port: c.port,
          username: c.username,
          password: c.password,
        );
      case 'webdav':
        return WebDavRemoteClient(
          host: c.host,
          port: c.port,
          username: c.username,
          password: c.password,
        );
      default:
        return FtpRemoteClient(
          host: c.host,
          port: c.port,
          username: c.username,
          password: c.password,
        );
    }
  }

  Future<void> _connect(RemoteConfig c) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = _makeClient(c);
      await client.connect();
      final items = await client.listDirectory(c.path);
      if (!mounted) return;
      setState(() {
        _client = client;
        _current = c;
        _remotePath = c.path;
        _items = items;
        _busy = false;
      });
      _snack('已连接 ${c.name}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '连接失败：$e';
      });
    }
  }

  Future<void> _disconnect() async {
    await _client?.disconnect();
    setState(() {
      _client = null;
      _current = null;
      _items = [];
      _remotePath = '/';
    });
  }

  Future<void> _openDir(String path) async {
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    try {
      final items = await client.listDirectory(path);
      if (!mounted) return;
      setState(() {
        _remotePath = path;
        _items = items;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('打开目录失败：$e');
    }
  }

  Future<void> _upload(RemoteFileItem item) async {
    final client = _client;
    if (client == null) return;
    // 从本地下载目录挑一个文件上传
    final picked = await _pickLocalFile();
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      await client.uploadFile(
        picked,
        p.posix.join(_remotePath, p.basename(picked)),
        (_) {},
      );
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('已上传 ${p.basename(picked)}');
      await _openDir(_remotePath);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('上传失败：$e');
    }
  }

  Future<void> _download(RemoteFileItem item) async {
    final client = _client;
    if (client == null) return;
    final dir = Directory('/storage/emulated/0/Download');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final local = p.join(dir.path, item.name);
    setState(() => _busy = true);
    try {
      await client.downloadFile(item.path, local, (_) {});
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('已下载到 $local');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('下载失败：$e');
    }
  }

  Future<String?> _pickLocalFile() async {
    // 简易文件选择：列出常用目录下的文件
    final dir = Directory('/storage/emulated/0/Download');
    if (!dir.existsSync()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .take(100)
        .toList();
    if (files.isEmpty) {
      _snack('下载目录里没有文件');
      return null;
    }
    final colors = MiuixTheme.of(context).colors;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择要上传的文件'),
        content: SizedBox(
          width: double.maxFinite,
          height: 340,
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (c, i) {
              final f = files[i];
              return AppListTile(
                dense: true,
                leading: uiIcon(UiIcons.file, size: 19, color: colors.primary),
                title: Text(p.basename(f.path),
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  formatSize(f.lengthSync()),
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.of(ctx).pop(f.path),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800),
      ),
    );
  }

  // ---------- 添加连接 ----------

  Future<void> _addConnection() async {
    final result = await showDialog<RemoteConfig>(
      context: context,
      builder: (_) => const _AddRemoteDialog(),
    );
    if (result == null) return;
    setState(() => _configs.add(result));
    await _connect(result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      containerColor: colors.background,
      topBar: _buildTopBar(colors),
      content: (padding) => Padding(
        padding: EdgeInsets.only(top: padding.top),
        child: _current == null ? _buildConnectList(colors) : _buildBrowser(colors),
      ),
    );
  }

  Widget _buildTopBar(MiuixColors colors) {
    return Container(
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
                    '远程管理',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _current == null
                        ? '${_configs.length} 个连接'
                        : '${_current!.name} · $_remotePath',
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
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (_current == null)
              IconButton(
                onPressed: _addConnection,
                icon: uiIcon(UiIcons.add, size: 22, color: colors.onSurface),
              )
            else ...[
              IconButton(
                onPressed: () => _upload(
                  RemoteFileItem(
                    name: '',
                    path: _remotePath,
                    isDirectory: false,
                    size: 0,
                    modified: DateTime.now(),
                  ),
                ),
                icon: uiIcon(UiIcons.download, size: 21, color: colors.onSurface),
              ),
              IconButton(
                onPressed: _disconnect,
                icon: uiIcon(UiIcons.close, size: 21, color: colors.onSurface),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectList(MiuixColors colors) {
    if (_configs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              uiIcon(
                UiIcons.layers,
                size: 46,
                color: colors.onSurfaceVariantSummary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                '还没有远程位置',
                style: TextStyle(fontSize: 15, color: colors.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                '支持 FTP / SFTP / WebDAV',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
              const SizedBox(height: 20),
              MiuixButton(
                onPressed: _addConnection,
                child: const Text('添加远程位置'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _configs.length,
      itemBuilder: (ctx, i) {
        final c = _configs[i];
        return AppListTile(
          leading: uiIcon(UiIcons.layers, size: 22, color: colors.primary),
          title: Text(c.name, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            '${c.typeLabel} · ${c.summary}',
            style: const TextStyle(fontSize: 11.5),
          ),
          trailing: IconButton(
            icon: uiIcon(UiIcons.delete, size: 19, color: colors.error),
            onPressed: () => setState(() => _configs.removeAt(i)),
          ),
          onTap: () => _connect(c),
        );
      },
    );
  }

  Widget _buildBrowser(MiuixColors colors) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colors.error),
          ),
        ),
      );
    }

    return Column(
      children: [
        // 路径栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              if (_remotePath != '/')
                IconButton(
                  onPressed: () => _openDir(p.posix.dirname(_remotePath)),
                  icon: uiIcon(UiIcons.up, size: 20, color: colors.primary),
                ),
              Expanded(
                child: Text(
                  _remotePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: _items.length,
            itemBuilder: (ctx, i) {
              final it = _items[i];
              return AppListTile(
                leading: uiIcon(
                  it.isDirectory ? UiIcons.folder : UiIcons.file,
                  size: 22,
                  color: it.isDirectory ? colors.primary : colors.onSurfaceVariantSummary,
                ),
                title: Text(
                  it.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
                subtitle: Text(
                  it.isDirectory ? '目录' : formatSize(it.size),
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: it.isDirectory
                    ? null
                    : IconButton(
                        icon: uiIcon(UiIcons.download,
                            size: 19, color: colors.primary),
                        onPressed: () => _download(it),
                      ),
                onTap: it.isDirectory ? () => _openDir(it.path) : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 添加远程连接的对话框
class _AddRemoteDialog extends StatefulWidget {
  const _AddRemoteDialog();

  @override
  State<_AddRemoteDialog> createState() => _AddRemoteDialogState();
}

class _AddRemoteDialogState extends State<_AddRemoteDialog> {
  String _type = 'ftp';
  final _host = TextEditingController();
  final _port = TextEditingController(text: '21');
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _path = TextEditingController(text: '/');
  final _name = TextEditingController();

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    _path.dispose();
    _name.dispose();
    super.dispose();
  }

  void _onTypeChanged(String t) {
    setState(() {
      _type = t;
      // 切换类型时给默认端口
      _port.text = switch (t) {
        'sftp' => '22',
        'webdav' => '80',
        _ => '21',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return AlertDialog(
      title: const Text('添加远程位置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final t in const ['ftp', 'sftp', 'webdav']) ...[
                  if (t != 'ftp') const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _onTypeChanged(t),
                      child: Container(
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _type == t
                              ? colors.primary
                              : colors.onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          t.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: _type == t
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: _type == t
                                ? colors.onPrimary
                                : colors.onSurfaceVariantSummary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _field(_name, '名称（可选）', '我的服务器'),
            _field(_host, '主机', '192.168.1.1'),
            _field(_port, '端口', '21', number: true),
            _field(_user, '用户名', 'anonymous'),
            _field(_pass, '密码', '', obscure: true),
            _field(_path, '初始路径', '/'),
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
            if (_host.text.trim().isEmpty) return;
            final host = _host.text.trim();
            Navigator.of(context).pop(
              RemoteConfig(
                name: _name.text.trim().isEmpty ? host : _name.text.trim(),
                type: _type,
                host: host,
                port: int.tryParse(_port.text.trim()) ??
                    (switch (_type) {
                      'sftp' => 22,
                      'webdav' => 80,
                      _ => 21,
                    }),
                username: _user.text.trim(),
                password: _pass.text,
                path: _path.text.trim().isEmpty ? '/' : _path.text.trim(),
              ),
            );
          },
          child: const Text('连接'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    String hint, {
    bool obscure = false,
    bool number = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
