// 虚拟文件系统抽象层
//
// 所有文件操作（本地 / Root / 压缩包内 / 远程）统一走 [Vfs] 接口，
// UI 层与具体实现完全解耦。
import 'dart:async';
import 'dart:typed_data';

import '../../core/models/file_item.dart';

/// 文件统计信息（stat）
class VfsStat {
  final bool exists;
  final bool isDirectory;
  final bool isLink;
  final String? linkTarget;
  final int size;
  final DateTime modified;
  final int? mode;

  const VfsStat({
    required this.exists,
    this.isDirectory = false,
    this.isLink = false,
    this.linkTarget,
    this.size = 0,
    required this.modified,
    this.mode,
  });

  const VfsStat.notFound()
      : exists = false,
        isDirectory = false,
        isLink = false,
        linkTarget = null,
        size = 0,
        modified = const _EpochTime(),
        mode = null;
}

class _EpochTime implements DateTime {
  const _EpochTime();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// 文件操作进度回调
typedef ProgressCallback = void Function(int current, int total, String name);

/// 虚拟文件系统接口
abstract class Vfs {
  /// 文件系统标识（用于 UI 显示）
  String get schemeName;

  /// 路径分隔符
  String get separator => '/';

  /// 根路径
  String get rootPath;

  /// 列出目录内容
  Future<List<FileItem>> list(String path, {bool showHidden = true});

  /// 获取文件信息
  Future<VfsStat> stat(String path);

  /// 判断路径是否存在
  Future<bool> exists(String path);

  /// 读取文件全部字节
  Future<Uint8List> readBytes(String path);

  /// 以流方式读取（大文件）
  Stream<List<int>> openRead(String path, {int? start, int? end});

  /// 写入文件（覆盖）
  Future<void> writeBytes(String path, List<int> data);

  /// 创建目录
  Future<void> mkdir(String path);

  /// 删除文件或目录
  Future<void> delete(String path, {bool recursive = true});

  /// 重命名/移动
  Future<void> rename(String path, String newPath);

  /// 复制文件（同一文件系统内）
  Future<void> copy(String src, String dst);

  /// 获取文件长度
  Future<int> length(String path);

  /// 规范化路径
  String normalize(String path);

  /// 拼接路径
  String join(String parent, String child) {
    if (parent.endsWith('/')) return '$parent$child';
    return '$parent/$child';
  }

  /// 父目录
  String parent(String path) {
    var p = path;
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    final idx = p.lastIndexOf('/');
    if (idx < 0) return p;
    if (idx == 0) return '/';
    return p.substring(0, idx);
  }

  /// 文件名
  String basename(String path) {
    var p = path;
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    final idx = p.lastIndexOf('/');
    return idx < 0 ? p : p.substring(idx + 1);
  }

  /// 释放资源
  Future<void> dispose() async {}

  /// 计算目录大小（递归）
  Future<int> dirSize(String path, {ProgressCallback? onProgress}) async {
    var total = 0;
    final children = await list(path);
    for (final child in children) {
      if (child.isDirectory && !child.isLink) {
        total += await dirSize(child.path, onProgress: onProgress);
      } else {
        total += child.size;
      }
    }
    return total;
  }

  /// 递归统计文件和目录数量
  Future<(int, int)> countChildren(String path) async {
    var files = 0, dirs = 0;
    final children = await list(path);
    for (final child in children) {
      if (child.isDirectory && !child.isLink) {
        dirs++;
        final sub = await countChildren(child.path);
        files += sub.$1;
        dirs += sub.$2;
      } else {
        files++;
      }
    }
    return (files, dirs);
  }
}

/// 文件系统异常
class VfsException implements Exception {
  final String message;
  final String? path;
  const VfsException(this.message, [this.path]);

  @override
  String toString() => path == null ? message : '$message: $path';
}

/// 权限不足异常。
///
/// 与普通 [VfsException] 区分开，便于 UI 层弹「无权限」提示
/// 并引导用户去开启 Root 访问。
class PermissionException extends VfsException {
  const PermissionException([
    super.message = '没有访问权限',
    super.path,
  ]);
}

/// 文件操作冲突处理策略
enum ConflictAction {
  /// 覆盖
  overwrite,

  /// 跳过
  skip,

  /// 保留两者（自动重命名）
  keepBoth,

  /// 对全部应用
  cancel,
}

/// 复制/移动任务描述
class FileTransferTask {
  final List<FileItem> sources;
  final String destDir;
  final bool isMove;

  const FileTransferTask({
    required this.sources,
    required this.destDir,
    required this.isMove,
  });
}
