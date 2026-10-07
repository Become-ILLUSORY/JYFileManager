// 后台任务队列：文件复制/移动/删除/压缩等耗时操作的进度跟踪。
//
// 设计：一个全局单例维护任务列表，界面订阅它显示进度。
// 任务在 Dart 侧串行执行，避免同时大量 I/O 拖慢设备。
import 'package:flutter/foundation.dart';

import '../../services/fs/vfs.dart';

/// 任务类型
enum TaskKind { copy, move, delete, compress, extract, other }

extension TaskKindLabel on TaskKind {
  String get label => switch (this) {
        TaskKind.copy => '复制',
        TaskKind.move => '移动',
        TaskKind.delete => '删除',
        TaskKind.compress => '压缩',
        TaskKind.extract => '解压',
        TaskKind.other => '任务',
      };
}

/// 任务状态
enum TaskStatus { pending, running, done, failed, cancelled }

/// 一个后台任务
class BackgroundTask {
  BackgroundTask({
    required this.kind,
    required this.title,
    required this.total,
  });

  final String id = DateTime.now().microsecondsSinceEpoch.toString();
  final TaskKind kind;
  final String title;

  /// 总项数（文件/目录个数），未知为 0
  int total;

  /// 已完成项数
  int done = 0;

  TaskStatus status = TaskStatus.pending;
  String? error;
  final DateTime startedAt = DateTime.now();
  DateTime? finishedAt;

  double get progress => total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);

  String get statusLabel => switch (status) {
        TaskStatus.pending => '等待中',
        TaskStatus.running => total > 0 ? '$done / $total' : '进行中',
        TaskStatus.done => '已完成',
        TaskStatus.failed => '失败',
        TaskStatus.cancelled => '已取消',
      };
}

/// 全局任务队列
class TaskQueue extends ChangeNotifier {
  TaskQueue._();
  static final TaskQueue instance = TaskQueue._();

  final List<BackgroundTask> _tasks = [];
  List<BackgroundTask> get tasks => List.unmodifiable(_tasks);

  bool get hasRunning =>
      _tasks.any((t) => t.status == TaskStatus.running);

  int get runningCount =>
      _tasks.where((t) => t.status == TaskStatus.running).length;

  void add(BackgroundTask t) {
    _tasks.insert(0, t);
    notifyListeners();
  }

  /// 外部更新任务状态后调用，触发界面刷新
  void touch() => notifyListeners();

  void clearFinished() {
    _tasks.removeWhere((t) =>
        t.status == TaskStatus.done ||
        t.status == TaskStatus.failed ||
        t.status == TaskStatus.cancelled);
    notifyListeners();
  }

  void remove(String id) {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  /// 统计一个目录下的文件/目录总数（用于进度条）
  static Future<int> countEntries(Vfs fs, String path) async {
    var n = 0;
    try {
      final items = await fs.list(path);
      n += items.length;
      for (final it in items) {
        if (it.isDirectory) n += await countEntries(fs, it.path);
      }
    } catch (_) {}
    return n;
  }

  /// 复制目录树（带进度回调）
  static Future<void> copyTree(
    Vfs fs,
    String src,
    String dst, {
    void Function(int delta)? onProgress,
  }) async {
    await fs.mkdir(dst);
    final children = await fs.list(src);
    for (final child in children) {
      final target = '$dst/${child.name}';
      if (child.isDirectory) {
        await copyTree(fs, child.path, target, onProgress: onProgress);
      } else {
        await fs.copy(child.path, target);
        onProgress?.call(1);
      }
    }
  }

  /// 删除目录树（带进度回调）
  static Future<void> deleteTree(
    Vfs fs,
    String path, {
    void Function(int delta)? onProgress,
  }) async {
    final items = await fs.list(path);
    for (final it in items) {
      if (it.isDirectory) {
        await deleteTree(fs, it.path, onProgress: onProgress);
      } else {
        await fs.delete(it.path, recursive: false);
        onProgress?.call(1);
      }
    }
    await fs.delete(path, recursive: true);
    onProgress?.call(1);
  }
}

/// 执行一个后台任务（自动登记到队列并更新进度）
Future<BackgroundTask> runTask({
  required TaskKind kind,
  required String title,
  required Future<void> Function(BackgroundTask task) body,
  int total = 0,
}) async {
  final task = BackgroundTask(kind: kind, title: title, total: total);
  final queue = TaskQueue.instance;
  queue.add(task);

  task.status = TaskStatus.running;
  queue.touch();

  try {
    await body(task);
    task.status = TaskStatus.done;
  } catch (e) {
    task.status = TaskStatus.failed;
    task.error = '$e';
  } finally {
    task.finishedAt = DateTime.now();
    queue.touch();
  }
  return task;
}
