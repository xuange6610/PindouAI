import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/bead_palettes.dart';
import '../l10n/app_strings.dart';
import '../models/processing_task.dart';
import '../services/app_notice_center.dart';
import '../services/processing_center.dart';
import '../services/project_repository.dart';
import '../theme/app_theme.dart';
import 'editor_screen.dart';

class ProcessingCenterScreen extends StatefulWidget {
  const ProcessingCenterScreen({super.key, required this.onOpenResult});

  final ValueChanged<String> onOpenResult;

  @override
  State<ProcessingCenterScreen> createState() => _ProcessingCenterScreenState();
}

class _ProcessingCenterScreenState extends State<ProcessingCenterScreen> {
  final _center = ProcessingCenter.instance;
  final _projects = ProjectRepository();

  @override
  void initState() {
    super.initState();
    unawaited(_center.initialize());
    unawaited(_center.refreshDeletedResults());
  }

  Future<void> _delete(ProcessingTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.ui(context, '删除处理任务？')),
        content: Text(AppStrings.ui(context, '任务记录和待处理图片将被删除；已经生成的作品不会受影响。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.ui(context, '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.ui(context, '确认删除')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _center.deleteTask(task.id);
  }

  Future<void> _regenerate(ProcessingTask task) async {
    final resultId = task.resultId;
    if (resultId == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final pattern = await _projects.load(resultId);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (pattern == null) {
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text(AppStrings.ui(context, '原作品已被删除，无法重新生成'))),
      );
      return;
    }
    final taskId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          imageBytes: pattern.sourceBytes,
          sourceName: task.sourceName,
          initialOptions: task.options,
          overwriteProjectId: resultId,
        ),
      ),
    );
    if (taskId != null && mounted) {
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text(AppStrings.ui(context, '已使用原图和新参数加入处理队列'))),
      );
    }
  }

  Future<void> _clearCompleted() async {
    final count = _center.tasks
        .where((task) => task.status == ProcessingTaskStatus.completed)
        .length;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cleaning_services_outlined),
        title: Text(AppStrings.ui(context, '清除已完成记录？')),
        content: Text(
          '$count ${AppStrings.ui(context, '将清除已完成的处理记录。已经生成并保存在“作品”中的图片不会被删除。')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.ui(context, '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.ui(context, '确认清除')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _center.clearCompleted();
  }

  Future<void> _restore(ProcessingTask task) async {
    final resultId = task.resultId;
    if (resultId == null) return;
    try {
      await _center.restoreResult(resultId);
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        const SnackBar(content: Text('作品已从回收站还原')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('还原失败：$error')),
      );
    }
  }

  Future<void> _rename(ProcessingTask task) async {
    final controller = TextEditingController(text: task.sourceName);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.ui(context, '重命名处理项目')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(
            labelText: AppStrings.ui(context, '显示名称'),
            prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.ui(context, '取消')),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: Text(AppStrings.ui(context, '保存名称')),
          ),
        ],
      ),
    );
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 350),
        controller.dispose,
      ),
    );
    if (value == null || value == task.sourceName) return;
    await _center.renameTask(task.id, value);
    if (task.resultId != null) {
      try {
        await _projects.rename(task.resultId!, value);
      } on Object {
        // A removed result does not prevent renaming its processing record.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.ui(context, '处理中心'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              AppStrings.ui(context, '任务按顺序处理，减少卡顿'),
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          AnimatedBuilder(
            animation: _center,
            builder: (context, _) {
              final hasCompleted = _center.tasks.any(
                (task) => task.status == ProcessingTaskStatus.completed,
              );
              if (!hasCompleted) return const SizedBox.shrink();
              return IconButton(
                onPressed: _clearCompleted,
                tooltip: AppStrings.ui(context, '清理已完成任务'),
                icon: const Icon(Icons.cleaning_services_outlined),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: AnimatedBuilder(
        animation: _center,
        builder: (context, _) {
          final tasks = _center.tasks;
          final summary = _QueueSummaryStats(
            active: _center.activeCount,
            pending: _center.pendingCount,
            completed: _center.completedCount,
            abnormal: _center.abnormalCount,
            deleted: _center.deletedResultCount,
          );
          if (tasks.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
              children: [
                summary,
                const SizedBox(height: 10),
                const _EmptyProcessingCenter(),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
            itemCount: tasks.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return summary;
              }
              final task = tasks[index - 1];
              return _TaskCard(
                task: task,
                resultDeleted: _center.resultDeleted(task.resultId),
                onPause: () => _center.pause(task.id),
                onResume: () => _center.resume(task.id),
                onDelete: () => _delete(task),
                onRename: () => _rename(task),
                onOpen:
                    task.resultId == null ||
                        _center.resultDeleted(task.resultId)
                    ? null
                    : () => widget.onOpenResult(task.resultId!),
                onRegenerate:
                    task.status == ProcessingTaskStatus.completed &&
                        task.resultId != null &&
                        !_center.resultDeleted(task.resultId)
                    ? () => _regenerate(task)
                    : null,
                onRestore: _center.resultRestorable(task.resultId)
                    ? () => _restore(task)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

class _QueueSummaryStats extends StatelessWidget {
  const _QueueSummaryStats({
    required this.active,
    required this.pending,
    required this.completed,
    required this.abnormal,
    required this.deleted,
  });

  final int active;
  final int pending;
  final int completed;
  final int abnormal;
  final int deleted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.teal, Color(0xFF48A798)],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.memory_rounded, color: Colors.white, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppStrings.ui(context, active > 0 ? '正在处理作品' : '处理队列已就绪'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ),
            Text(
              '$pending\n${AppStrings.ui(context, '待处理')}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _SummaryMetric(
              label: AppStrings.ui(context, '已处理'),
              value: completed,
            ),
            _SummaryMetric(
              label: AppStrings.ui(context, '待处理'),
              value: pending,
            ),
            _SummaryMetric(
              label: AppStrings.ui(context, '异常'),
              value: abnormal,
              danger: true,
            ),
            _SummaryMetric(
              label: AppStrings.ui(context, '作品已删除'),
              value: deleted,
              danger: true,
            ),
          ],
        ),
      ],
    ),
  );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final int value;
  final bool danger;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: danger ? const Color(0xFFFFD4D0) : Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 19,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: danger ? const Color(0xFFFFD4D0) : const Color(0xFFD9F4EF),
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.resultDeleted,
    required this.onPause,
    required this.onResume,
    required this.onDelete,
    required this.onRename,
    required this.onOpen,
    required this.onRegenerate,
    required this.onRestore,
  });

  final ProcessingTask task;
  final bool resultDeleted;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback? onOpen;
  final VoidCallback? onRegenerate;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final rawStatus = resultDeleted
        ? (
            label: AppStrings.ui(context, '作品已删除'),
            color: AppColors.coralDark,
            icon: Icons.delete_forever_outlined,
          )
        : _statusVisual(task.status);
    final ({String label, Color color, IconData icon}) status = (
      label: AppStrings.ui(context, rawStatus.label),
      color: rawStatus.color,
      icon: rawStatus.icon,
    );
    return Card(
      child: InkWell(
        onTap: onOpen,
        onLongPress: onRename,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child:
                          !resultDeleted &&
                              task.status == ProcessingTaskStatus.completed &&
                              task.resultThumbnailPath != null &&
                              File(task.resultThumbnailPath!).existsSync()
                          ? Image.file(
                              File(task.resultThumbnailPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _statusIcon(status),
                            )
                          : _statusIcon(status),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.sourceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          AppStrings.ui(context, '长按卡片可重命名'),
                          style: TextStyle(
                            color: AppColors.teal,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${task.options.width}×${task.options.outputHeight} · '
                          '${BeadPalettes.byId(task.options.paletteId).shortName} · '
                          '${AppStrings.ui(context, '最多')} ${task.options.maxColors} ${AppStrings.ui(context, '色')}'
                          '${task.options.removeBackground ? ' · ${AppStrings.ui(context, 'AI 抠图')}' : ''}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_formatDateTime(task.completedAt ?? task.createdAt)} · '
                          '${task.options.template.label} · '
                          '${AppStrings.ui(context, task.options.portraitMode ? '人像保护' : '标准颜色')} · '
                          '${AppStrings.ui(context, task.options.smoothing ? '轮廓优化' : '保留原像素')}'
                          '${task.options.variantSeed == 0 ? '' : ' · ${AppStrings.ui(context, '变化方案')}'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.label,
                      style: TextStyle(
                        color: status.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      resultDeleted
                          ? AppStrings.ui(context, '生成结果已被删除，无法查看作品')
                          : task.error ?? task.phase,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(task.progress * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 7,
                  color: status.color,
                  backgroundColor: AppColors.line,
                ),
              ),
              const SizedBox(height: 10),
              if (task.startedAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 15,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        task.completedAt == null
                            ? '${AppStrings.ui(context, '已用时')} ${_formatDuration(task.elapsed)}'
                            : '${AppStrings.ui(context, '生成用时')} ${_formatDuration(task.elapsed)} · ${AppStrings.ui(context, '应用画板')} ${task.options.width}×${task.options.outputHeight}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onRestore != null)
                    SizedBox(
                      width: 146,
                      height: 42,
                      child: FilledButton.tonalIcon(
                        onPressed: onRestore,
                        icon: const Icon(Icons.restore_from_trash_rounded),
                        label: const Text('还原作品'),
                      ),
                    ),
                  if (onOpen != null && !resultDeleted)
                    SizedBox(
                      width: 146,
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.visibility_outlined, size: 17),
                        label: Text(AppStrings.ui(context, '查看作品')),
                      ),
                    ),
                  if (onRegenerate != null)
                    SizedBox(
                      width: 146,
                      height: 42,
                      child: FilledButton.tonalIcon(
                        onPressed: onRegenerate,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: Text(AppStrings.ui(context, '重新设置参数')),
                      ),
                    ),
                  if (task.canPause)
                    OutlinedButton.icon(
                      onPressed: onPause,
                      icon: const Icon(Icons.pause_rounded, size: 18),
                      label: Text(AppStrings.ui(context, '暂停')),
                    ),
                  if (task.canResume)
                    FilledButton.tonalIcon(
                      onPressed: onResume,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(AppStrings.ui(context, '继续')),
                    ),
                  IconButton(
                    onPressed: onDelete,
                    tooltip: AppStrings.ui(context, '删除任务'),
                    color: AppColors.coralDark,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static ({String label, Color color, IconData icon}) _statusVisual(
    ProcessingTaskStatus status,
  ) => switch (status) {
    ProcessingTaskStatus.queued => (
      label: '排队中',
      color: const Color(0xFF8A6B22),
      icon: Icons.schedule_rounded,
    ),
    ProcessingTaskStatus.preparing || ProcessingTaskStatus.processing => (
      label: '处理中',
      color: AppColors.teal,
      icon: Icons.auto_awesome_rounded,
    ),
    ProcessingTaskStatus.paused => (
      label: '已暂停',
      color: const Color(0xFF7A5C9E),
      icon: Icons.pause_circle_outline,
    ),
    ProcessingTaskStatus.saving => (
      label: '保存中',
      color: AppColors.teal,
      icon: Icons.save_outlined,
    ),
    ProcessingTaskStatus.completed => (
      label: '已完成',
      color: const Color(0xFF287A43),
      icon: Icons.check_circle_outline,
    ),
    ProcessingTaskStatus.failed => (
      label: '失败',
      color: AppColors.coralDark,
      icon: Icons.error_outline,
    ),
  };

  static Widget _statusIcon(
    ({String label, Color color, IconData icon}) status,
  ) => ColoredBox(
    color: status.color.withValues(alpha: 0.13),
    child: Icon(status.icon, color: status.color),
  );

  static String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  static String _formatDuration(Duration duration) {
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}分${duration.inSeconds.remainder(60)}秒';
    }
    return '${math.max(1, duration.inSeconds)}秒';
  }
}

class _EmptyProcessingCenter extends StatelessWidget {
  const _EmptyProcessingCenter();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: const BoxDecoration(
              color: AppColors.mint,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.task_alt_rounded,
              color: AppColors.teal,
              size: 42,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            AppStrings.ui(context, '暂时没有处理任务'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 7),
          Text(
            AppStrings.ui(context, '新作品会进入这里排队，你可以随时暂停、继续或删除。'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}
