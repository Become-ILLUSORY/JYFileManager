// 挂载点的编辑跟踪：记录在压缩包内做过的改动，退出时询问是否保存。
//
// 交互（对齐成熟文件管理器的做法）：
//   1. 在压缩包里编辑/新增/删除文件 → 改动先记在内存里
//   2. 返回到压缩包外（回到上级）时，若存在未保存改动 → 弹窗询问
//   3. 保存时：原压缩包改名加 .bak 备份，再写出包含改动的新压缩包
import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import 'mount.dart';

/// 一处改动
class MountChange {
  MountChange({
    required this.innerPath,
    required this.kind,
    this.data,
  });

  /// 压缩包内的路径（不含挂载前缀）
  final String innerPath;

  /// write / delete
  final String kind;

  /// 新内容（删除时为 null）
  final Uint8List? data;

  String get actionLabel => kind == 'delete' ? '删除' : '修改';
}

/// 某个挂载点的改动集合
class MountEdits extends ChangeNotifier {
  MountEdits(this.mount);

  final Mount mount;
  final List<MountChange> _changes = [];
  List<MountChange> get changes => List.unmodifiable(_changes);

  bool get isEmpty => _changes.isEmpty;
  bool get isNotEmpty => _changes.isNotEmpty;
  int get count => _changes.length;

  /// 记录一次写入（同路径覆盖前一条）
  void recordWrite(String innerPath, Uint8List data) {
    _changes.removeWhere((c) => c.innerPath == innerPath);
    _changes.add(MountChange(
      innerPath: innerPath,
      kind: 'write',
      data: data,
    ));
    notifyListeners();
  }

  /// 记录一次删除
  void recordDelete(String innerPath) {
    _changes.removeWhere((c) => c.innerPath == innerPath);
    _changes.add(MountChange(innerPath: innerPath, kind: 'delete'));
    notifyListeners();
  }

  void clear() {
    _changes.clear();
    notifyListeners();
  }
}

/// 全局编辑跟踪表
class MountEditStore {
  MountEditStore._();
  static final MountEditStore instance = MountEditStore._();

  final Map<String, MountEdits> _byRoot = {};

  /// 取某个挂载点的改动记录（没有则创建）
  MountEdits forRoot(Mount mount) =>
      _byRoot.putIfAbsent(mount.root, () => MountEdits(mount));

  /// 查询（不创建）
  MountEdits? peek(String root) => _byRoot[root];

  /// 是否有未保存改动
  bool hasEdits(String root) => (_byRoot[root]?.count ?? 0) > 0;

  void drop(String root) {
    _byRoot.remove(root);
  }

  /// 把改动应用到压缩包并写出新文件
  ///
  /// 步骤：原文件 → 改名加 .bak；再把「原内容 + 改动」写成新压缩包。
  /// 返回新压缩包的路径。
  static Future<String> saveArchive({
    required String archivePath,
    required Archive base,
    required List<MountChange> changes,
  }) async {
    // 1) 先备份原文件
    final bakPath = '$archivePath.bak';
    final src = File(archivePath);
    if (await src.exists()) {
      // 已有同名备份时先删掉，避免备份失败
      final bak = File(bakPath);
      if (await bak.exists()) await bak.delete();
      await src.rename(bakPath);
    }

    // 2) 应用改动到归档对象
    for (final c in changes) {
      final name = c.innerPath.startsWith('/')
          ? c.innerPath.substring(1)
          : c.innerPath;

      // 先移除旧条目（如果有）
      base.files.removeWhere((f) => f.name == name);

      if (c.kind == 'delete') continue;

      final data = c.data ?? Uint8List(0);
      base.add(ArchiveFile(name, data.length, data));
    }

    // 3) 写出新压缩包
    final bytes = ZipEncoder().encode(base, level: DeflateLevel.defaultCompression);
    await src.writeAsBytes(bytes, flush: true);

    return archivePath;
  }
}
