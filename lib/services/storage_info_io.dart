// 存储容量查询（Android / Linux 实现）
//
// 通过 toybox 的 `df -k <path>` 读取挂载点容量。
import 'dart:io';

/// 某个挂载点的容量信息
class StorageUsage {
  const StorageUsage({
    required this.path,
    required this.total,
    required this.free,
  });

  /// 查询的路径
  final String path;

  /// 总容量（字节）
  final int total;

  /// 可用容量（字节）
  final int free;

  int get used => total - free;

  /// 已用比例 0..1
  double get usedRatio => total <= 0 ? 0 : (used / total).clamp(0.0, 1.0);

  /// 百分比整数
  int get usedPercent => (usedRatio * 100).round();
}

/// 读取 [path] 所在挂载点的容量；失败返回 null。
Future<StorageUsage?> storageUsageOf(String path) async {
  try {
    final result = await Process.run('df', ['-k', path]);
    if (result.exitCode != 0) return null;
    final lines = '${result.stdout}'
        .trim()
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return null;

    // 末行形如：
    // /dev/block/dm-5  254772216 262144000 12345678  55% /storage/emulated
    final cols = lines.last.trim().split(RegExp(r'\s+'));
    if (cols.length < 5) return null;

    final n = cols.length;
    final totalK = int.tryParse(cols[n - 5]);
    final freeK = int.tryParse(cols[n - 3]);
    if (totalK == null || freeK == null || totalK <= 0) return null;

    return StorageUsage(
      path: path,
      total: totalK * 1024,
      free: freeK * 1024,
    );
  } catch (_) {
    return null;
  }
}
