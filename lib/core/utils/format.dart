// 格式化工具：文件大小、时间、数字
import 'package:intl/intl.dart';

/// 格式化文件大小，自动选择单位（B / KB / MB / GB / TB）
String formatSize(int bytes, {int decimals = 2}) {
  if (bytes < 0) return '-';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  double size = bytes.toDouble();
  int unitIndex = -1;
  do {
    size /= 1024;
    unitIndex++;
  } while (size >= 1024 && unitIndex < units.length - 1);
  // 大于 100 时减少小数位，界面更整齐
  final d = size >= 100 ? 1 : decimals;
  return '${size.toStringAsFixed(d)} ${units[unitIndex]}';
}

/// 精确大小（带千分位字节数）
String formatSizeExact(int bytes) {
  final f = NumberFormat('#,###');
  return '${formatSize(bytes)} (${f.format(bytes)} 字节)';
}

/// 格式化时间：今天显示 HH:mm，今年显示 MM-dd HH:mm，其他显示 yyyy-MM-dd HH:mm
String formatTime(DateTime time, {bool withTime = true}) {
  final now = DateTime.now();
  final local = time.toLocal();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return withTime ? DateFormat('HH:mm').format(local) : '今天';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (local.year == yesterday.year &&
      local.month == yesterday.month &&
      local.day == yesterday.day) {
    return withTime ? '昨天 ${DateFormat('HH:mm').format(local)}' : '昨天';
  }
  if (local.year == now.year) {
    return withTime
        ? DateFormat('MM-dd HH:mm').format(local)
        : DateFormat('MM-dd').format(local);
  }
  return withTime
      ? DateFormat('yyyy-MM-dd HH:mm').format(local)
      : DateFormat('yyyy-MM-dd').format(local);
}

/// 完整时间格式（属性对话框用）
String formatTimeFull(DateTime time) {
  return DateFormat('yyyy-MM-dd HH:mm:ss').format(time.toLocal());
}

/// 相对时间描述
String formatRelativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30} 个月前';
  return '${diff.inDays ~/ 365} 年前';
}

/// 格式化数量（带单位）
String formatCount(int count) {
  if (count < 10000) return NumberFormat('#,###').format(count);
  if (count < 100000000) {
    return '${(count / 10000).toStringAsFixed(2)} 万';
  }
  return '${(count / 100000000).toStringAsFixed(2)} 亿';
}
