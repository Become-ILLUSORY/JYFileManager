// 文件操作服务：复制、移动、删除、批量操作（带进度与冲突处理）
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/models/file_item.dart';
import 'local_fs.dart';
import 'vfs.dart';

/// 操作进度
class OperationProgress {
  final String currentFile;
  final int done;
  final int total;
  final bool isCounting;

  const OperationProgress({
    this.currentFile = '',
    this.done = 0,
    this.total = 0,
    this.isCounting = false,
  });

  double get fraction => total <= 0 ? 0 : done / total;
}

/// 冲突处理结果
class ConflictResolution {
  final ConflictAction action;
  final bool applyToAll;
  const ConflictResolution(this.action, {this.applyToAll = false});
}

/// 文件操作服务
class FileOperations {
  FileOperations._();
  static final FileOperations instance = FileOperations._();

  final _local = LocalFs.instance;

  /// 冲突回调：由 UI 提供对话框
  Future<ConflictResolution> Function(String src, String dst)?
      onConflict;

  /// 进度回调
  void Function(OperationProgress progress)? onProgress;

  /// 取消标志
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void resetCancel() => _cancelled = false;

  /// 计算一组文件的总大小（用于进度显示）
  Future<int> totalSize(List<FileItem> items) async {
    var total = 0;
    for (final item in items) {
      if (item.isDirectory) {
        total += await _local.dirSize(item.path);
      } else {
        total += item.size;
      }
    }
    return total;
  }

  /// 复制多个条目到目标目录
  Future<int> copyItems(List<FileItem> sources, String destDir,
      {bool move = false}) async {
    resetCancel();
    var count = 0;
    final total = sources.length;
    for (final src in sources) {
      if (_cancelled) break;
      onProgress?.call(OperationProgress(
          currentFile: src.name, done: count, total: total));
      try {
        await _copyRecursive(src.path, destDir, src.isDirectory);
        if (move) {
          await _local.delete(src.path, recursive: true);
        }
        count++;
      } catch (e) {
        // 记录失败但继续
        // ignore: avoid_print
        print('复制失败: ${src.path} -> $e');
      }
    }
    onProgress?.call(OperationProgress(
        currentFile: '', done: count, total: total));
    return count;
  }

  /// 递归复制（目录树）
  Future<void> _copyRecursive(
      String srcPath, String destDir, bool isDir) async {
    final name = p.basename(srcPath);
    var destPath = p.join(destDir, name);

    // 冲突处理
    if (await _local.exists(destPath)) {
      if (onConflict != null) {
        final res = await onConflict!(srcPath, destPath);
        switch (res.action) {
          case ConflictAction.skip:
          case ConflictAction.cancel:
            return;
          case ConflictAction.overwrite:
            await _local.delete(destPath, recursive: true);
          case ConflictAction.keepBoth:
            destPath = await _uniquePath(destPath);
        }
      } else {
        // 默认保留两者
        destPath = await _uniquePath(destPath);
      }
    }

    if (isDir) {
      await _local.mkdir(destPath);
      final children = await _local.list(srcPath);
      for (final child in children) {
        if (_cancelled) return;
        await _copyRecursive(child.path, destPath, child.isDirectory);
      }
      // 保留修改时间
      try {
        final stat = await _local.stat(srcPath);
        await _setModified(destPath, stat.modified);
      } catch (_) {}
    } else {
      await _copyFile(srcPath, destPath);
    }
  }

  /// 复制单个文件（流式，支持大文件）
  Future<void> _copyFile(String src, String dst) async {
    final input = File(src).openRead();
    final output = File(dst).openWrite();
    try {
      await input.pipe(output);
    } catch (e) {
      await output.close();
      rethrow;
    }
    try {
      final stat = await File(src).stat();
      await _setModified(dst, stat.modified);
    } catch (_) {}
  }

  Future<void> _setModified(String path, DateTime time) async {
    try {
      await Process.run('touch',
          ['-d', time.toIso8601String(), '--', path]);
    } catch (_) {}
  }

  /// 生成不冲突的路径：name (1).ext
  Future<String> _uniquePath(String path) async {
    final dir = p.dirname(path);
    final ext = p.extension(path);
    final base = p.basenameWithoutExtension(path);
    var i = 1;
    var candidate = path;
    while (await _local.exists(candidate)) {
      candidate = p.join(dir, '$base ($i)$ext');
      i++;
      if (i > 9999) break;
    }
    return candidate;
  }

  /// 删除多个条目
  Future<int> deleteItems(List<FileItem> items) async {
    resetCancel();
    var count = 0;
    for (final item in items) {
      if (_cancelled) break;
      try {
        await _local.delete(item.path, recursive: true);
        count++;
      } catch (_) {}
      onProgress?.call(OperationProgress(
          currentFile: item.name, done: count, total: items.length));
    }
    return count;
  }

  /// 重命名
  Future<void> rename(String path, String newName) async {
    final parent = p.dirname(path);
    final newPath = p.join(parent, newName);
    if (newPath == path) return;
    if (await _local.exists(newPath)) {
      throw VfsException('同名文件已存在', newPath);
    }
    await _local.rename(path, newPath);
  }

  /// 批量重命名
  Future<int> batchRename(List<FileItem> items, String Function(int index, FileItem item) nameBuilder) async {
    var count = 0;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final newName = nameBuilder(i, item);
      if (newName == item.name || newName.isEmpty) continue;
      try {
        await rename(item.path, newName);
        count++;
      } catch (_) {}
    }
    return count;
  }

  /// 新建文件
  Future<void> createFile(String path, [String content = '']) async {
    if (await _local.exists(path)) {
      throw VfsException('文件已存在', path);
    }
    await _local.writeBytes(path, content.codeUnits);
  }

  /// 新建目录
  Future<void> createDirectory(String path) async {
    if (await _local.exists(path)) {
      throw VfsException('目录已存在', path);
    }
    await _local.mkdir(path);
  }

  /// 计算目录大小（异步）
  Future<int> calculateDirSize(String path) async {
    return _local.dirSize(path);
  }

  /// 计算校验和
  Future<Map<String, String>> calculateChecksums(String path) async {
    final result = <String, String>{};
    try {
      final file = File(path);
      final length = await file.length();
      result['size'] = '$length';

      // 大文件流式计算，避免占用大量内存
      final md5c = _DigestSink();
      final sha1c = _DigestSink();
      final sha256c = _DigestSink();
      final md5s = md5.startChunkedConversion(md5c);
      final sha1s = sha1.startChunkedConversion(sha1c);
      final sha256s = sha256.startChunkedConversion(sha256c);

      await for (final chunk in file.openRead()) {
        md5s.add(chunk);
        sha1s.add(chunk);
        sha256s.add(chunk);
      }
      md5s.close();
      sha1s.close();
      sha256s.close();

      result['md5'] = md5c.value;
      result['sha1'] = sha1c.value;
      result['sha256'] = sha256c.value;
    } catch (e) {
      result['error'] = '$e';
    }
    return result;
  }
}

/// 收集 Digest 的轻量 Sink
class _DigestSink implements Sink<Digest> {
  Digest? _last;
  String get value => _last?.toString() ?? '';
  @override
  void add(Digest data) => _last = data;
  @override
  void close() {}
}
