// 特权文件系统：通过 Root 或 Shizuku 执行 shell 命令实现特权文件操作
import 'dart:async';
import 'dart:convert';

import 'dart:typed_data';

import '../../core/models/file_item.dart';
import '../privilege.dart';
import 'vfs.dart';

/// 通过提权通道（Root 或 Shizuku）实现的文件系统。
///
/// 用于访问 /data、/system 等特权目录。所有操作都经由 [PrivilegeManager]
/// 执行 shell 命令完成，因此 Root 与 Shizuku 两种方式共用同一套实现；
/// 文件内容通过 base64 管道传输避免转义问题。
class RootFs extends Vfs {
  RootFs._();
  static final RootFs instance = RootFs._();

  @override
  String get schemeName => 'Root';

  @override
  String get rootPath => '/';

  /// 当前是否具备特权（Root 或 Shizuku 任一可用）
  Future<bool> hasRoot() => PrivilegeManager.instance.refresh().then(
        (s) => s.active,
      );

  /// 执行并返回结果
  Future<ExecResult> _exec(String command) =>
      PrivilegeManager.instance.exec(command);

  /// 执行并返回 stdout 文本
  Future<String> _suOut(String command) async {
    final r = await _exec(command);
    return r.stdout;
  }

  /// shell 单引号转义
  String _q(String s) => "'${s.replaceAll("'", "'\\''")}'";

  @override
  Future<List<FileItem>> list(String path, {bool showHidden = true}) async {
    // 用 ls -la 输出解析；分隔符用 \x1f 避免文件名含空格问题
    // busybox/toybox ls 支持 -e 或 --full-time，这里用 stat 批量更稳妥
    final cmd = 'ls -la ${_q(path)} 2>/dev/null';
    final out = await _suOut(cmd);
    if (out.trim().isEmpty) {
      // 检查目录是否存在
      final exists = await this.exists(path);
      if (!exists) throw VfsException('目录不存在或无法访问', path);
      return [];
    }

    final items = <FileItem>[];
    final lines = out.split('\n');
    for (final line in lines) {
      if (line.isEmpty || line.startsWith('total ')) continue;
      final item = _parseLsLine(line, path);
      if (item != null) {
        if (!showHidden && item.isHidden) continue;
        items.add(item);
      }
    }

    // ls -la 不含年份的日期（6个月内）与含年份的日期（更早）格式不同，
    // 为了拿到精确 mtime，用 stat 批量补充（部分设备支持 stat -c）
    await _enrichWithStat(items);
    return items;
  }

  /// 解析 `ls -la` 一行
  /// 格式: -rw-r--r-- 1 root root 12345 2024-01-01 12:00 filename
  /// 或:   lrwxrwxrwx 1 root root    10 2024-01-01 12:00 link -> target
  FileItem? _parseLsLine(String line, String dirPath) {
    try {
      if (line.length < 10) return null;
      final typeChar = line[0];
      final perms = line.substring(1, 10);
      final rest = line.substring(10).trim();
      final parts = rest.split(RegExp(r'\s+'));
      if (parts.length < 6) return null;

      // parts: [links, owner, group, size, date, time/year, name...]
      final size = int.tryParse(parts[3]) ?? 0;
      final dateStr = parts[4];
      final timeOrYear = parts[5];

      // 文件名可能含空格，取剩余部分
      var nameStart = line.indexOf(timeOrYear, line.indexOf(dateStr)) +
          timeOrYear.length;
      var name = line.substring(nameStart).trim();
      if (name.isEmpty) return null;

      String? linkTarget;
      final arrowIdx = name.indexOf(' -> ');
      if (arrowIdx >= 0) {
        linkTarget = name.substring(arrowIdx + 4);
        name = name.substring(0, arrowIdx);
      }

      // 解析日期
      DateTime modified;
      try {
        final now = DateTime.now();
        if (timeOrYear.contains(':')) {
          // 当年: 2024-01-01 12:00
          final dt = DateTime.parse('$dateStr $timeOrYear:00');
          modified = dt;
        } else {
          modified = DateTime.parse(dateStr);
        }
        // 未来时间修正（时钟问题）
        if (modified.isAfter(now.add(const Duration(days: 1)))) {
          modified = modified.subtract(const Duration(days: 365));
        }
      } catch (_) {
        modified = DateTime.fromMillisecondsSinceEpoch(0);
      }

      final isLink = typeChar == 'l';
      // 符号链接解析后可能是目录；ls -la 输出中链接带 @ 或 -> 标记
      // 用 -F 标志判断，这里保守处理：链接先按文件处理，stat 时修正
      final isDir = typeChar == 'd';

      return FileItem(
        name: name,
        path: dirPath.endsWith('/') ? '$dirPath$name' : '$dirPath/$name',
        isDirectory: isDir,
        isLink: isLink,
        linkTarget: linkTarget,
        size: size,
        modified: modified,
        mode: _parsePerms(typeChar, perms),
      );
    } catch (_) {
      return null;
    }
  }

  int _parsePerms(String typeChar, String perms) {
    var mode = 0;
    if (typeChar == 'd') {
      mode |= 0x4000;
    } else if (typeChar == 'l') {
      mode |= 0xA000;
    } else {
      mode |= 0x8000;
    }
    const bits = [0x100, 0x80, 0x40, 0x20, 0x10, 0x8, 0x4, 0x2, 0x1];
    for (var i = 0; i < 9 && i < perms.length; i++) {
      if (perms[i] != '-') mode |= bits[i];
    }
    return mode;
  }

  /// 用 stat 补充精确信息（大小写兼容 GNU/BusyBox）
  Future<void> _enrichWithStat(List<FileItem> items) async {
    if (items.isEmpty) return;
    // 批量 stat：每条路径单独查询太慢，这里跳过；改用已有 ls 信息
    // 对目录修正链接判断：检查是否为指向目录的链接
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.isLink) {
        // 用 test -d 判断链接目标
        final target = await _suOut(
            'test -d ${_q(item.path)} && echo yes || echo no');
        if (target.trim() == 'yes') {
          items[i] = item.copyWith(isDirectory: true);
        }
      }
    }
  }

  @override
  Future<VfsStat> stat(String path) async {
    final out = await _suOut(
        'stat -c "%F|%s|%Y|%a" ${_q(path)} 2>/dev/null || echo NOTFOUND');
    final text = out.trim();
    if (text == 'NOTFOUND' || text.isEmpty) {
      return const VfsStat.notFound();
    }
    final parts = text.split('|');
    if (parts.length < 4) return const VfsStat.notFound();
    final typeStr = parts[0];
    final size = int.tryParse(parts[1]) ?? 0;
    final mtime = int.tryParse(parts[2]) ?? 0;
    final mode = int.tryParse(parts[3], radix: 8) ?? 0;
    final isLink = typeStr.contains('symbolic link');
    final isDir = typeStr.contains('directory');

    String? linkTarget;
    if (isLink) {
      linkTarget = (await _suOut('readlink ${_q(path)}')).trim();
    }

    return VfsStat(
      exists: true,
      isDirectory: isDir,
      isLink: isLink,
      linkTarget: linkTarget,
      size: size,
      modified: DateTime.fromMillisecondsSinceEpoch(mtime * 1000),
      mode: mode | (isDir ? 0x4000 : (isLink ? 0xA000 : 0x8000)),
    );
  }

  @override
  Future<bool> exists(String path) async {
    final out = await _suOut('test -e ${_q(path)} && echo yes || echo no');
    return out.trim() == 'yes';
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    // base64 传输，避免二进制损坏
    final result = await _exec('base64 ${_q(path)} 2>/dev/null');
    if (!result.ok) {
      throw VfsException('读取失败（需要 root）', path);
    }
    final b64 = result.stdout.replaceAll(RegExp(r'\s'), '');
    return base64Decode(b64);
  }

  @override
  Stream<List<int>> openRead(String path, {int? start, int? end}) async* {
    // Root 文件用 dd 分块读取
    final size = await length(path);
    final from = start ?? 0;
    final to = end ?? size;
    const chunkSize = 1024 * 256;
    var pos = from;
    while (pos < to) {
      final len = (to - pos).clamp(0, chunkSize);
      final cmd =
          'dd if=${_q(path)} bs=1 skip=$pos count=$len 2>/dev/null | base64';
      final result = await _exec(cmd);
      if (!result.ok) break;
      final b64 = result.stdout.replaceAll(RegExp(r'\s'), '');
      if (b64.isEmpty) break;
      yield base64Decode(b64);
      pos += len;
    }
  }

  @override
  Future<void> writeBytes(String path, List<int> data) async {
    final b64 = base64Encode(data);
    // 分块传输避免命令行过长
    const chunkSize = 65536;
    if (b64.length <= chunkSize) {
      final result = await _exec(
          'echo ${_q(b64)} | base64 -d > ${_q(path)}');
      if (!result.ok) throw VfsException('写入失败', path);
    } else {
      // 先清空文件
      await _exec('> ${_q(path)}');
      for (var i = 0; i < b64.length; i += chunkSize) {
        final chunk =
            b64.substring(i, (i + chunkSize).clamp(0, b64.length));
        final result = await _exec(
            'echo ${_q(chunk)} | base64 -d >> ${_q(path)}');
        if (!result.ok) throw VfsException('写入失败', path);
      }
    }
  }

  @override
  Future<void> mkdir(String path) async {
    final result = await _exec('mkdir -p ${_q(path)}');
    if (!result.ok) throw VfsException('创建目录失败', path);
  }

  @override
  Future<void> delete(String path, {bool recursive = true}) async {
    final cmd = recursive ? 'rm -rf ${_q(path)}' : 'rm ${_q(path)}';
    final result = await _exec(cmd);
    if (!result.ok) throw VfsException('删除失败', path);
  }

  @override
  Future<void> rename(String path, String newPath) async {
    final result = await _exec('mv ${_q(path)} ${_q(newPath)}');
    if (!result.ok) throw VfsException('重命名失败', path);
  }

  @override
  Future<void> copy(String src, String dst) async {
    final result = await _exec('cp -f ${_q(src)} ${_q(dst)}');
    if (!result.ok) throw VfsException('复制失败', src);
  }

  @override
  Future<int> length(String path) async {
    final out = await _suOut('stat -c "%s" ${_q(path)} 2>/dev/null || echo 0');
    return int.tryParse(out.trim()) ?? 0;
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

  /// 挂载为可读写（重挂载功能）
  Future<bool> remountRw(String mountPoint) async {
    final result =
        await _exec('mount -o remount,rw ${_q(mountPoint)} 2>&1');
    return result.ok;
  }
}
