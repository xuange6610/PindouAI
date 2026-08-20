import 'dart:typed_data';

import 'bead_color.dart';
import 'bead_palette.dart';

enum PatternTemplate {
  none('无模板', '保持当前的纯编号格子图'),
  classic('经典标题', '大标题、四边坐标与底部用量色卡'),
  fresh('清爽图纸（10*10）', '轻量标题栏、每 10 格分区粗线与紧凑用量表'),
  mard('Artkal 色号（5*5）', '淡蓝坐标栏、每 5 格分区、四边编号与横向色号清单');

  const PatternTemplate(this.label, this.description);

  final String label;
  final String description;
}

class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.title,
    required this.width,
    required this.height,
    required this.colorCount,
    required this.createdAt,
    required this.thumbnailPath,
    required this.isFavorite,
    this.beadCount,
    this.deletedAt,
    this.favoriteCategory,
    this.sourceName,
    this.deletedFrom,
    this.isCustomBoard = false,
    this.isPhotoProject = false,
  });

  final String id;
  final String title;
  final int width;
  final int height;
  final int colorCount;
  final DateTime createdAt;
  final String? thumbnailPath;
  final bool isFavorite;
  final int? beadCount;
  final DateTime? deletedAt;
  final String? favoriteCategory;
  final String? sourceName;
  final String? deletedFrom;
  final bool isCustomBoard;
  final bool isPhotoProject;

  int get totalBeads => beadCount ?? width * height;
}

class BeadPattern {
  BeadPattern({
    required this.id,
    required this.title,
    required this.width,
    required this.height,
    required this.colors,
    required this.cells,
    required this.sourceBytes,
    required this.createdAt,
    required this.requestedColorCount,
    required this.portraitMode,
    this.referenceBytes,
    this.backgroundRemoved = false,
    this.template = PatternTemplate.none,
    this.sourceName,
    this.processingDurationMs,
    this.smoothing = true,
    this.variantSeed = 0,
    this.isCustomBoard = false,
    this.isPhotoProject = false,
    this.paletteId = BeadPaletteId.artkal397,
  });

  final String id;
  String title;
  final int width;
  final int height;
  final List<BeadColor> colors;
  final List<int> cells;
  final Uint8List sourceBytes;
  final DateTime createdAt;
  final int requestedColorCount;
  final bool portraitMode;
  final Uint8List? referenceBytes;
  final bool backgroundRemoved;
  final PatternTemplate template;
  final String? sourceName;
  final int? processingDurationMs;
  final bool smoothing;
  final int variantSeed;
  final bool isCustomBoard;
  final bool isPhotoProject;
  final BeadPaletteId paletteId;

  int get totalBeads => cells.where((colorIndex) => colorIndex >= 0).length;

  ({int left, int top, int width, int height}) get occupiedBounds {
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;
    for (var index = 0; index < cells.length; index++) {
      if (cells[index] < 0) continue;
      final x = index % width;
      final y = index ~/ width;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    if (maxX < 0 || maxY < 0) return (left: 0, top: 0, width: 0, height: 0);
    return (
      left: minX,
      top: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    );
  }

  String get minimumBoardSize {
    final bounds = occupiedBounds;
    return '${bounds.width}×${bounds.height} 格';
  }

  Map<int, int> get counts {
    final result = <int, int>{};
    for (final colorIndex in cells) {
      if (colorIndex < 0) continue;
      result[colorIndex] = (result[colorIndex] ?? 0) + 1;
    }
    return result;
  }

  List<MapEntry<int, int>> get sortedCounts {
    final result = counts.entries.toList();
    result.sort((a, b) => b.value.compareTo(a.value));
    return result;
  }
}
