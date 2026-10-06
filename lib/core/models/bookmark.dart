// 书签与快捷位置模型
import 'dart:convert';

import 'package:flutter/material.dart';

/// 书签条目
class Bookmark {
  final String name;
  final String path;

  /// 图标键名（存储用字符串，图标本身来自常量表，避免动态 IconData
  /// 触发 `--tree-shake-icons` 失败）
  final String iconKey;
  final bool isBuiltin;

  const Bookmark({
    required this.name,
    required this.path,
    this.iconKey = 'folder',
    this.isBuiltin = false,
  });

  IconData get icon => bookmarkIcon(iconKey);

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'iconKey': iconKey,
        'isBuiltin': isBuiltin,
      };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        name: json['name'] as String,
        path: json['path'] as String,
        iconKey: json['iconKey'] as String? ?? 'folder',
        isBuiltin: json['isBuiltin'] as bool? ?? false,
      );

  Bookmark copyWith({String? name, String? path, String? iconKey}) => Bookmark(
        name: name ?? this.name,
        path: path ?? this.path,
        iconKey: iconKey ?? this.iconKey,
        isBuiltin: isBuiltin,
      );
}

/// 图标键 → 常量图标。
///
/// 全部为编译期常量，可被 `--tree-shake-icons` 正确裁剪。
IconData bookmarkIcon(String key) {
  switch (key) {
    case 'storage':
      return Icons.sd_storage_rounded;
    case 'root':
      return Icons.home_rounded;
    case 'download':
      return Icons.download_rounded;
    case 'image':
      return Icons.image_rounded;
    case 'camera':
      return Icons.photo_camera_rounded;
    case 'document':
      return Icons.description_rounded;
    case 'music':
      return Icons.music_note_rounded;
    case 'video':
      return Icons.movie_rounded;
    case 'memory':
      return Icons.memory_rounded;
    case 'system':
      return Icons.settings_applications_rounded;
    case 'star':
      return Icons.star_rounded;
    default:
      return Icons.folder_rounded;
  }
}

/// 书签存储：内置 + 用户自定义
class BookmarkStore {
  BookmarkStore._();
  static final BookmarkStore instance = BookmarkStore._();

  /// 内置快捷位置
  static const List<Bookmark> builtin = [
    Bookmark(
        name: '内部存储',
        path: '/storage/emulated/0',
        iconKey: 'storage',
        isBuiltin: true),
    Bookmark(name: '根目录', path: '/', iconKey: 'root', isBuiltin: true),
    Bookmark(
        name: '下载',
        path: '/storage/emulated/0/Download',
        iconKey: 'download',
        isBuiltin: true),
    Bookmark(
        name: '图片',
        path: '/storage/emulated/0/Pictures',
        iconKey: 'image',
        isBuiltin: true),
    Bookmark(
        name: '相机',
        path: '/storage/emulated/0/DCIM',
        iconKey: 'camera',
        isBuiltin: true),
    Bookmark(
        name: '文档',
        path: '/storage/emulated/0/Documents',
        iconKey: 'document',
        isBuiltin: true),
    Bookmark(
        name: '音乐',
        path: '/storage/emulated/0/Music',
        iconKey: 'music',
        isBuiltin: true),
    Bookmark(
        name: '视频',
        path: '/storage/emulated/0/Movies',
        iconKey: 'video',
        isBuiltin: true),
    Bookmark(
        name: '应用数据',
        path: '/data/app',
        iconKey: 'memory',
        isBuiltin: true),
    Bookmark(
        name: '系统',
        path: '/system',
        iconKey: 'system',
        isBuiltin: true),
  ];

  final List<Bookmark> _user = [];
  List<Bookmark> get user => List.unmodifiable(_user);

  /// 全部书签（用户在前）
  List<Bookmark> get all => [..._user, ...builtin];

  void loadFrom(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return;
    try {
      final list = jsonDecode(jsonStr) as List;
      _user
        ..clear()
        ..addAll(list.map((e) => Bookmark.fromJson(e as Map<String, dynamic>)));
    } catch (_) {}
  }

  String encode() => jsonEncode(_user.map((e) => e.toJson()).toList());

  void add(Bookmark bookmark) {
    _user.add(bookmark);
  }

  void removeAt(int index) {
    if (index >= 0 && index < _user.length) {
      _user.removeAt(index);
    }
  }

  void update(int index, Bookmark bookmark) {
    if (index >= 0 && index < _user.length) {
      _user[index] = bookmark;
    }
  }

  bool containsPath(String path) =>
      all.any((b) => b.path == path);
}
