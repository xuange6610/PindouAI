import 'dart:io';

import 'package:flutter/material.dart';

import '../services/ai_design_task_center.dart';
import '../services/app_notice_center.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';

class AiDesignTaskCenterScreen extends StatefulWidget {
  const AiDesignTaskCenterScreen({
    super.key,
    this.center,
    this.scope = AiDesignTaskScope.design,
  });

  final AiDesignTaskCenter? center;
  final AiDesignTaskScope scope;

  @override
  State<AiDesignTaskCenterScreen> createState() =>
      _AiDesignTaskCenterScreenState();
}

class _AiDesignTaskCenterScreenState extends State<AiDesignTaskCenterScreen> {
  late final AiDesignTaskCenter _center;

  @override
  void initState() {
    super.initState();
    _center = widget.center ?? AiDesignTaskCenter.instance;
    _center.addListener(_changed);
  }

  @override
  void dispose() {
    _center.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _open(AiDesignTask task) async {
    final entry = task.historyEntry;
    final path = entry?.imagePath;
    if (task.status != AiDesignTaskStatus.succeeded || path == null) return;
    final file = File(path);
    if (!await file.exists() || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text('${task.styleTitle} · 任务结果'),
            actions: [
              IconButton(
                onPressed: () async {
                  final path = await ExportService().saveImageBytes(
                    await file.readAsBytes(),
                    '${widget.scope == AiDesignTaskScope.colorRecognition ? 'AI色号识别' : 'AI拼豆图'}_${task.id}.png',
                  );
                  if (!mounted) return;
                  AppNoticeCenter.instance.showSnackBar(
                    SnackBar(content: Text('已保存：$path')),
                  );
                },
                tooltip: '保存图片',
                icon: const Icon(Icons.download_rounded),
              ),
            ],
          ),
          body: InteractiveViewer(
            minScale: 0.2,
            maxScale: 12,
            child: Center(child: Image.file(file, fit: BoxFit.contain)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _center.visibleTasksFor(widget.scope);
    final recognition = widget.scope == AiDesignTaskScope.colorRecognition;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          recognition ? '图片色号识别任务中心' : 'AI 拼豆图纸任务中心',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: tasks.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.task_alt_rounded,
                      size: 56,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: 12),
                    Text(recognition ? '还没有后台色号识别任务' : '还没有后台拼豆图纸任务'),
                    const SizedBox(height: 5),
                    Text(
                      recognition
                          ? '这里只显示图片色号识别任务，不会再与 AI 拼豆图纸重叠。'
                          : '这里只显示 AI 拼豆图纸任务；生成时可选择放到任务中心。',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final task = tasks[index];
                final status = _status(task);
                final canOpen = task.status == AiDesignTaskStatus.succeeded;
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: canOpen ? () => _open(task) : null,
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _TaskStatusIcon(task: task),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.styleTitle,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      status,
                                      style: TextStyle(
                                        color:
                                            task.status ==
                                                AiDesignTaskStatus.failed
                                            ? Colors.red
                                            : AppColors.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!task.isActive)
                                IconButton(
                                  onPressed: () => _center.remove(task.id),
                                  tooltip: '从任务中心移除',
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            task.displayPrompt,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 9),
                          LinearProgressIndicator(
                            value: task.status == AiDesignTaskStatus.succeeded
                                ? 1
                                : task.isActive
                                ? task.progress > 0
                                      ? task.progress
                                      : null
                                : task.progress,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${(task.progress * 100).round()}% · ${task.phase}',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (task.error != null) ...[
                            const SizedBox(height: 7),
                            Text(
                              task.error!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(bottom: 8),
                            dense: true,
                            leading: const Icon(Icons.tune_rounded, size: 20),
                            title: const Text(
                              '详细进度与请求参数',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            children: [
                              _TaskParameter(
                                label: '任务类型',
                                value: recognition ? '图片色号识别' : 'AI 拼豆图纸',
                              ),
                              _TaskParameter(label: '当前阶段', value: task.phase),
                              _TaskParameter(label: '模型', value: task.model),
                              _TaskParameter(
                                label: '样式',
                                value: '${task.styleTitle}（${task.styleId}）',
                              ),
                              const _TaskParameter(
                                label: '输出尺寸',
                                value: '1024×1024',
                              ),
                              _TaskParameter(
                                label: '参考图',
                                value:
                                    '${(task.sourceImageByteLength / 1024).toStringAsFixed(1)} KB',
                              ),
                              _TaskParameter(
                                label: '重试设置',
                                value: task.autoRetry
                                    ? '失败后自动重试 · 已尝试 ${task.attempts} 次'
                                    : '不自动重试 · 已尝试 ${task.attempts} 次',
                              ),
                              _TaskParameter(
                                label: '提交时间',
                                value: task.createdAt.toLocal().toString(),
                              ),
                              _TaskParameter(
                                label: '用户要求',
                                value: task.displayPrompt,
                                selectable: true,
                              ),
                              _TaskParameter(
                                label: '完整 API 提示词',
                                value: task.apiPrompt,
                                selectable: true,
                              ),
                            ],
                          ),
                          const Divider(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  value: task.autoRetry,
                                  title: const Text(
                                    '失败后持续重试',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  onChanged: (value) => _center.setAutoRetry(
                                    task.id,
                                    value ?? false,
                                  ),
                                ),
                              ),
                              if (task.status == AiDesignTaskStatus.failed)
                                TextButton.icon(
                                  onPressed: () => _center.retry(task.id),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('重试'),
                                ),
                              if (task.isActive)
                                TextButton(
                                  onPressed: () => _center.cancel(task.id),
                                  child: const Text('取消任务'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _status(AiDesignTask task) => switch (task.status) {
    AiDesignTaskStatus.queued => '排队等待 · 已尝试 ${task.attempts} 次',
    AiDesignTaskStatus.running => '正在后台生成 · 第 ${task.attempts} 次尝试',
    AiDesignTaskStatus.waitingToRetry => '生成失败，等待自动重试 · 已尝试 ${task.attempts} 次',
    AiDesignTaskStatus.succeeded => '生成成功 · 点击查看',
    AiDesignTaskStatus.failed => '生成失败 · 可手动重试',
    AiDesignTaskStatus.cancelled => '任务已取消',
  };
}

class _TaskParameter extends StatelessWidget {
  const _TaskParameter({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            '$label：',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: selectable
              ? SelectableText(value, style: const TextStyle(fontSize: 11))
              : Text(value, style: const TextStyle(fontSize: 11)),
        ),
      ],
    ),
  );
}

class _TaskStatusIcon extends StatelessWidget {
  const _TaskStatusIcon({required this.task});

  final AiDesignTask task;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 42,
    child: switch (task.status) {
      AiDesignTaskStatus.running => const Padding(
        padding: EdgeInsets.all(9),
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
      AiDesignTaskStatus.succeeded => const Icon(
        Icons.check_circle_rounded,
        color: Color(0xFF1F7A4C),
        size: 36,
      ),
      AiDesignTaskStatus.failed => const Icon(
        Icons.error_rounded,
        color: Colors.red,
        size: 36,
      ),
      AiDesignTaskStatus.cancelled => const Icon(
        Icons.cancel_outlined,
        color: AppColors.muted,
        size: 34,
      ),
      _ => const Icon(Icons.schedule_rounded, color: AppColors.teal, size: 34),
    },
  );
}
