import 'bead_pattern.dart';
import 'bead_palette.dart';
import '../services/pattern_processor.dart';

enum ProcessingTaskStatus {
  queued,
  preparing,
  processing,
  paused,
  saving,
  completed,
  failed,
}

class ProcessingTask {
  ProcessingTask({
    required this.id,
    required this.sourceName,
    required this.sourcePath,
    required this.options,
    required this.createdAt,
    required this.status,
    required this.progress,
    required this.phase,
    this.originalSourcePath,
    this.comparisonSourcePath,
    this.resultId,
    this.replaceProjectId,
    this.error,
    this.startedAt,
    this.completedAt,
    this.resultThumbnailPath,
  });

  final String id;
  String sourceName;
  final String sourcePath;
  final String? originalSourcePath;
  final String? comparisonSourcePath;
  final ProcessingOptions options;
  final DateTime createdAt;
  ProcessingTaskStatus status;
  double progress;
  String phase;
  String? resultId;
  final String? replaceProjectId;
  String? error;
  DateTime? startedAt;
  DateTime? completedAt;
  String? resultThumbnailPath;

  Duration get elapsed {
    final start = startedAt ?? createdAt;
    return (completedAt ?? DateTime.now()).difference(start);
  }

  bool get isActive =>
      status == ProcessingTaskStatus.preparing ||
      status == ProcessingTaskStatus.processing ||
      status == ProcessingTaskStatus.saving;

  bool get canPause => status == ProcessingTaskStatus.queued || isActive;

  bool get canResume =>
      status == ProcessingTaskStatus.paused ||
      status == ProcessingTaskStatus.failed;

  Map<String, Object?> toJson() => {
    'id': id,
    'sourceName': sourceName,
    'sourcePath': sourcePath,
    'originalSourcePath': originalSourcePath,
    'comparisonSourcePath': comparisonSourcePath,
    'size': options.size,
    'height': options.outputHeight,
    'maxColors': options.maxColors,
    'portraitMode': options.portraitMode,
    'smoothing': options.smoothing,
    'removeBackground': options.removeBackground,
    'template': options.template.name,
    'variantSeed': options.variantSeed,
    'paletteId': options.paletteId.storageId,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'progress': progress,
    'phase': phase,
    'resultId': resultId,
    'replaceProjectId': replaceProjectId,
    'error': error,
    'startedAt': startedAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'resultThumbnailPath': resultThumbnailPath,
  };

  factory ProcessingTask.fromJson(Map<String, dynamic> json) {
    final storedStatus = ProcessingTaskStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => ProcessingTaskStatus.paused,
    );
    final restoredStatus = switch (storedStatus) {
      ProcessingTaskStatus.preparing ||
      ProcessingTaskStatus.processing ||
      ProcessingTaskStatus.saving => ProcessingTaskStatus.paused,
      _ => storedStatus,
    };
    return ProcessingTask(
      id: json['id'] as String,
      sourceName: json['sourceName'] as String,
      sourcePath: json['sourcePath'] as String,
      originalSourcePath: json['originalSourcePath'] as String?,
      comparisonSourcePath: json['comparisonSourcePath'] as String?,
      options: ProcessingOptions(
        size: json['size'] as int,
        height: json['height'] as int?,
        maxColors: json['maxColors'] as int,
        portraitMode: json['portraitMode'] as bool,
        smoothing: json['smoothing'] as bool,
        removeBackground: json['removeBackground'] as bool? ?? false,
        template: PatternTemplate.values.firstWhere(
          (value) => value.name == json['template'],
          orElse: () => PatternTemplate.none,
        ),
        variantSeed: json['variantSeed'] as int? ?? 0,
        paletteId:
            BeadPaletteIdStorage.tryParse(json['paletteId'] as String?) ??
            BeadPaletteId.artkal397,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      status: restoredStatus,
      progress: (json['progress'] as num).toDouble(),
      phase: restoredStatus == ProcessingTaskStatus.paused
          ? '已暂停，可继续处理'
          : _localizedStoredMessage(json['phase']?.toString()) ?? '等待处理',
      resultId: json['resultId'] as String?,
      replaceProjectId: json['replaceProjectId'] as String?,
      error: _localizedStoredMessage(json['error']?.toString()),
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      resultThumbnailPath: json['resultThumbnailPath'] as String?,
    );
  }

  static String? _localizedStoredMessage(String? source) {
    if (source == null || source.trim().isEmpty) return null;
    final value = source.trim();
    const exact = <String, String>{
      'RESULT DELETED': '作品已删除',
      'Generated result deleted': '生成结果已被删除，无法查看作品',
      'Generated result was deleted': '生成结果已被删除，无法查看作品',
      'Result deleted': '生成结果已被删除，无法查看作品',
      'Waiting': '等待处理',
      'Preparing image': '准备图片',
      'Reading image': '读取图片',
      'Processing': '正在处理',
      'Saving': '正在保存',
      'Completed': '处理完成',
      'Failed': '处理失败',
      'Paused': '已暂停，可继续处理',
    };
    if (exact.containsKey(value)) return exact[value];
    if (!RegExp(r'[A-Za-z]').hasMatch(value)) return value;
    final lower = value.toLowerCase();
    if (lower.contains('delete')) return '生成结果已被删除，无法查看作品';
    if (lower.contains('not found') || lower.contains('missing')) {
      return '原始图片已丢失，无法继续处理';
    }
    if (lower.contains('cancel')) return '任务已暂停，可继续处理';
    return '处理异常，请检查图片后重试';
  }
}
