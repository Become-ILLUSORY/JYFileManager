// 文件对比引擎：文本逐行对比 + 目录结构对比。
//
// 文本对比用经典的 LCS（最长公共子序列）动态规划 —— 对常见规模
// （几千行）足够快；超过阈值时退化为「按行哈希的快速对比」，
// 避免 O(n²) 内存爆掉。
import 'dart:convert';

/// 一行在对比结果里的角色
enum DiffKind {
  /// 两边都有且相同
  same,

  /// 仅左侧有（删除）
  removed,

  /// 仅右侧有（新增）
  added,

  /// 两边都有但内容不同（修改）
  changed,
}

/// 一行对比结果
class DiffLine {
  const DiffLine({
    required this.kind,
    this.left,
    this.right,
    this.leftNo,
    this.rightNo,
  });

  final DiffKind kind;
  final String? left;
  final String? right;
  final int? leftNo;
  final int? rightNo;
}

/// 对比统计
class DiffStats {
  const DiffStats({
    required this.same,
    required this.added,
    required this.removed,
    required this.changed,
  });

  final int same;
  final int added;
  final int removed;
  final int changed;

  int get total => same + added + removed + changed;
  bool get identical => added == 0 && removed == 0 && changed == 0;
}

/// 文本对比结果
class TextDiffResult {
  const TextDiffResult({required this.lines, required this.stats});

  final List<DiffLine> lines;
  final DiffStats stats;
}

/// 目录对比里一个条目的状态
enum DirEntryState { onlyLeft, onlyRight, both, different }

/// 目录对比结果的一行
class DirDiffEntry {
  const DirDiffEntry({
    required this.name,
    required this.state,
    this.leftSize,
    this.rightSize,
    this.isDirectory = false,
  });

  final String name;
  final DirEntryState state;
  final int? leftSize;
  final int? rightSize;
  final bool isDirectory;
}

/// 对比引擎
class DiffEngine {
  DiffEngine._();

  /// 超过这个行数就不做 O(n²) 的 LCS，退化为快速对比
  static const int lcsLineLimit = 3000;

  /// 文本对比
  static TextDiffResult compareText(String left, String right) {
    final a = const LineSplitter().convert(left);
    final b = const LineSplitter().convert(right);

    // 大文件走快速路径，避免内存爆掉
    if (a.length > lcsLineLimit || b.length > lcsLineLimit) {
      return _fastDiff(a, b);
    }
    return _lcsDiff(a, b);
  }

  /// 基于 LCS 的精确对比
  static TextDiffResult _lcsDiff(List<String> a, List<String> b) {
    final n = a.length, m = b.length;
    // dp[i][j] = a[i..] 与 b[j..] 的 LCS 长度
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        dp[i][j] = a[i] == b[j]
            ? dp[i + 1][j + 1] + 1
            : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
      }
    }

    final lines = <DiffLine>[];
    var i = 0, j = 0;
    var same = 0, added = 0, removed = 0, changed = 0;

    while (i < n && j < m) {
      if (a[i] == b[j]) {
        lines.add(DiffLine(
          kind: DiffKind.same,
          left: a[i],
          right: b[j],
          leftNo: i + 1,
          rightNo: j + 1,
        ));
        same++;
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        lines.add(DiffLine(kind: DiffKind.removed, left: a[i], leftNo: i + 1));
        removed++;
        i++;
      } else {
        lines.add(DiffLine(kind: DiffKind.added, right: b[j], rightNo: j + 1));
        added++;
        j++;
      }
    }
    while (i < n) {
      lines.add(DiffLine(kind: DiffKind.removed, left: a[i], leftNo: i + 1));
      removed++;
      i++;
    }
    while (j < m) {
      lines.add(DiffLine(kind: DiffKind.added, right: b[j], rightNo: j + 1));
      added++;
      j++;
    }

    return TextDiffResult(
      lines: lines,
      stats: DiffStats(
        same: same,
        added: added,
        removed: removed,
        changed: changed,
      ),
    );
  }

  /// 大文件的快速对比：按行做集合差异，不保证最小编辑距离，但结果直观
  static TextDiffResult _fastDiff(List<String> a, List<String> b) {
    final lines = <DiffLine>[];
    var same = 0, added = 0, removed = 0;
    final maxLen = a.length > b.length ? a.length : b.length;

    for (var i = 0; i < maxLen; i++) {
      final la = i < a.length ? a[i] : null;
      final lb = i < b.length ? b[i] : null;
      if (la == lb) {
        lines.add(DiffLine(
          kind: DiffKind.same,
          left: la,
          right: lb,
          leftNo: i + 1,
          rightNo: i + 1,
        ));
        same++;
      } else {
        if (la != null) {
          lines.add(DiffLine(kind: DiffKind.removed, left: la, leftNo: i + 1));
          removed++;
        }
        if (lb != null) {
          lines.add(DiffLine(kind: DiffKind.added, right: lb, rightNo: i + 1));
          added++;
        }
      }
    }

    return TextDiffResult(
      lines: lines,
      stats: DiffStats(
        same: same,
        added: added,
        removed: removed,
        changed: 0,
      ),
    );
  }

  /// 目录对比：按文件名匹配，比较大小与存在性
  static List<DirDiffEntry> compareDirs({
    required Map<String, ({int size, bool isDir})> left,
    required Map<String, ({int size, bool isDir})> right,
  }) {
    final names = <String>{...left.keys, ...right.keys}.toList()..sort();

    final out = <DirDiffEntry>[];
    for (final name in names) {
      final l = left[name];
      final r = right[name];
      if (l != null && r == null) {
        out.add(DirDiffEntry(
          name: name,
          state: DirEntryState.onlyLeft,
          leftSize: l.size,
          isDirectory: l.isDir,
        ));
      } else if (l == null && r != null) {
        out.add(DirDiffEntry(
          name: name,
          state: DirEntryState.onlyRight,
          rightSize: r.size,
          isDirectory: r.isDir,
        ));
      } else if (l != null && r != null) {
        // 目录不比大小；文件大小不同视为「有差异」
        final differ = !l.isDir && !r.isDir && l.size != r.size;
        out.add(DirDiffEntry(
          name: name,
          state: differ ? DirEntryState.different : DirEntryState.both,
          leftSize: l.size,
          rightSize: r.size,
          isDirectory: l.isDir,
        ));
      }
    }
    return out;
  }
}
