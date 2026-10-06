// 存储容量查询（Web 桩实现：浏览器无法读取宿主磁盘）

/// 某个挂载点的容量信息
class StorageUsage {
  const StorageUsage({
    required this.path,
    required this.total,
    required this.free,
  });

  final String path;
  final int total;
  final int free;

  int get used => total - free;
  double get usedRatio => total <= 0 ? 0 : (used / total).clamp(0.0, 1.0);
  int get usedPercent => (usedRatio * 100).round();
}

/// Web 上无磁盘容量概念，恒返回 null。
Future<StorageUsage?> storageUsageOf(String path) async => null;
