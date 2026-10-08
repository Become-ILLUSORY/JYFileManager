// 远程位置的持久化存储。
//
// 之前每次进页面都要重新添加，现在保存到 SharedPreferences，
// 并且可以在左侧抽屉里直接看到、点击即连接。
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 一个远程位置配置
class RemoteLocation {
  const RemoteLocation({
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

  /// 初始路径
  final String path;

  String get typeLabel => switch (type) {
        'ftp' => 'FTP',
        'sftp' => 'SFTP',
        'webdav' => 'WebDAV',
        _ => type.toUpperCase(),
      };

  String get summary => '$host:$port$path';

  /// 唯一标识（用于去重与删除）
  String get id => '$type://$host:$port$path';

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'path': path,
      };

  factory RemoteLocation.fromJson(Map<String, dynamic> j) => RemoteLocation(
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? 'ftp',
        host: j['host'] as String? ?? '',
        port: j['port'] as int? ?? 21,
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
        path: j['path'] as String? ?? '/',
      );
}

/// 远程位置存储
class RemoteLocationStore extends ChangeNotifier {
  RemoteLocationStore._();
  static final RemoteLocationStore instance = RemoteLocationStore._();

  final List<RemoteLocation> _items = [];
  List<RemoteLocation> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  /// 从 JSON 字符串载入
  void loadFrom(String? jsonStr) {
    _items.clear();
    if (jsonStr == null || jsonStr.isEmpty) {
      notifyListeners();
      return;
    }
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _items.addAll(
        list.map((e) => RemoteLocation.fromJson(e as Map<String, dynamic>)),
      );
    } catch (_) {}
    notifyListeners();
  }

  String encode() => jsonEncode(_items.map((e) => e.toJson()).toList());

  /// 添加（同 id 视为更新）
  void upsert(RemoteLocation loc) {
    final i = _items.indexWhere((e) => e.id == loc.id);
    if (i >= 0) {
      _items[i] = loc;
    } else {
      _items.add(loc);
    }
    notifyListeners();
  }

  void remove(String id) {
    _items.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  bool contains(String id) => _items.any((e) => e.id == id);
}
