// 挂载感知的文件系统：把 `/__mount__/...` 前缀的路径分发到对应的
// 压缩包 / 远程客户端，其余路径交给本地实现。
//
// 这样面板、导航、复制粘贴等所有上层代码都不用知道「当前看的是不是压缩包」，
// 只要照常按路径操作即可 —— 复制/移动也能自然地跨挂载点工作。
import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/models/file_item.dart';
import '../../core/models/mount.dart';
import '../../core/models/mount_edits.dart';
import '../remote/remote_client.dart';
import 'local_fs.dart';
import 'vfs.dart';

/// 挂载感知的文件系统
class MountAwareFs extends Vfs {
  MountAwareFs._();
  static final MountAwareFs instance = MountAwareFs._();

  final LocalFs _local = LocalFs.instance;

  /// 已打开的压缩包缓存（路径 → Archive）
  final Map<String, Archive> _archives = {};

  /// 远程客户端缓存（挂载根 → 客户端）
  final Map<String, RemoteClient> _clients = {};

  @override
  String get schemeName => '本地';

  @override
  String get rootPath => _local.rootPath;

  @override
  String normalize(String path) => path;

  // ---------- 挂载辅助 ----------

  /// 把远程位置挂载为一个面板根
  Future<String> mountRemote(RemoteClient client, RemoteLocationInfo info) async {
    final root = MountRegistry.instance.add(
      kind: MountKind.remote,
      label: info.label,
      sourcePath: info.sourcePath,
    );
    _clients[root] = client;
    return root;
  }

  /// 把压缩包挂载为一个面板根
  Future<String> mountArchive(String archivePath, String label) async {
    final root = MountRegistry.instance.add(
      kind: MountKind.archive,
      label: label,
      sourcePath: archivePath,
    );
    return root;
  }

  /// 卸载并释放资源
  void unmount(String root) {
    _clients.remove(root)?.disconnect();
    _archives.remove(root);
    MountRegistry.instance.remove(root);
  }

  /// 当前路径所属的挂载点
  Mount? mountOf(String path) => MountRegistry.instance.ownerOf(path);

  // ---------- Vfs 实现 ----------

  @override
  Future<List<FileItem>> list(String path, {bool showHidden = true}) async {
    final mount = mountOf(path);
    if (mount == null) return _local.list(path, showHidden: showHidden);

    final inner = MountRegistry.innerPath(path) ?? '/';

    switch (mount.kind) {
      case MountKind.archive:
        return _listArchive(mount, inner);
      case MountKind.remote:
        return _listRemote(mount, inner);
    }
  }

  /// 列出压缩包内某个目录
  Future<List<FileItem>> _listArchive(Mount mount, String inner) async {
    final archive = await _archiveOf(mount);
    if (archive == null) throw VfsException('无法读取压缩包', mount.sourcePath);

    final prefix = inner == '/' ? '' : '${inner.substring(1)}/';
    final seen = <String>{};
    final out = <FileItem>[];

    for (final f in archive.files) {
      final name = f.name;
      if (!name.startsWith(prefix)) continue;
      final rest = name.substring(prefix.length);
      if (rest.isEmpty) continue;

      final slash = rest.indexOf('/');
      if (slash >= 0) {
        // 子目录（折叠成一层）
        final dirName = rest.substring(0, slash);
        if (seen.add(dirName)) {
          out.add(FileItem(
            name: dirName,
            path: '${mount.root}$inner/$dirName'.replaceAll('//', '/'),
            isDirectory: true,
            modified: DateTime.fromMillisecondsSinceEpoch(
              f.lastModTime * 1000,
            ),
          ));
        }
      } else {
        if (seen.add(rest)) {
          out.add(FileItem(
            name: rest,
            path: '${mount.root}$inner/$rest'.replaceAll('//', '/'),
            isDirectory: false,
            size: f.size,
            modified: DateTime.fromMillisecondsSinceEpoch(
              f.lastModTime * 1000,
            ),
          ));
        }
      }
    }
    return out;
  }

  /// 列出远程目录
  Future<List<FileItem>> _listRemote(Mount mount, String inner) async {
    final client = _clients[mount.root];
    if (client == null) throw VfsException('远程连接已断开', mount.sourcePath);

    final items = await client.listDirectory(inner);
    return [
      for (final it in items)
        FileItem(
          name: it.name,
          path: '${mount.root}${it.path}'.replaceAll('//', '/'),
          isDirectory: it.isDirectory,
          size: it.size,
          modified: it.modified,
        ),
    ];
  }

  /// 公开访问：供保存流程取回归档对象
  Future<Archive?> archiveOf(String root) async {
    final m = MountRegistry.instance.byRoot(root);
    if (m == null) return null;
    return _archiveOf(m);
  }

  /// 取得（并按需打开）压缩包
  Future<Archive?> _archiveOf(Mount mount) async {
    final cached = _archives[mount.root];
    if (cached != null) return cached;
    try {
      final bytes = await _local.readBytes(mount.sourcePath);
      final archive = ZipDecoder().decodeBytes(bytes);
      _archives[mount.root] = archive;
      return archive;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<VfsStat> stat(String path) async {
    final mount = mountOf(path);
    if (mount == null) return _local.stat(path);

    final inner = MountRegistry.innerPath(path) ?? '/';
    // 挂载根一律当目录；更深的路径尝试按文件查一次
    if (inner == '/') {
      return VfsStat(
        exists: true,
        isDirectory: true,
        size: 0,
        modified: DateTime.now(),
      );
    }

    if (mount.kind == MountKind.archive) {
      final archive = await _archiveOf(mount);
      final f = archive?.findFile(inner.substring(1));
      if (f != null) {
        return VfsStat(
          exists: true,
          isDirectory: f.isFile == false,
          size: f.size,
          modified: DateTime.fromMillisecondsSinceEpoch(f.lastModTime * 1000),
        );
      }
    }
    return VfsStat(
      exists: true,
      isDirectory: true,
      size: 0,
      modified: DateTime.now(),
    );
  }

  @override
  Future<bool> exists(String path) async {
    final mount = mountOf(path);
    if (mount == null) return _local.exists(path);
    if (MountRegistry.innerPath(path) == '/') return true;
    try {
      final items = await list(path);
      return items.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    final mount = mountOf(path);
    if (mount == null) return _local.readBytes(path);

    final inner = MountRegistry.innerPath(path) ?? '/';
    if (mount.kind == MountKind.archive) {
      final archive = await _archiveOf(mount);
      final f = archive?.findFile(inner.substring(1));
      if (f == null) throw VfsException('压缩包内文件不存在', path);
      return Uint8List.fromList(f.content as List<int>);
    }
    // 远程：下载到临时文件再读
    throw VfsException('远程文件请先下载到本地再打开', path);
  }

  @override
  Future<Uint8List> readHead(String path, {int limit = 8192}) async {
    final mount = mountOf(path);
    if (mount == null) return _local.readHead(path, limit: limit);
    final bytes = await readBytes(path);
    return bytes.length <= limit ? bytes : bytes.sublist(0, limit);
  }

  @override
  Stream<List<int>> openRead(String path, {int? start, int? end}) async* {
    final mount = mountOf(path);
    if (mount == null) {
      yield* _local.openRead(path, start: start, end: end);
      return;
    }
    final bytes = await readBytes(path);
    final from = start ?? 0;
    final to = end ?? bytes.length;
    yield bytes.sublist(from, to.clamp(0, bytes.length));
  }

  @override
  Future<void> writeBytes(String path, List<int> data) async {
    final mount = mountOf(path);
    if (mount == null) return _local.writeBytes(path, data);

    if (mount.kind == MountKind.archive) {
      // 压缩包内允许编辑：改动先记在内存里，退出时询问是否保存。
      final inner = MountRegistry.innerPath(path) ?? '/';
      MountEditStore.instance
          .forRoot(mount)
          .recordWrite(inner, Uint8List.fromList(data));
      // 同步更新内存中的归档对象，让同一次会话里能读到新内容
      final archive = await _archiveOf(mount);
      final name = inner.startsWith('/') ? inner.substring(1) : inner;
      archive?.files.removeWhere((f) => f.name == name);
      archive?.add(ArchiveFile(name, data.length, data));
      return;
    }
    throw VfsException('远程位置不支持直接写入', path);
  }

  @override
  Future<void> mkdir(String path) async {
    final mount = mountOf(path);
    if (mount == null) return _local.mkdir(path);
    throw VfsException('该位置不支持创建目录', path);
  }

  @override
  Future<void> delete(String path, {bool recursive = true}) async {
    final mount = mountOf(path);
    if (mount == null) return _local.delete(path, recursive: recursive);

    if (mount.kind == MountKind.archive) {
      final inner = MountRegistry.innerPath(path) ?? '/';
      final name = inner.startsWith('/') ? inner.substring(1) : inner;

      // 目录要连子项一起删
      final archive = await _archiveOf(mount);
      final toRemove = <String>[];
      for (final f in archive?.files ?? const <ArchiveFile>[]) {
        if (f.name == name || f.name.startsWith('$name/')) toRemove.add(f.name);
      }
      for (final n in toRemove) {
        MountEditStore.instance
            .forRoot(mount)
            .recordDelete('/$n');
        archive?.files.removeWhere((f) => f.name == n);
      }
      return;
    }
    throw VfsException('远程位置不支持直接删除', path);
  }

  @override
  Future<void> rename(String path, String newPath) async {
    final mount = mountOf(path);
    if (mount == null) return _local.rename(path, newPath);
    throw VfsException('该位置不支持重命名', path);
  }

  @override
  Future<void> copy(String src, String dst) async {
    final srcMount = mountOf(src);
    final dstMount = mountOf(dst);

    // 本地 → 本地
    if (srcMount == null && dstMount == null) {
      return _local.copy(src, dst);
    }

    // 从挂载点（压缩包/远程）复制到本地
    if (srcMount != null && dstMount == null) {
      final bytes = await readBytes(src);
      return _local.writeBytes(dst, bytes);
    }

    throw VfsException('暂不支持写入该位置', dst);
  }

  @override
  Future<void> symlink(String target, String linkPath) async {
    final mount = mountOf(linkPath);
    if (mount == null) return _local.symlink(target, linkPath);
    throw VfsException('该位置不支持创建链接', linkPath);
  }

  @override
  Future<int> length(String path) async {
    final mount = mountOf(path);
    if (mount == null) return _local.length(path);
    final stat = await this.stat(path);
    return stat.size;
  }

  @override
  String parent(String path) {
    // 挂载根之上是本地（回到挂载来源所在目录）
    final mount = mountOf(path);
    if (mount != null) {
      if (path == mount.root) return _local.parent(mount.sourcePath);
    }
    if (!path.contains('/')) return path;
    var p = path;
    if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
    final i = p.lastIndexOf('/');
    if (i <= 0) return '/';
    return p.substring(0, i);
  }

  @override
  String basename(String path) => _local.basename(path);
}

/// 挂载远程时需要的展示信息
class RemoteLocationInfo {
  const RemoteLocationInfo({required this.label, required this.sourcePath});

  final String label;
  final String sourcePath;
}
