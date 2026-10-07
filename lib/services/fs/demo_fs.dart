// 内存演示文件系统 —— 用于 Web 预览与界面迭代
//
// 只在 Web 构建中启用（见 fs_provider.dart 的条件导出），
// 提供一套贴近 Android 存储结构的假数据，方便在浏览器里检查界面。
import 'dart:async';
import 'dart:typed_data';

import '../../core/models/file_item.dart';
import 'vfs.dart';

class _Node {
  _Node({
    required this.path,
    required this.isDirectory,
    this.size = 0,
    required this.modified,
    this.linkTarget,
    this.mode = 0x1A4,
  });

  final String path;
  bool isDirectory;
  int size;
  DateTime modified;
  String? linkTarget;
  int mode;
}

class DemoFs extends Vfs {
  DemoFs._();
  static final DemoFs instance = DemoFs._();

  final Map<String, _Node> _nodes = {};
  bool _seeded = false;

  @override
  String get schemeName => '演示';

  @override
  String get rootPath => '/';

  // ============ 初始化假数据 ============

  void _seed() {
    if (_seeded) return;
    _seeded = true;
    final now = DateTime.now();

    void dir(String path, {int daysAgo = 0}) {
      _nodes[path] = _Node(
        path: path,
        isDirectory: true,
        modified: now.subtract(Duration(days: daysAgo, hours: 3)),
        mode: 0x1ED,
      );
    }

    void file(String path, int size, {int daysAgo = 0, int hoursAgo = 0}) {
      _nodes[path] = _Node(
        path: path,
        isDirectory: false,
        size: size,
        modified: now.subtract(Duration(days: daysAgo, hours: hoursAgo)),
      );
    }

    // 根与存储
    dir('/');
    dir('/storage');
    dir('/storage/emulated');
    dir('/storage/emulated/0');
    dir('/storage/emulated/0/DCIM');
    dir('/storage/emulated/0/DCIM/Camera');
    dir('/storage/emulated/0/Download');
    dir('/storage/emulated/0/Documents');
    dir('/storage/emulated/0/Pictures');
    dir('/storage/emulated/0/Pictures/Screenshots');
    dir('/storage/emulated/0/Music');
    dir('/storage/emulated/0/Movies');
    dir('/storage/emulated/0/空文件夹');
    dir('/storage/emulated/0/Android');
    dir('/storage/emulated/0/Android/data');
    dir('/storage/emulated/0/Android/obb');
    dir('/storage/emulated/0/JYBackup');

    file('/storage/emulated/0/DCIM/Camera/IMG_20261005_183012.jpg', 4194304,
        hoursAgo: 6);
    file('/storage/emulated/0/DCIM/Camera/IMG_20261004_142233.jpg', 3670016,
        daysAgo: 1);
    file('/storage/emulated/0/DCIM/Camera/VID_20261003_201155.mp4', 134217728,
        daysAgo: 2);
    file('/storage/emulated/0/Pictures/Screenshots/Screenshot_2026-10-06-12-27-22.png',
        1258291, hoursAgo: 2);
    file('/storage/emulated/0/Pictures/Screenshots/Screenshot_2026-10-06-10-42-09.png',
        1108390, hoursAgo: 5);

    file('/storage/emulated/0/Download/JYFileManager-v1.0.0.apk', 51275366,
        hoursAgo: 1);
    file('/storage/emulated/0/Download/报告-2026年度.pdf', 2411724, daysAgo: 3);
    file('/storage/emulated/0/Download/data-export.zip', 18874368, daysAgo: 4);
    file('/storage/emulated/0/Download/notes.txt', 4096, daysAgo: 1);

    file('/storage/emulated/0/Documents/会议纪要.md', 8192, hoursAgo: 4);
    file('/storage/emulated/0/Documents/预算表.xlsx', 24576, daysAgo: 5);
    file('/storage/emulated/0/Documents/合同扫描件.pdf', 1572864, daysAgo: 7);

    file('/storage/emulated/0/Music/夜曲.mp3', 9437184, daysAgo: 12);
    file('/storage/emulated/0/Music/钢琴协奏曲.flac', 41943040, daysAgo: 20);

    file('/storage/emulated/0/Movies/纪录片-深海.mp4', 2147483648, daysAgo: 30);

    file('/storage/emulated/0/JYBackup/backup-2026-10-01.tar.gz', 104857600,
        daysAgo: 5);
    file('/storage/emulated/0/JYBackup/contacts.vcf', 65536, daysAgo: 5);

    file('/storage/emulated/0/.nomedia', 0, daysAgo: 60);
    file('/storage/emulated/0/.config_backup', 1024, daysAgo: 45);
    file('/storage/emulated/0/README.txt', 2048, daysAgo: 10);
  }

  _Node? _node(String path) {
    _seed();
    return _nodes[normalize(path)];
  }

  // ============ Vfs 实现 ============

  @override
  Future<List<FileItem>> list(String path, {bool showHidden = true}) async {
    final p = normalize(path);
    final node = _node(p);
    if (node == null) throw VfsException('目录不存在', path);
    if (!node.isDirectory) throw VfsException('不是目录', path);

    final prefix = p == '/' ? '/' : '$p/';
    final result = <FileItem>[];
    for (final n in _nodes.values) {
      if (n.path == p) continue;
      if (!n.path.startsWith(prefix)) continue;
      final rest = n.path.substring(prefix.length);
      if (rest.isEmpty || rest.contains('/')) continue;
      if (!showHidden && FileItem.basenameOf(n.path).startsWith('.')) continue;
      result.add(FileItem(
        name: FileItem.basenameOf(n.path),
        path: n.path,
        isDirectory: n.isDirectory,
        isLink: n.linkTarget != null,
        linkTarget: n.linkTarget,
        size: n.size,
        modified: n.modified,
        accessed: n.modified,
        mode: n.mode,
      ));
    }
    return result;
  }

  @override
  Future<VfsStat> stat(String path) async {
    final n = _node(path);
    if (n == null) return const VfsStat.notFound();
    return VfsStat(
      exists: true,
      isDirectory: n.isDirectory,
      isLink: n.linkTarget != null,
      linkTarget: n.linkTarget,
      size: n.size,
      modified: n.modified,
      mode: n.mode,
    );
  }

  @override
  Future<bool> exists(String path) async => _node(path) != null;

  @override
  Future<Uint8List> readBytes(String path) async {
    final n = _node(path);
    if (n == null) throw VfsException('文件不存在', path);
    return Uint8List(n.size);
  }

  @override
  Future<Uint8List> readHead(String path, {int limit = 8192}) async {
    final n = _node(path);
    if (n == null) throw VfsException('文件不存在', path);
    return Uint8List(n.size < limit ? n.size : limit);
  }

  @override
  Stream<List<int>> openRead(String path, {int? start, int? end}) {
    return Stream.value(<int>[]);
  }

  @override
  Future<void> writeBytes(String path, List<int> data) async {
    _seed();
    final p = normalize(path);
    _nodes[p] = _Node(
      path: p,
      isDirectory: false,
      size: data.length,
      modified: DateTime.now(),
    );
  }

  @override
  Future<void> mkdir(String path) async {
    _seed();
    final p = normalize(path);
    _nodes[p] = _Node(
      path: p,
      isDirectory: true,
      modified: DateTime.now(),
      mode: 0x1ED,
    );
  }

  @override
  Future<void> delete(String path, {bool recursive = true}) async {
    _seed();
    final p = normalize(path);
    final prefix = '$p/';
    _nodes.removeWhere((k, _) => k == p || (recursive && k.startsWith(prefix)));
  }

  @override
  Future<void> rename(String path, String newPath) async {
    _seed();
    final from = normalize(path);
    final to = normalize(newPath);
    final node = _nodes.remove(from);
    if (node == null) throw VfsException('源不存在', path);
    _nodes[to] = node;
    // 目录内容一并搬移
    final prefix = '$from/';
    final moved = <String, _Node>{};
    _nodes.removeWhere((k, v) {
      if (k.startsWith(prefix)) {
        moved[k.replaceFirst(from, to)] = v;
        return true;
      }
      return false;
    });
    _nodes.addAll(moved);
  }

  @override
  Future<void> copy(String src, String dst) async {
    _seed();
    final node = _node(src);
    if (node == null) throw VfsException('源不存在', src);
    _nodes[normalize(dst)] = _Node(
      path: normalize(dst),
      isDirectory: node.isDirectory,
      size: node.size,
      modified: DateTime.now(),
      linkTarget: node.linkTarget,
      mode: node.mode,
    );
  }

  @override
  Future<int> length(String path) async => _node(path)?.size ?? 0;

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
}
