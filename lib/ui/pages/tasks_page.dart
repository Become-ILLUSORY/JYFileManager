// 任务队列：显示后台文件操作的进度。
//
// 数据来自 TaskQueue 单例（见 core/models/task_queue.dart），
// 复制/移动/删除/压缩等耗时操作都会登记进来，这里订阅显示。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/models/task_queue.dart';
import '../../core/utils/ui_icons.dart';

/// 打开任务队列
Future<void> showTasksPage(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const TasksPage(),
      fullscreenDialog: true,
    ),
  );
}

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  @override
  void initState() {
    super.initState();
    TaskQueue.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    TaskQueue.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final queue = TaskQueue.instance;
    final tasks = queue.tasks;

    return MiuixScaffold(
      containerColor: colors.background,
      topBar: _buildTopBar(colors, queue),
      content: (padding) => Padding(
        padding: EdgeInsets.only(top: padding.top),
        child: tasks.isEmpty
            ? _buildEmpty(colors)
            : ListView.builder(
                padding: const EdgeInsets.only(top: 6, bottom: 80),
                itemCount: tasks.length,
                itemBuilder: (ctx, i) => _taskTile(tasks[i], colors),
              ),
      ),
    );
  }

  Widget _buildTopBar(MiuixColors colors, TaskQueue queue) {
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: uiIcon(UiIcons.back, size: 22, color: colors.onSurface),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '任务队列',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    queue.hasRunning
                        ? '${queue.runningCount} 个进行中'
                        : '没有正在进行的任务',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
            if (queue.tasks.any((t) => t.status != TaskStatus.running &&
                t.status != TaskStatus.pending))
              TextButton(
                onPressed: queue.clearFinished,
                child: const Text('清除已完成'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(MiuixColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          uiIcon(
            UiIcons.tasks,
            size: 46,
            color: colors.onSurfaceVariantSummary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无任务',
            style: TextStyle(fontSize: 15, color: colors.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            '复制、移动、删除等操作会显示在这里',
            style: TextStyle(
              fontSize: 12.5,
              color: colors.onSurfaceVariantSummary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskTile(BackgroundTask t, MiuixColors colors) {
    final (icon, color) = switch (t.status) {
      TaskStatus.done => (UiIcons.checkCircle, colors.primary),
      TaskStatus.failed => (UiIcons.error, colors.error),
      TaskStatus.cancelled => (UiIcons.close, colors.onSurfaceVariantSummary),
      _ => (UiIcons.tasks, colors.primary),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                uiIcon(icon, size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                Text(
                  t.kind.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
            if (t.status == TaskStatus.running) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: t.total > 0 ? t.progress : null,
                  minHeight: 5,
                  backgroundColor: colors.onSurface.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(colors.primary),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  t.statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
                const Spacer(),
                if (t.error != null)
                  Flexible(
                    child: Text(
                      t.error!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: colors.error),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
