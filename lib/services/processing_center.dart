import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/bead_pattern.dart';
import '../models/processing_task.dart';
import 'ai_background_image_workflow.dart';
import 'app_settings.dart';
import 'pattern_processor.dart';
import 'project_repository.dart';
import 'app_notice_center.dart';

class ProcessingCenter extends ChangeNotifier {
  ProcessingCenter._({AiBackgroundImageWorkflow? imageWorkflow})
    : _imageWorkflow = imageWorkflow ?? AiBackgroundImageWorkflow.instance;

  @visibleForTesting
  ProcessingCenter.forTesting({AiBackgroundImageWorkflow? imageWorkflow})
    : _imageWorkflow = imageWorkflow ?? AiBackgroundImageWorkflow.instance;

  static final ProcessingCenter instance = ProcessingCenter._();

  final AiBackgroundImageWorkflow _imageWorkflow;
  final _processor = PatternProcessor();
  final _projects = ProjectRepository();
  final List<ProcessingTask> _tasks = [];
  final Set<String> _deletedIds = {};
  final Set<String> _deletedResultIds = {};
  final Set<String> _restorableResultIds = {};
  ProcessingOperation? _activeOperation;
  ProcessingTask? _activeTask;
  Directory? _taskDirectory;
  Future<void>? _initializing;
  int _projectRevision = 0;

  List<ProcessingTask> get tasks => List.unmodifiable(_tasks);
  int get projectRevision => _projectRevision;
  int get activeCount => _tasks.where((task) => task.isActive).length;
  int get pendingCount => _tasks
      .where(
        (task) =>
            task.status == ProcessingTaskStatus.queued ||
            task.status == ProcessingTaskStatus.paused,
      )
      .length;
  int get completedCount => _tasks
      .where((task) => task.status == ProcessingTaskStatus.completed)
      .length;
  int get failedCount =>
      _tasks.where((task) => task.status == ProcessingTaskStatus.failed).length;
  int get abnormalCount => failedCount;
  int get deletedResultCount => _deletedResultIds.length;

  bool resultDeleted(String? resultId) =>
      resultId != null && _deletedResultIds.contains(resultId);

  bool resultRestorable(String? resultId) =>
      resultId != null && _restorableResultIds.contains(resultId);

  Future<void> refreshDeletedResults() async {
    final next = <String>{};
    final trashIds = (await _projects.loadTrashSummaries())
        .map((summary) => summary.id)
        .toSet();
    final restorable = <String>{};
    for (final task in _tasks) {
      final resultId = task.resultId;
      if (task.status != ProcessingTaskStatus.completed || resultId == null) {
        continue;
      }
      if (await _projects.load(resultId) == null) {
        next.add(resultId);
        if (trashIds.contains(resultId)) restorable.add(resultId);
      }
    }
    if (next.length == _deletedResultIds.length &&
        next.containsAll(_deletedResultIds) &&
        restorable.length == _restorableResultIds.length &&
        restorable.containsAll(_restorableResultIds)) {
      return;
    }
    _deletedResultIds
      ..clear()
      ..addAll(next);
    _restorableResultIds
      ..clear()
      ..addAll(restorable);
    notifyListeners();
  }

  Future<void> restoreResult(String resultId) async {
    if (!_restorableResultIds.contains(resultId)) {
      throw StateError('回收站中没有可还原的作品');
    }
    await _projects.restoreFromTrash(resultId);
    _projectRevision++;
    await refreshDeletedResults();
  }

  Future<void> initialize() => _initializing ??= _load();

  Future<void> _load() async {
    final documents = await getApplicationDocumentsDirectory();
    _taskDirectory = Directory(
      '${documents.path}${Platform.pathSeparator}processing_tasks',
    );
    if (!await _taskDirectory!.exists()) {
      await _taskDirectory!.create(recursive: true);
    }
    await for (final entity in _taskDirectory!.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        _tasks.add(ProcessingTask.fromJson(json));
      } on Object {
        // Ignore a damaged task record and preserve the rest of the queue.
      }
    }
    _tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await refreshDeletedResults();
    notifyListeners();
    _schedule();
  }

  Future<ProcessingTask> enqueue({
    required Uint8List imageBytes,
    required String sourceName,
    required ProcessingOptions options,
    Uint8List? originalImageBytes,
    Uint8List? comparisonImageBytes,
    String? replaceProjectId,
  }) async {
    await initialize();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final source = File(
      '${_taskDirectory!.path}${Platform.pathSeparator}$id.source',
    );
    await source.writeAsBytes(imageBytes, flush: true);
    File? originalSource;
    if (originalImageBytes != null) {
      originalSource = File(
        '${_taskDirectory!.path}${Platform.pathSeparator}$id.original',
      );
      await originalSource.writeAsBytes(originalImageBytes, flush: true);
    }
    File? comparisonSource;
    if (comparisonImageBytes != null) {
      comparisonSource = File(
        '${_taskDirectory!.path}${Platform.pathSeparator}$id.comparison',
      );
      await comparisonSource.writeAsBytes(comparisonImageBytes, flush: true);
    }
    final task = ProcessingTask(
      id: id,
      sourceName: sourceName,
      sourcePath: source.path,
      originalSourcePath: originalSource?.path,
      comparisonSourcePath: comparisonSource?.path,
      options: options,
      createdAt: DateTime.now(),
      status: ProcessingTaskStatus.queued,
      progress: 0,
      phase: '等待处理',
      replaceProjectId: replaceProjectId,
    );
    _tasks.insert(0, task);
    await _persist(task);
    notifyListeners();
    _schedule();
    return task;
  }

  Future<void> pause(String id) async {
    final task = _find(id);
    if (task == null || !task.canPause) return;
    task.status = ProcessingTaskStatus.paused;
    task.phase = '已暂停，可继续处理';
    if (_activeTask?.id == id) _activeOperation?.cancel();
    await _persist(task);
    notifyListeners();
  }

  Future<void> resume(String id) async {
    final task = _find(id);
    if (task == null || !task.canResume) return;
    if (!await File(task.sourcePath).exists()) {
      task.status = ProcessingTaskStatus.failed;
      task.error = '原始图片已丢失，无法继续';
      task.phase = '无法继续';
      await _persist(task);
      notifyListeners();
      AppNoticeCenter.instance.show(
        '后台任务“${task.sourceName}”失败：原始图片已丢失，无法继续处理。',
        kind: AppNoticeKind.error,
        duration: const Duration(seconds: 12),
      );
      return;
    }
    task.status = ProcessingTaskStatus.queued;
    task.progress = 0;
    task.phase = '等待处理';
    task.error = null;
    await _persist(task);
    notifyListeners();
    _schedule();
  }

  Future<void> deleteTask(String id) async {
    final task = _find(id);
    if (task == null) return;
    _deletedIds.add(id);
    if (_activeTask?.id == id) _activeOperation?.cancel();
    _tasks.remove(task);
    notifyListeners();
    for (final path in {
      task.sourcePath,
      if (task.originalSourcePath != null) task.originalSourcePath!,
      if (task.comparisonSourcePath != null) task.comparisonSourcePath!,
      _taskJsonPath(id),
    }) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> clearCompleted() async {
    final ids = _tasks
        .where((task) => task.status == ProcessingTaskStatus.completed)
        .map((task) => task.id)
        .toList();
    for (final id in ids) {
      await deleteTask(id);
    }
  }

  Future<void> renameTask(String id, String name) async {
    final task = _find(id);
    final value = name.trim();
    if (task == null || value.isEmpty) return;
    task.sourceName = value;
    await _persist(task);
    notifyListeners();
  }

  ProcessingTask? _find(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  void _schedule() {
    if (_activeTask != null) return;
    ProcessingTask? next;
    for (final task in _tasks.reversed) {
      if (task.status == ProcessingTaskStatus.queued) {
        next = task;
        break;
      }
    }
    if (next == null) return;
    _activeTask = next;
    unawaited(_run(next));
  }

  Future<void> _run(ProcessingTask task) async {
    try {
      task.status = ProcessingTaskStatus.preparing;
      task.startedAt ??= DateTime.now();
      task.phase = '读取图片';
      task.progress = 0.01;
      notifyListeners();
      await _persist(task);
      final bytes = await File(task.sourcePath).readAsBytes();
      if (task.status == ProcessingTaskStatus.paused ||
          _deletedIds.contains(task.id)) {
        return;
      }
      var processingBytes = bytes;
      var backgroundAlreadyRemoved = false;
      if (task.options.removeBackground) {
        await AppSettings.instance.initialize();
        final cutout = await _imageWorkflow.cutout(
          sourceImage: bytes,
          imageModel: AppSettings.instance.aiImageModel,
          onProgress: (progress, phase) {
            if (_deletedIds.contains(task.id) ||
                task.status == ProcessingTaskStatus.paused) {
              return;
            }
            task.status = ProcessingTaskStatus.preparing;
            task.progress = progress.clamp(0, 0.36);
            task.phase = phase;
            notifyListeners();
          },
        );
        processingBytes = cutout.bytes;
        backgroundAlreadyRemoved = true;
        if (cutout.warning != null) {
          AppNoticeCenter.instance.show(
            cutout.warning!,
            kind: AppNoticeKind.warning,
            duration: const Duration(seconds: 12),
          );
        }
      }
      if (task.status == ProcessingTaskStatus.paused ||
          _deletedIds.contains(task.id)) {
        return;
      }
      var lastNotifiedProgress = task.progress;
      var lastPhase = task.phase;
      final operation = await _processor.start(
        processingBytes,
        task.options,
        projectSourceBytes: await _readOriginalSource(task, bytes),
        sourceName: task.sourceName,
        backgroundAlreadyRemoved: backgroundAlreadyRemoved,
        onProgress: (progress, phase) {
          if (_deletedIds.contains(task.id) ||
              task.status == ProcessingTaskStatus.paused) {
            return;
          }
          task.status = ProcessingTaskStatus.processing;
          final scaledProgress = backgroundAlreadyRemoved
              ? 0.36 + progress * 0.60
              : progress;
          task.progress = scaledProgress.clamp(0, 0.96);
          task.phase = phase;
          if (task.progress - lastNotifiedProgress >= 0.015 ||
              phase != lastPhase) {
            lastNotifiedProgress = task.progress;
            lastPhase = phase;
            notifyListeners();
          }
        },
      );
      _activeOperation = operation;
      if (task.status == ProcessingTaskStatus.paused ||
          _deletedIds.contains(task.id)) {
        operation.cancel();
        return;
      }
      final generatedPattern = await operation.result;
      _activeOperation = null;
      if (task.status == ProcessingTaskStatus.paused ||
          _deletedIds.contains(task.id)) {
        return;
      }
      task.status = ProcessingTaskStatus.saving;
      task.progress = 0.97;
      task.phase = '保存作品与缩略图';
      notifyListeners();
      var pattern = generatedPattern;
      final comparisonBytes = await _readOptionalBytes(
        task.comparisonSourcePath,
      );
      task.completedAt = DateTime.now();
      pattern = BeadPattern(
        id: pattern.id,
        title: pattern.title,
        width: pattern.width,
        height: pattern.height,
        colors: pattern.colors,
        cells: pattern.cells,
        sourceBytes: pattern.sourceBytes,
        referenceBytes: comparisonBytes ?? pattern.referenceBytes,
        createdAt: pattern.createdAt,
        requestedColorCount: pattern.requestedColorCount,
        portraitMode: pattern.portraitMode,
        backgroundRemoved: pattern.backgroundRemoved,
        template: pattern.template,
        sourceName: task.sourceName,
        processingDurationMs: task.elapsed.inMilliseconds,
        smoothing: pattern.smoothing,
        variantSeed: pattern.variantSeed,
        paletteId: pattern.paletteId,
      );
      final replaceProjectId = task.replaceProjectId;
      if (replaceProjectId != null) {
        final previous = await _projects.load(replaceProjectId);
        if (previous != null) {
          await _projects.snapshotToTrash(
            replaceProjectId,
            deletionSource: task.options.variantSeed == 0
                ? '重新设置参数覆盖'
                : '不同方案覆盖',
          );
          pattern = BeadPattern(
            id: previous.id,
            title: previous.title,
            width: generatedPattern.width,
            height: generatedPattern.height,
            colors: generatedPattern.colors,
            cells: generatedPattern.cells,
            sourceBytes: generatedPattern.sourceBytes,
            referenceBytes: comparisonBytes ?? generatedPattern.referenceBytes,
            createdAt: previous.createdAt,
            requestedColorCount: generatedPattern.requestedColorCount,
            portraitMode: generatedPattern.portraitMode,
            backgroundRemoved: generatedPattern.backgroundRemoved,
            template: generatedPattern.template,
            sourceName: generatedPattern.sourceName,
            processingDurationMs: task.elapsed.inMilliseconds,
            smoothing: generatedPattern.smoothing,
            variantSeed: generatedPattern.variantSeed,
            isCustomBoard: false,
            paletteId: generatedPattern.paletteId,
          );
        }
      }
      await _projects.save(pattern);
      String? savedThumbnailPath;
      for (final summary in await _projects.loadSummaries()) {
        if (summary.id == pattern.id) {
          savedThumbnailPath = summary.thumbnailPath;
          break;
        }
      }
      task.status = ProcessingTaskStatus.completed;
      task.progress = 1;
      task.phase = '处理完成';
      task.resultId = pattern.id;
      task.resultThumbnailPath = savedThumbnailPath;
      _deletedResultIds.remove(pattern.id);
      task.error = null;
      _projectRevision++;
      final source = File(task.sourcePath);
      if (await source.exists()) await source.delete();
      final originalPath = task.originalSourcePath;
      if (originalPath != null) {
        final original = File(originalPath);
        if (await original.exists()) await original.delete();
      }
      final comparisonPath = task.comparisonSourcePath;
      if (comparisonPath != null) {
        final comparison = File(comparisonPath);
        if (await comparison.exists()) await comparison.delete();
      }
      await _persist(task);
      notifyListeners();
      AppNoticeCenter.instance.show(
        '后台任务“${task.sourceName}”处理成功，已保存到“我的作品”。',
        kind: AppNoticeKind.success,
        duration: const Duration(seconds: 10),
      );
    } on ProcessingCancelledException {
      if (!_deletedIds.contains(task.id)) {
        task.status = ProcessingTaskStatus.paused;
        task.phase = '已暂停，可继续处理';
        await _persist(task);
        notifyListeners();
      }
    } on Object catch (error) {
      if (!_deletedIds.contains(task.id)) {
        task.status = ProcessingTaskStatus.failed;
        task.phase = '处理失败';
        task.error = error.toString();
        await _persist(task);
        notifyListeners();
        AppNoticeCenter.instance.showError(
          error,
          operation: '后台任务“${task.sourceName}”',
        );
      }
    } finally {
      _activeOperation = null;
      if (_activeTask?.id == task.id) _activeTask = null;
      _deletedIds.remove(task.id);
      _schedule();
    }
  }

  String _taskJsonPath(String id) =>
      '${_taskDirectory!.path}${Platform.pathSeparator}$id.json';

  Future<Uint8List> _readOriginalSource(
    ProcessingTask task,
    Uint8List fallback,
  ) async {
    final path = task.originalSourcePath;
    if (path == null) return fallback;
    final file = File(path);
    return await file.exists() ? file.readAsBytes() : fallback;
  }

  Future<Uint8List?> _readOptionalBytes(String? path) async {
    if (path == null) return null;
    final file = File(path);
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> _persist(ProcessingTask task) async {
    if (_deletedIds.contains(task.id)) return;
    final file = File(_taskJsonPath(task.id));
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(task.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
