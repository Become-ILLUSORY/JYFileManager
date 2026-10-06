// 书签与快捷位置模型
import 'dart:convert';

import 'package:flutter/material.dart';

/// 书签条目
class Bookmark {
  final String name;
  final String path;

  /// 图标代码点（存储时用 int，避免 IconData 序列化问题）
  final int iconCode;
  final bool isBuiltin;

  const Bookmark({
    required this.name,
    required this.path,
    this.iconCode = 0xe2c7, // Icons.folder_rounded
    this.isBuiltin = false,
  });

  IconData get icon => IconData(iconCode, fontFamily: 'MaterialIcons'); // ignore: non_const_argument_for_const_parameter
  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'iconCode': iconCode,
        'isBuiltin': isBuiltin,
      };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        name: json['name'] as String,
        path: json['path'] as String,
        iconCode: json['iconCode'] as int? ?? 0xe2c7,
        isBuiltin: json['isBuiltin'] as bool? ?? false,
      );

  Bookmark copyWith({String? name, String? path, int? iconCode}) => Bookmark(
        name: name ?? this.name,
        path: path ?? this.path,
        iconCode: iconCode ?? this.iconCode,
        isBuiltin: isBuiltin,
      );
}

/// 书签存储：内置 + 用户自定义
class BookmarkStore {
  BookmarkStore._();
  static final BookmarkStore instance = BookmarkStore._();

  /// 内置快捷位置
  static final List<Bookmark> builtin = [
    const Bookmark(
        name: '内部存储',
        path: '/storage/emulated/0',
        iconCode: 0xe1db, // Icons.sd_storage_rounded
        isBuiltin: true),
    const Bookmark(
        name: '根目录', path: '/', iconCode: 0xe88a, isBuiltin: true),
    const Bookmark(
        name: '下载',
        path: '/storage/emulated/0/Download',
        iconCode: 0xe2c4, // Icons.download_rounded
        isBuiltin: true),
    const Bookmark(
        name: '图片',
        path: '/storage/emulated/0/Pictures',
        iconCode: 0xe413, // Icons.image_rounded
        isBuiltin: true),
    const Bookmark(
        name: '相机',
        path: '/storage/emulated/0/DCIM',
        iconCode: 0xe412, // Icons.photo_camera_rounded
        isBuiltin: true),
    const Bookmark(
        name: '文档',
        path: '/storage/emulated/0/Documents',
        iconCode: 0xe24d, // Icons.description_rounded
        isBuiltin: true),
    const Bookmark(
        name: '音乐',
        path: '/storage/emulated/0/Music',
        iconCode: 0xe405, // Icons.music_note_rounded
        isBuiltin: true),
    const Bookmark(
        name: '视频',
        path: '/storage/emulated/0/Movies',
        iconCode: 0xe02c, // Icons.movie_rounded
        isBuiltin: true),
    const Bookmark(
        name: '应用数据',
        path: '/data/app',
        iconCode: 0xe8d4, // Icons.memory_rounded
        isBuiltin: true),
    const Bookmark(
        name: '系统',
        path: '/system',
        iconCode: 0xe8b8, // Icons.settings_applications
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
