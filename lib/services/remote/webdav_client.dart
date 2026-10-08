// WebDAV 客户端。
//
// 相比初版修掉的问题：
//   1. 没有超时保护 —— 服务器不可达时 openUrl 会长时间挂起，
//      界面上表现为「点了连接没反应」。现在统一加超时。
//   2. 协议写死 http —— 443 端口 / https 服务连不上。
//      现在按端口自动判断，也允许显式指定。
//   3. rootPath 没传给客户端 —— 用户填的初始路径被忽略。
//   4. PROPFIND 的 Depth 头不规范，部分服务器直接拒绝。
//   5. 状态码判断太粗（401 与 404 报同样的错），排错困难。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart' as xml;

import 'remote_client.dart';

class WebDavRemoteClient implements RemoteClient {
  WebDavRemoteClient({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.protocol,
    this.rootPath = '/',
    this.trustAllCerts = true,
  }) {
    _httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..idleTimeout = const Duration(seconds: 10)
      // 自签名证书：默认放行（家用 NAS 基本都是自签），
      // 但保留开关，用户可在连接配置里关掉
      ..badCertificateCallback =
          (_, _, _) => trustAllCerts;
  }

  final String host;
  final int port;
  final String username;
  final String password;

  /// 显式指定协议；为 null 时按端口推断（443 → https，其余 http）
  final String? protocol;

  /// 根路径（WebDAV 服务通常挂在 /dav 这类子路径下）
  final String rootPath;

  /// 是否信任自签名证书
  final bool trustAllCerts;

  late final HttpClient _httpClient;

  // ---------- URL 解析 ----------
  //
  // 用户可能填各种形式：
  //   192.168.1.5
  //   192.168.1.5:5244
  //   http://192.168.1.5:5244/dav
  //   https://nas.example.com/dav/
  //
  // 早期实现直接 split('/').first，把 /dav 这种路径丢掉了，
  // 于是 PROPFIND 打到服务器根路径 → 服务端返回 405 Method Not Allowed。
  // 这里完整解析出 scheme / host / port / path 四部分。

  String get _scheme {
    if (protocol != null && protocol!.isNotEmpty) return protocol!;
    final h = host.trim().toLowerCase();
    if (h.startsWith('https://')) return 'https';
    if (h.startsWith('http://')) return 'http';
    return port == 443 ? 'https' : 'http';
  }

  /// 纯主机名（去掉协议、端口、路径）
  String get _hostOnly {
    var h = host.trim();
    if (h.startsWith('http://')) h = h.substring(7);
    if (h.startsWith('https://')) h = h.substring(8);
    if (h.contains('/')) h = h.split('/').first;
    if (h.contains(':')) h = h.split(':').first;
    return h;
  }

  /// 从 host 字段里解析出的端口（没写则返回 null）
  int? get _portFromHost {
    var h = host.trim();
    if (h.startsWith('http://')) h = h.substring(7);
    if (h.startsWith('https://')) h = h.substring(8);
    if (h.contains('/')) h = h.split('/').first;
    if (!h.contains(':')) return null;
    return int.tryParse(h.split(':').last);
  }

  /// 从 host 字段里解析出的路径（没写则返回 null）
  String? get _pathFromHost {
    var h = host.trim();
    if (h.startsWith('http://')) h = h.substring(7);
    if (h.startsWith('https://')) h = h.substring(8);
    final slash = h.indexOf('/');
    if (slash < 0) return null;
    final p = h.substring(slash);
    return p.isEmpty ? null : p;
  }

  /// 实际使用的端口：优先用 host 里写的
  int get _effectivePort => _portFromHost ?? port;

  String get _baseUrl => '$_scheme://$_hostOnly:$_effectivePort';

  /// 实际使用的根路径：
  /// 优先用 host 里带的路径（用户直接粘了完整 URL 的情况），
  /// 否则用配置里的 rootPath。
  String get _effectiveRoot {
    final fromHost = _pathFromHost;
    if (fromHost != null && fromHost != '/') return _norm(fromHost);
    return _norm(rootPath);
  }

  String? get _authHeader {
    if (username.isEmpty && password.isEmpty) return null;
    return 'Basic ${base64.encode(utf8.encode('$username:$password'))}';
  }

  /// 规范化路径（保证以 / 开头）
  String _norm(String path) {
    var p = path.trim();
    if (p.isEmpty) p = '/';
    if (!p.startsWith('/')) p = '/$p';
    return p;
  }

  /// 带超时的请求执行
  Future<HttpClientResponse> _send(
    String method,
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final url = Uri.parse('$_baseUrl${_norm(path)}');
    final request = await _httpClient.openUrl(method, url).timeout(timeout);
    final auth = _authHeader;
    if (auth != null) request.headers.set('Authorization', auth);
    headers?.forEach(request.headers.set);
    return request.close().timeout(timeout);
  }

  @override
  Future<void> connect() async {
    final root = _effectiveRoot;
    try {
      final response = await _send('PROPFIND', root, headers: {'Depth': '0'});
      final code = response.statusCode;
      await response.drain<void>().catchError((_) {});

      if (code == 401) {
        throw Exception('认证失败（401）：请检查用户名与密码');
      }
      if (code == 403) {
        throw Exception('拒绝访问（403）：账号可能无权限');
      }
      if (code == 404) {
        throw Exception('路径不存在（404）：$_baseUrl$root');
      }
      if (code == 405) {
        // 405 = 方法不被允许。常见于：
        //   · 根路径不是 WebDAV 端点（服务挂在 /dav 之类的子路径）
        //   · 服务器要求走 https
        throw Exception(
          '服务器不接受 WebDAV 请求（405）\n'
          '地址：$_baseUrl$root\n'
          '请确认「初始路径」填的是 WebDAV 端点\n'
          '（例如 OpenList/AList 通常是 /dav，Nextcloud 是 /remote.php/dav）',
        );
      }
      if (code >= 400) {
        throw Exception('连接失败（HTTP $code）$_baseUrl$root');
      }
    } on TimeoutException {
      throw Exception(
        '连接超时：$_baseUrl 无响应\n请检查地址、端口是否可达，以及是否为 https',
      );
    } on SocketException catch (e) {
      throw Exception('无法连接到 $_baseUrl\n${e.message}');
    } on HandshakeException catch (e) {
      throw Exception(
        '证书校验失败：$_baseUrl\n${e.message}\n'
        '可在连接配置里开启「信任自签名证书」后重试',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    _httpClient.close(force: true);
  }

  @override
  Future<List<RemoteFileItem>> listDirectory(String path) async {
    // 传 '/' 或空时用配置里的根路径（WebDAV 常挂在子路径下）
    final target = (path.isEmpty || path == '/') ? _effectiveRoot : path;
    final response = await _send('PROPFIND', target, headers: {'Depth': '1'});
    if (response.statusCode >= 400) {
      await response.drain<void>().catchError((_) {});
      throw Exception('列目录失败（HTTP ${response.statusCode}）');
    }
    final body = await response.transform(utf8.decoder).join();

    final doc = xml.XmlDocument.parse(body);
    final items = <RemoteFileItem>[];
    final selfPath = _norm(target).replaceAll(RegExp(r'/+$'), '');

    for (final resp in doc.findAllElements('*', namespaceUri: 'DAV:')) {
      if (resp.name.local != 'response') continue;

      final hrefEl = resp
          .findElements('*', namespaceUri: 'DAV:')
          .where((e) => e.name.local == 'href')
          .firstOrNull;
      if (hrefEl == null) continue;

      var href = Uri.decodeFull(hrefEl.innerText.trim());
      // 转成相对路径
      var rel = href;
      final idx = rel.indexOf('://');
      if (idx >= 0) {
        final slash = rel.indexOf('/', idx + 3);
        rel = slash >= 0 ? rel.substring(slash) : '/';
      }
      rel = rel.replaceAll(RegExp(r'/+$'), '');
      if (rel.isEmpty) rel = '/';
      if (rel == selfPath) continue; // 跳过自身

      final name = rel.split('/').last;
      if (name.isEmpty) continue;

      // 目录判定：resourcetype 里含 collection
      var isDir = false;
      for (final rt in resp.findAllElements('*', namespaceUri: 'DAV:')) {
        if (rt.name.local == 'collection') {
          isDir = true;
          break;
        }
      }

      var size = 0;
      final lenEl = resp
          .findElements('*', namespaceUri: 'DAV:')
          .where((e) => e.name.local == 'getcontentlength')
          .firstOrNull;
      if (lenEl != null) size = int.tryParse(lenEl.innerText.trim()) ?? 0;

      DateTime modified = DateTime.now();
      final modEl = resp
          .findElements('*', namespaceUri: 'DAV:')
          .where((e) => e.name.local == 'getlastmodified')
          .firstOrNull;
      if (modEl != null) {
        try {
          modified = HttpDate.parse(modEl.innerText.trim());
        } catch (_) {}
      }

      items.add(RemoteFileItem(
        name: name,
        path: rel,
        isDirectory: isDir,
        size: size,
        modified: modified,
      ));
    }

    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  @override
  Future<void> createDirectory(String path) async {
    final response = await _send('MKCOL', path);
    if (response.statusCode >= 400) {
      await response.drain<void>().catchError((_) {});
      throw Exception('创建目录失败（HTTP ${response.statusCode}）');
    }
    await response.drain<void>().catchError((_) {});
  }

  @override
  Future<void> delete(String path, bool isDir) async {
    final response = await _send('DELETE', path);
    if (response.statusCode >= 400) {
      await response.drain<void>().catchError((_) {});
      throw Exception('删除失败（HTTP ${response.statusCode}）');
    }
    await response.drain<void>().catchError((_) {});
  }

  @override
  Future<void> downloadFile(
    String remotePath,
    String localPath,
    Function(double) onProgress,
  ) async {
    final response = await _send('GET', remotePath);
    if (response.statusCode >= 400) {
      await response.drain<void>().catchError((_) {});
      throw Exception('下载失败（HTTP ${response.statusCode}）');
    }
    final total = response.contentLength;
    final sink = File(localPath).openWrite();
    var received = 0;
    await for (final chunk in response) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }
    await sink.close();
  }

  @override
  Future<void> uploadFile(
    String localPath,
    String remotePath,
    Function(double) onProgress,
  ) async {
    final file = File(localPath);
    if (!file.existsSync()) throw Exception('本地文件不存在：$localPath');
    final total = file.lengthSync();

    final url = Uri.parse('$_baseUrl${_norm(remotePath)}');
    final request = await _httpClient
        .openUrl('PUT', url)
        .timeout(const Duration(seconds: 15));
    final auth = _authHeader;
    if (auth != null) request.headers.set('Authorization', auth);
    request.headers.set('Content-Type', 'application/octet-stream');
    request.contentLength = total;

    var sent = 0;
    await for (final chunk in file.openRead()) {
      request.add(chunk);
      sent += chunk.length;
      if (total > 0) onProgress(sent / total);
    }
    final response =
        await request.close().timeout(const Duration(minutes: 5));
    if (response.statusCode >= 400) {
      await response.drain<void>().catchError((_) {});
      throw Exception('上传失败（HTTP ${response.statusCode}）');
    }
    await response.drain<void>().catchError((_) {});
  }
}
