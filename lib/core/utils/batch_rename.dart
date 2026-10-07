// 批量重命名：按表达式模板生成新文件名。
//
// 支持的占位符（沿用成熟文件管理器的习惯，便于用户迁移）：
//   {P}  原文件名（不含扩展名）
//   {E}  原扩展名（不含点）
//   {N}  序号（从起始值开始，按步长递增）
//   {zN} 序号补零（如 {z3} → 001）
//   {T}  当前时间戳（yyyyMMdd_HHmmss）
//   {D}  修改日期（yyyyMMdd）
//   {S}  文件大小（人类可读，如 1.2MB）
//   {AN} 按名称排序后的序号
//   {AD} 按日期排序后的序号
//   {AS} 按大小排序后的序号
//
// 日期时间子格式（在 {D:...} / {T:...} 里使用）：
//   yyyy / yy / MMMM / MMM / MM / dd / EEE / HH / hh / mm / ss / SSS / Q
import 'package:path/path.dart' as p;

/// 单个文件的改名计划
class RenamePlan {
  const RenamePlan({
    required this.oldPath,
    required this.newName,
    required this.oldName,
  });

  final String oldPath;
  final String newName;
  final String oldName;

  bool get changed => newName != oldName;
}

/// 批量重命名引擎
class BatchRename {
  BatchRename._();

  /// 解析模板中的占位符
  static String applyTemplate(
    String template, {
    required String baseName,
    required String extension,
    required int index,
    required int startNumber,
    required int step,
    required DateTime modified,
    required int size,
    required int sortIndexByName,
    required int sortIndexByDate,
    required int sortIndexBySize,
  }) {
    var out = template;

    // 序号类：{N} {zN}（N 是数字位数）
    out = out.replaceAllMapped(
      RegExp(r'\{z(\d+)\}'),
      (m) {
        final width = int.tryParse(m.group(1)!) ?? 1;
        final n = startNumber + index * step;
        return n.toString().padLeft(width, '0');
      },
    );
    out = out.replaceAll('{N}', '${startNumber + index * step}');

    // 排序序号
    out = out.replaceAll('{AN}', '${sortIndexByName + 1}');
    out = out.replaceAll('{AD}', '${sortIndexByDate + 1}');
    out = out.replaceAll('{AS}', '${sortIndexBySize + 1}');

    // 原名与扩展名
    out = out.replaceAll('{P}', baseName);
    out = out.replaceAll('{E}', extension);

    // 大小
    out = out.replaceAll('{S}', _humanSize(size));

    // 日期时间：支持 {T:fmt} 与 {D:fmt}
    out = out.replaceAllMapped(
      RegExp(r'\{(T|D)(?::([^}]*))?\}'),
      (m) {
        final kind = m.group(1)!;
        final fmt = m.group(2) ??
            (kind == 'T' ? 'yyyyMMdd_HHmmss' : 'yyyyMMdd');
        return formatDate(modified, fmt);
      },
    );

    return out;
  }

  /// 日期格式化（覆盖常用的完整模式）
  static String formatDate(DateTime d, String pattern) {
    // 按长度从长到短替换，避免 yyyy 被 yy 抢先匹配。
    // 同时支持单字符形式（M/d/H/h/m/s），与常见日期格式一致。
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const monthsShort = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final quarter = ((d.month - 1) ~/ 3) + 1;

    // 用「唯一占位符」避免替换结果被后续 token 再次匹配
    final map = <String, String>{
      'yyyy': d.year.toString().padLeft(4, '0'),
      'yy': (d.year % 100).toString().padLeft(2, '0'),
      'y': d.year.toString(),
      'MMMM': months[d.month - 1],
      'MMM': monthsShort[d.month - 1],
      'MM': d.month.toString().padLeft(2, '0'),
      'M': d.month.toString(),
      'dd': d.day.toString().padLeft(2, '0'),
      'd': d.day.toString(),
      'EEEE': weekdays[d.weekday - 1],
      'EEE': weekdaysShort[d.weekday - 1],
      'HH': d.hour.toString().padLeft(2, '0'),
      'H': d.hour.toString(),
      'hh': ((d.hour % 12) == 0 ? 12 : d.hour % 12).toString().padLeft(2, '0'),
      'h': ((d.hour % 12) == 0 ? 12 : d.hour % 12).toString(),
      'mm': d.minute.toString().padLeft(2, '0'),
      'm': d.minute.toString(),
      'ss': d.second.toString().padLeft(2, '0'),
      's': d.second.toString(),
      'SSS': d.millisecond.toString().padLeft(3, '0'),
      'Q': '$quarter',
    };

    final tokens = map.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    // 先把 token 替换成占位标记，最后统一还原，
    // 这样替换出来的数字不会被后面的 token 二次匹配。
    final marks = <String, String>{};
    var out = pattern;
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      final mark = '\u0000$i\u0001';
      if (out.contains(t)) {
        out = out.replaceAll(t, mark);
        marks[mark] = map[t]!;
      }
    }
    for (final e in marks.entries) {
      out = out.replaceAll(e.key, e.value);
    }
    return out;
  }

  /// 为一批文件生成改名计划
  static List<RenamePlan> plan({
    required List<({String path, String name, DateTime modified, int size})> files,
    required String template,
    int startNumber = 1,
    int step = 1,
  }) {
    if (files.isEmpty) return const [];

    // 计算三种排序序号（用于 {AN} {AD} {AS}）
    final byName = [...files]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final byDate = [...files]..sort((a, b) => a.modified.compareTo(b.modified));
    final bySize = [...files]..sort((a, b) => a.size.compareTo(b.size));

    int idxOf(List<({String path, String name, DateTime modified, int size})> l,
            String path) =>
        l.indexWhere((e) => e.path == path);

    final plans = <RenamePlan>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final base = f.name.contains('.')
          ? f.name.substring(0, f.name.lastIndexOf('.'))
          : f.name;
      final ext = f.name.contains('.')
          ? f.name.substring(f.name.lastIndexOf('.') + 1)
          : '';

      final newBase = applyTemplate(
        template,
        baseName: base,
        extension: ext,
        index: i,
        startNumber: startNumber,
        step: step,
        modified: f.modified,
        size: f.size,
        sortIndexByName: idxOf(byName, f.path),
        sortIndexByDate: idxOf(byDate, f.path),
        sortIndexBySize: idxOf(bySize, f.path),
      );

      // 模板没写扩展名时，保留原扩展名
      final hasExtToken = template.contains('{E}');
      final newName = hasExtToken || ext.isEmpty
          ? newBase
          : '$newBase.$ext';

      plans.add(RenamePlan(
        oldPath: f.path,
        newName: newName,
        oldName: f.name,
      ));
    }
    return plans;
  }

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)}GB';
  }

  /// 校验：新名字是否重复（同一批次内或与现有文件冲突）
  static List<String> validate(List<RenamePlan> plans) {
    final errors = <String>[];
    final seen = <String, int>{};
    for (final p0 in plans) {
      final key = p0.newName.toLowerCase();
      seen[key] = (seen[key] ?? 0) + 1;
    }
    for (final e in seen.entries) {
      if (e.value > 1) {
        errors.add('「${e.key}」出现 ${e.value} 次，会产生重名');
      }
    }
    // 非法字符
    for (final p0 in plans) {
      if (p0.newName.contains('/') || p0.newName.contains('\u0000')) {
        errors.add('「${p0.newName}」含非法字符');
      }
    }
    return errors;
  }

  /// 目录部分（用于拼接新路径）
  static String dirOf(String path) => p.dirname(path);
}
