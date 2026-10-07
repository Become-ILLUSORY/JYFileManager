// 本地文件系统实现（dart:io）
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/models/file_item.dart';
import 'vfs.dart';

/// 基于 dart:io 的本地文件系统
class LocalFs extends Vfs {
  LocalFs._();
  static final LocalFs instance = LocalFs._();

  @override
  String get schemeName => '本地';

  @override
  String get rootPath => '/';

  @override
  Future<List<FileItem>> list(String path, {bool showHidden = true}) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      throw VfsException('目录不存在', path);
    }
    final items = <FileItem>[];
    await for (final entity in dir.list(followLinks: false)) {
      try {
        final stat = await entity.stat();
        String? linkTarget;
        if (entity is Link) {
          try {
            linkTarget = await entity.target();
          } catch (_) {}
        }
        final item = _itemFromStat(entity, stat, linkTarget: linkTarget);
        if (!showHidden && item.isHidden) continue;
        items.add(item);
      } catch (_) {
        // 单个条目失败不影响整体
      }
    }
    return items;
  }

  @override
  Future<VfsStat> stat(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return const VfsStat.notFound();
    }
    final stat = await FileStat.stat(path);
    String? linkTarget;
    if (type == FileSystemEntityType.link) {
      try {
        linkTarget = await Link(path).target();
      } catch (_) {}
    }
    return VfsStat(
      exists: true,
      isDirectory: type == FileSystemEntityType.directory,
      isLink: type == FileSystemEntityType.link,
      linkTarget: linkTarget,
      size: stat.size,
      modified: stat.modified,
      mode: stat.mode,
    );
  }

  @override
  Future<bool> exists(String path) async {
    return (await FileSystemEntity.type(path, followLinks: false)) !=
        FileSystemEntityType.notFound;
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    return await File(path).readAsBytes();
  }

  @override
  Future<Uint8List> readHead(String path, {int limit = 8192}) async {
    final f = File(path);
    final raf = await f.open();
    try {
      final len = await raf.length();
      final n = len < limit ? len : limit;
      return await raf.read(n);
    } finally {
      await raf.close();
    }
  }

  @override
  Stream<List<int>> openRead(String path, {int? start, int? end}) {
    return File(path).openRead(start ?? 0, end);
  }

  @override
  Future<void> writeBytes(String path, List<int> data) async {
    await File(path).writeAsBytes(data, flush: true);
  }

  @override
  Future<void> mkdir(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> delete(String path, {bool recursive = true}) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(path).delete(recursive: recursive);
      case FileSystemEntityType.file:
        await File(path).delete();
      case FileSystemEntityType.link:
        await Link(path).delete();
      default:
        break;
    }
  }

  @override
  Future<void> rename(String path, String newPath) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(path).rename(newPath);
      case FileSystemEntityType.file:
        await File(path).rename(newPath);
      case FileSystemEntityType.link:
        await Link(path).rename(newPath);
      default:
        throw VfsException('源不存在', path);
    }
  }

  @override
  Future<void> copy(String src, String dst) async {
    await File(src).copy(dst);
  }

  @override
  Future<int> length(String path) async {
    return await File(path).length();
  }

  @override
  String normalize(String path) {
    final parts = path.split('/');
    final stack = <String>[];
    for (final part in parts) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (stack.isNotEmpty) stack.removeLast();
      } else {
        stack.add(part);
      }
    }
    return '/${stack.join('/')}';
  }

  /// 应用启动时的默认路径：优先外部存储根目录
  Future<String> defaultStartPath() async {
    const candidates = [
      '/storage/emulated/0',
      '/sdcard',
      '/storage',
    ];
    for (final c in candidates) {
      try {
        if (await Directory(c).exists()) return c;
      } catch (_) {}
    }
    return '/';
  }

  /// 获取挂载的存储卷列表（Android 特有路径探测）
  Future<List<StorageVolume>> detectStorageVolumes() async {
    final volumes = <StorageVolume>[];
    // 内部存储
    volumes.add(const StorageVolume('内部存储', '/storage/emulated/0', 'emulated'));
    // 外置 SD 卡常见路径
    final candidates = <String>[
      '/storage',
      '/mnt/media_rw',
    ];
    for (final base in candidates) {
      try {
        final dir = Directory(base);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(followLinks: false)) {
          final name = entity.path.split('/').last;
          if (name == 'emulated' || name == 'self') continue;
          if (name.length > 16) continue; // 排除 tmpfs 等
          if (entity is Directory) {
            try {
              if (await Directory('${entity.path}/Android').exists() ||
                  await Directory('${entity.path}/DCIM').exists()) {
                volumes.add(StorageVolume('外置存储 ($name)', entity.path, name));
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    // 去重
    final seen = <String>{};
    return volumes.where((v) => seen.add(v.path)).toList();
  }
}

/// 从 dart:io 的实体与 stat 构建 [FileItem]。
///
/// 放在本地实现里（而非模型层），让模型与 UI 层保持跨平台。
FileItem _itemFromStat(
  FileSystemEntity entity,
  FileStat stat, {
  String? linkTarget,
}) {
  final isDir = stat.type == FileSystemEntityType.directory;
  return FileItem(
    name: FileItem.basenameOf(entity.path),
    path: entity.path,
    isDirectory: isDir,
    isLink: entity is Link,
    linkTarget: linkTarget,
    size: isDir ? 0 : stat.size,
    modified: stat.modified,
    accessed: stat.accessed,
    changed: stat.changed,
    mode: stat.mode,
  );
}

/// 存储卷描述
class StorageVolume {  final String label;
  final String path;
  final String id;
  const StorageVolume(this.label, this.path, this.id);
}
