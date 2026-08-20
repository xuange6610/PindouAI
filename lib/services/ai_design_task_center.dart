import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ai_design_history.dart';
import 'ai_background_image_workflow.dart';
import 'ai_design_service.dart';
import 'app_error.dart';
import 'app_notice_center.dart';
import 'app_settings.dart';

enum AiDesignTaskStatus {
  queued,
  running,
  waitingToRetry,
  succeeded,
  failed,
  cancelled,
}

enum AiDesignTaskScope { design, colorRecognition }

typedef AiDesignImageGenerator =
    Future<AiImageResult> Function({
      required String prompt,
      required Uint8List imageBytes,
      required String model,
    });

class AiDesignTask {
  const AiDesignTask({
    required this.id,
    required this.styleId,
    required this.styleTitle,
    required this.displayPrompt,
    required this.apiPrompt,
    required this.sourceImage,
    required this.model,
    required this.createdAt,
    required this.status,
    required this.autoRetry,
    required this.backgrounded,
    this.scope = AiDesignTaskScope.design,
    this.attempts = 0,
    this.error,
    this.nextRetryAt,
    this.result,
    this.historyEntry,
    this.progress = 0,
    this.phase = '等待处理',
    this.startedAt,
    this.completedAt,
    this.sourceImageByteLength = 0,
  });

  final String id;
  final String styleId;
  final String styleTitle;
  final String displayPrompt;
  final String apiPrompt;
  final Uint8List sourceImage;
  final String model;
  final DateTime createdAt;
  final AiDesignTaskStatus status;
  final bool autoRetry;
  final bool backgrounded;
  final AiDesignTaskScope scope;
  final int attempts;
  final String? error;
  final DateTime? nextRetryAt;
  final AiImageResult? result;
  final AiDesignHistoryEntry? historyEntry;
  final double progress;
  final String phase;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int sourceImageByteLength;

  bool get isActive => const {
    AiDesignTaskStatus.queued,
    AiDesignTaskStatus.running,
    AiDesignTaskStatus.waitingToRetry,
  }.contains(status);

  AiDesignTask copyWith({
    Uint8List? sourceImage,
    AiDesignTaskStatus? status,
    bool? autoRetry,
    bool? backgrounded,
    AiDesignTaskScope? scope,
    int? attempts,
    String? error,
    bool clearError = false,
    DateTime? nextRetryAt,
    bool clearNextRetry = false,
    AiImageResult? result,
    AiDesignHistoryEntry? historyEntry,
    double? progress,
    String? phase,
    DateTime? startedAt,
    DateTime? completedAt,
  }) => AiDesignTask(
    id: id,
    styleId: styleId,
    styleTitle: styleTitle,
    displayPrompt: displayPrompt,
    apiPrompt: apiPrompt,
    sourceImage: sourceImage ?? this.sourceImage,
    model: model,
    createdAt: createdAt,
    status: status ?? this.status,
    autoRetry: autoRetry ?? this.autoRetry,
    backgrounded: backgrounded ?? this.backgrounded,
    scope: scope ?? this.scope,
    attempts: attempts ?? this.attempts,
    error: clearError ? null : error ?? this.error,
    nextRetryAt: clearNextRetry ? null : nextRetryAt ?? this.nextRetryAt,
    result: result ?? this.result,
    historyEntry: historyEntry ?? this.historyEntry,
    progress: progress ?? this.progress,
    phase: phase ?? this.phase,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt ?? this.completedAt,
    sourceImageByteLength: sourceImageByteLength,
  );
}

class AiDesignTaskCenter extends ChangeNotifier {
  AiDesignTaskCenter({
    AiDesignImageGenerator? generator,
    AiBackgroundImageWorkflow? imageWorkflow,
    AiDesignHistoryStore history = const AiDesignHistoryStore(),
    this.retryBaseDelay = const Duration(seconds: 8),
  }) : _generator = generator,
       _imageWorkflow = imageWorkflow ?? AiBackgroundImageWorkflow.instance,
       _history = history;

  static final instance = AiDesignTaskCenter();

  final AiDesignImageGenerator? _generator;
  final AiBackgroundImageWorkflow _imageWorkflow;
  final AiDesignHistoryStore _history;
  final Duration retryBaseDelay;
  final List<AiDesignTask> _tasks = [];
  final Map<String, Timer> _retryTimers = {};
  final Map<String, Timer> _progressTimers = {};
  var _running = false;

  List<AiDesignTask> get tasks => List.unmodifiable(_tasks);
  List<AiDesignTask> get visibleTasks =>
      visibleTasksFor(AiDesignTaskScope.design);
  int get activeBackgroundCount =>
      activeBackgroundCountFor(AiDesignTaskScope.design);

  List<AiDesignTask> visibleTasksFor(AiDesignTaskScope scope) =>
      List.unmodifiable(
        _tasks.where((task) => task.backgrounded && task.scope == scope),
      );

  int activeBackgroundCountFor(AiDesignTaskScope scope) =>
      visibleTasksFor(scope).where((task) => task.isActive).length;

  AiDesignTask? taskById(String? id) {
    if (id == null) return null;
    return _tasks.where((task) => task.id == id).firstOrNull;
  }

  String enqueue({
    required String styleId,
    required String styleTitle,
    required String displayPrompt,
    required String apiPrompt,
    required Uint8List sourceImage,
    required String model,
    required bool autoRetry,
    required bool backgrounded,
    AiDesignTaskScope scope = AiDesignTaskScope.design,
  }) {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    _tasks.insert(
      0,
      AiDesignTask(
        id: id,
        styleId: styleId,
        styleTitle: styleTitle,
        displayPrompt: displayPrompt,
        apiPrompt: apiPrompt,
        sourceImage: Uint8List.fromList(sourceImage),
        model: model,
        createdAt: now,
        status: AiDesignTaskStatus.queued,
        autoRetry: autoRetry,
        backgrounded: backgrounded,
        scope: scope,
        phase: '等待后台调度',
        sourceImageByteLength: sourceImage.length,
      ),
    );
    notifyListeners();
    _pump();
    return id;
  }

  void moveToCenter(String id) =>
      _update(id, (task) => task.copyWith(backgrounded: true));

  void setAutoRetry(String id, bool value) {
    final task = taskById(id);
    if (task == null) return;
    _update(id, (current) => current.copyWith(autoRetry: value));
    if (value && task.status == AiDesignTaskStatus.failed) retry(id);
    if (!value && task.status == AiDesignTaskStatus.waitingToRetry) {
      _retryTimers.remove(id)?.cancel();
      _update(
        id,
        (current) => current.copyWith(
          status: AiDesignTaskStatus.failed,
          clearNextRetry: true,
          phase: '已停止自动重试，任务失败',
          progress: 0,
          completedAt: DateTime.now(),
        ),
      );
      if (task.backgrounded && task.error != null) {
        AppNoticeCenter.instance.show(
          task.error!,
          kind: AppNoticeKind.error,
          duration: const Duration(seconds: 14),
        );
      }
    }
  }

  void retry(String id) {
    final task = taskById(id);
    if (task == null || task.status == AiDesignTaskStatus.running) return;
    _retryTimers.remove(id)?.cancel();
    _update(
      id,
      (current) => current.copyWith(
        status: AiDesignTaskStatus.queued,
        clearError: true,
        clearNextRetry: true,
        progress: 0,
        phase: '重新排队等待',
      ),
    );
    _pump();
  }

  void cancel(String id) {
    final task = taskById(id);
    if (task == null || task.status == AiDesignTaskStatus.succeeded) return;
    _retryTimers.remove(id)?.cancel();
    _progressTimers.remove(id)?.cancel();
    _update(
      id,
      (current) => current.copyWith(
        status: AiDesignTaskStatus.cancelled,
        clearNextRetry: true,
        phase: '任务已取消',
      ),
    );
  }

  void remove(String id) {
    final task = taskById(id);
    if (task == null || task.isActive) return;
    _retryTimers.remove(id)?.cancel();
    _progressTimers.remove(id)?.cancel();
    _tasks.removeWhere((value) => value.id == id);
    notifyListeners();
  }

  void _pump() {
    if (_running) return;
    final next = _tasks
        .where((task) => task.status == AiDesignTaskStatus.queued)
        .lastOrNull;
    if (next == null) return;
    _running = true;
    _update(
      next.id,
      (task) => task.copyWith(
        status: AiDesignTaskStatus.running,
        attempts: task.attempts + 1,
        clearError: true,
        clearNextRetry: true,
        progress: 0.08,
        phase: '准备参考图与请求参数',
        startedAt: task.startedAt ?? DateTime.now(),
      ),
    );
    unawaited(_execute(next.id));
  }

  Future<void> _execute(String id) async {
    try {
      final task = taskById(id);
      if (task == null) return;
      _update(
        id,
        (value) => value.copyWith(progress: 0.14, phase: '准备后台 AI 识图链路'),
      );
      _progressTimers.remove(id)?.cancel();
      _progressTimers[id] = Timer.periodic(const Duration(seconds: 1), (_) {
        final latest = taskById(id);
        if (latest == null || latest.status != AiDesignTaskStatus.running) {
          _progressTimers.remove(id)?.cancel();
          return;
        }
        _update(
          id,
          (value) => value.copyWith(
            progress: (value.progress + 0.015).clamp(0.0, 0.88),
            phase: value.phase,
          ),
        );
      });
      await AppSettings.instance.initialize();
      final customGenerator = _generator;
      final result = customGenerator == null
          ? await _imageWorkflow.generateBeadDesign(
              prompt: task.apiPrompt,
              referenceImage: task.sourceImage,
              imageModel: task.model,
              visionModel: AppSettings.instance.aiChatModel,
              onProgress: (progress, phase) {
                final latest = taskById(id);
                if (latest == null ||
                    latest.status != AiDesignTaskStatus.running) {
                  return;
                }
                _update(
                  id,
                  (value) => value.copyWith(
                    progress: progress.clamp(value.progress, 0.88),
                    phase: phase,
                  ),
                );
              },
            )
          : await customGenerator(
              prompt: task.apiPrompt,
              imageBytes: task.sourceImage,
              model: task.model,
            );
      final current = taskById(id);
      if (current == null || current.status == AiDesignTaskStatus.cancelled) {
        return;
      }
      _progressTimers.remove(id)?.cancel();
      _update(
        id,
        (value) => value.copyWith(progress: 0.94, phase: '生成成功，正在保存记录'),
      );
      var entry = AiDesignHistoryEntry(
        id: id,
        prompt: current.displayPrompt,
        content: current.scope == AiDesignTaskScope.colorRecognition
            ? '已为图片色号识别生成清晰参考图。'
            : '已按${current.styleTitle}生成，可预览、保存或转换为拼豆图。',
        model: result.model,
        createdAt: current.createdAt,
        styleId: current.styleId,
      );
      entry = await _history.saveImage(entry, result.bytes);
      _update(
        id,
        (value) => value.copyWith(
          status: AiDesignTaskStatus.succeeded,
          sourceImage: Uint8List(0),
          result: current.backgrounded ? null : result,
          historyEntry: entry,
          clearError: true,
          clearNextRetry: true,
          progress: 1,
          phase: '生成记录已保存',
          completedAt: DateTime.now(),
        ),
      );
      if (current.backgrounded) {
        AppNoticeCenter.instance.show(
          '${current.styleTitle}后台生成成功 · 模型 ${result.model} · '
          '共尝试 ${current.attempts} 次',
          kind: AppNoticeKind.success,
          duration: const Duration(seconds: 10),
        );
      }
    } on Object catch (error) {
      _progressTimers.remove(id)?.cancel();
      final task = taskById(id);
      if (task == null || task.status == AiDesignTaskStatus.cancelled) return;
      final errorInfo = AppErrorClassifier.classify(
        error,
        operation: task.scope == AiDesignTaskScope.colorRecognition
            ? 'AI 图片色号识别'
            : 'AI 拼豆图生成',
      );
      if (task.autoRetry) {
        final multiplier = task.attempts.clamp(1, 8);
        final delay = Duration(
          milliseconds: retryBaseDelay.inMilliseconds * multiplier,
        );
        _update(
          id,
          (value) => value.copyWith(
            status: AiDesignTaskStatus.waitingToRetry,
            error: errorInfo.displayText,
            nextRetryAt: DateTime.now().add(delay),
            phase: '本次失败，等待 ${delay.inSeconds} 秒后自动重试',
            progress: 0,
          ),
        );
        _retryTimers[id]?.cancel();
        _retryTimers[id] = Timer(delay, () {
          _retryTimers.remove(id);
          final latest = taskById(id);
          if (latest == null ||
              !latest.autoRetry ||
              latest.status != AiDesignTaskStatus.waitingToRetry) {
            return;
          }
          _update(
            id,
            (value) => value.copyWith(
              status: AiDesignTaskStatus.queued,
              clearNextRetry: true,
              phase: '重新排队等待',
            ),
          );
          _pump();
        });
      } else {
        _update(
          id,
          (value) => value.copyWith(
            status: AiDesignTaskStatus.failed,
            error: errorInfo.displayText,
            clearNextRetry: true,
            phase: '生成失败，等待手动重试',
            progress: 0,
            completedAt: DateTime.now(),
          ),
        );
        if (task.backgrounded) {
          AppNoticeCenter.instance.show(
            errorInfo.displayText,
            kind: AppNoticeKind.error,
            duration: const Duration(seconds: 14),
          );
        }
      }
    } finally {
      _running = false;
      _pump();
    }
  }

  void _update(String id, AiDesignTask Function(AiDesignTask task) transform) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    _tasks[index] = transform(_tasks[index]);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    for (final timer in _progressTimers.values) {
      timer.cancel();
    }
    _progressTimers.clear();
    super.dispose();
  }
}
