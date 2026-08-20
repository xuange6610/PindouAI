import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../data/bead_palettes.dart';
import '../models/bead_color.dart';
import '../models/bead_palette.dart';
import '../models/bead_pattern.dart';

class ProjectRepository {
  static const defaultTrashRetentionDays = 30;
  static const maxTrashRetentionDays = 3650;
  static const defaultFavoriteCategories = ['收藏柜哦', '收藏柜呀', '收藏柜呢'];
  static const _projectExtensions = [
    'json',
    'summary.json',
    'source',
    'reference',
    'thumb.png',
  ];

  Future<Directory> _documentsDirectory() => getApplicationDocumentsDirectory();

  Future<Directory> _directory() async {
    final documents = await _documentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}patterns',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _trashDirectory() async {
    final documents = await _documentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}patterns_trash',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> _settingsFile() async {
    final documents = await _documentsDirectory();
    return File(
      '${documents.path}${Platform.pathSeparator}recycle_bin_settings.json',
    );
  }

  Future<File> _favoriteCategoriesFile() async {
    final documents = await _documentsDirectory();
    return File(
      '${documents.path}${Platform.pathSeparator}favorite_categories.json',
    );
  }

  Future<File> _projectOrderFile() async {
    final documents = await _documentsDirectory();
    return File('${documents.path}${Platform.pathSeparator}project_order.json');
  }

  Future<void> save(BeadPattern pattern) async {
    final directory = await _directory();
    final sourceFile = File(
      '${directory.path}${Platform.pathSeparator}${pattern.id}.source',
    );
    final referenceFile = File(
      '${directory.path}${Platform.pathSeparator}${pattern.id}.reference',
    );
    final jsonFile = File(
      '${directory.path}${Platform.pathSeparator}${pattern.id}.json',
    );
    final summaryFile = File(
      '${directory.path}${Platform.pathSeparator}${pattern.id}.summary.json',
    );
    final thumbnailFile = File(
      '${directory.path}${Platform.pathSeparator}${pattern.id}.thumb.png',
    );
    var isFavorite = false;
    String? favoriteCategory;
    if (await summaryFile.exists()) {
      try {
        final previous =
            jsonDecode(await summaryFile.readAsString())
                as Map<String, dynamic>;
        isFavorite = previous['isFavorite'] as bool? ?? false;
        favoriteCategory = previous['favoriteCategory'] as String?;
      } on Object {
        // A damaged index is replaced by the newly generated project index.
      }
    }
    await sourceFile.writeAsBytes(pattern.sourceBytes, flush: true);
    final referenceBytes = pattern.referenceBytes;
    if (referenceBytes != null) {
      await referenceFile.writeAsBytes(referenceBytes, flush: true);
    } else if (await referenceFile.exists()) {
      await referenceFile.delete();
    }
    final byteData = ByteData(pattern.cells.length * 2);
    for (var i = 0; i < pattern.cells.length; i++) {
      byteData.setUint16(
        i * 2,
        pattern.cells[i] < 0 ? 0xFFFF : pattern.cells[i],
        Endian.little,
      );
    }
    final payload = <String, Object>{
      'schema': 4,
      'id': pattern.id,
      'title': pattern.title,
      'width': pattern.width,
      'height': pattern.height,
      'createdAt': pattern.createdAt.toIso8601String(),
      'requestedColorCount': pattern.requestedColorCount,
      'portraitMode': pattern.portraitMode,
      'backgroundRemoved': pattern.backgroundRemoved,
      'template': pattern.template.name,
      'sourceName': pattern.sourceName ?? '',
      'processingDurationMs': pattern.processingDurationMs ?? 0,
      'smoothing': pattern.smoothing,
      'variantSeed': pattern.variantSeed,
      'paletteId': pattern.paletteId.storageId,
      'isCustomBoard': pattern.isCustomBoard,
      'isPhotoProject': pattern.isPhotoProject,
      'colorCount': pattern.colors.length,
      'beadCount': pattern.totalBeads,
      'colors': pattern.colors.map((color) => color.code).toList(),
      'cells': base64Encode(byteData.buffer.asUint8List()),
    };
    final summaryPayload = <String, Object>{
      'schema': 3,
      'id': pattern.id,
      'title': pattern.title,
      'width': pattern.width,
      'height': pattern.height,
      'colorCount': pattern.colors.length,
      'beadCount': pattern.totalBeads,
      'createdAt': pattern.createdAt.toIso8601String(),
      'isFavorite': isFavorite,
      if (favoriteCategory case final String value) 'favoriteCategory': value,
      if (pattern.sourceName != null) 'sourceName': pattern.sourceName!,
      'isCustomBoard': pattern.isCustomBoard,
      'isPhotoProject': pattern.isPhotoProject,
    };
    final thumbnail = pattern.isPhotoProject
        ? await compute(_renderPhotoThumbnail, pattern.sourceBytes)
        : await compute(_renderProjectThumbnail, {
            'width': pattern.width,
            'height': pattern.height,
            'cells': pattern.cells,
            'colors': [
              for (final color in pattern.colors)
                [color.red, color.green, color.blue],
            ],
          });
    await thumbnailFile.writeAsBytes(thumbnail, flush: true);
    final temporary = File('${jsonFile.path}.tmp');
    await temporary.writeAsString(jsonEncode(payload), flush: true);
    if (await jsonFile.exists()) await jsonFile.delete();
    await temporary.rename(jsonFile.path);
    await _writeSummaryFile(summaryFile, summaryPayload);
  }

  /// Stores an AI-generated image as the original photo. No AI request,
  /// palette matching, resizing of the source, or bead conversion is involved.
  Future<BeadPattern> savePhotoProject(
    Uint8List bytes, {
    required String title,
    required String sourceName,
  }) async {
    if (bytes.isEmpty || img.decodeImage(bytes) == null) {
      throw const FormatException('图片文件已损坏或格式不受支持');
    }
    final now = DateTime.now();
    final pattern = BeadPattern(
      id: 'photo_${now.microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'AI 原图' : title.trim(),
      width: 1,
      height: 1,
      colors: [BeadPalettes.artkal397.colors.first],
      cells: const [0],
      sourceBytes: bytes,
      createdAt: now,
      requestedColorCount: 1,
      portraitMode: false,
      smoothing: false,
      sourceName: sourceName,
      isPhotoProject: true,
    );
    await save(pattern);
    return pattern;
  }

  Future<List<ProjectSummary>> loadSummaries() async {
    final directory = await _directory();
    final result = <ProjectSummary>[];
    final files = await directory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    final loadedIds = <String>{};

    for (final file in files.where(
      (file) => file.path.endsWith('.summary.json'),
    )) {
      try {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final summary = await _summaryFromJson(directory, json);
        result.add(summary);
        loadedIds.add(summary.id);
      } on Object {
        // A damaged sidecar falls back to its full project header below.
      }
    }

    for (final file in files.where(
      (file) =>
          file.path.endsWith('.json') && !file.path.endsWith('.summary.json'),
    )) {
      try {
        final json = await _readProjectHeader(file);
        final id = json['id'] as String;
        if (loadedIds.contains(id)) continue;
        final summary = await _summaryFromJson(directory, json);
        result.add(summary);
        loadedIds.add(id);
        final sidecar = File(
          '${directory.path}${Platform.pathSeparator}$id.summary.json',
        );
        await _writeSummaryFile(sidecar, {
          'schema': 1,
          'id': summary.id,
          'title': summary.title,
          'width': summary.width,
          'height': summary.height,
          'colorCount': summary.colorCount,
          if (summary.beadCount != null) 'beadCount': summary.beadCount!,
          'createdAt': summary.createdAt.toIso8601String(),
          'isFavorite': summary.isFavorite,
          if (summary.sourceName != null) 'sourceName': summary.sourceName!,
          'isCustomBoard': summary.isCustomBoard,
          'isPhotoProject': summary.isPhotoProject,
        });
      } on Object {
        // A damaged project is ignored so the remaining local library still opens.
      }
    }
    final orderFile = await _projectOrderFile();
    var order = <String>[];
    if (await orderFile.exists()) {
      try {
        order = (jsonDecode(await orderFile.readAsString()) as List)
            .cast<String>();
      } on Object {
        order = [];
      }
    }
    final positions = <String, int>{
      for (var index = 0; index < order.length; index++) order[index]: index,
    };
    result.sort((a, b) {
      final left = positions[a.id];
      final right = positions[b.id];
      if (left != null || right != null) {
        if (left == null) return 1;
        if (right == null) return -1;
        return left.compareTo(right);
      }
      if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return result;
  }

  Future<BeadPattern?> load(String id) async {
    final directory = await _directory();
    final jsonFile = File('${directory.path}${Platform.pathSeparator}$id.json');
    final source = File('${directory.path}${Platform.pathSeparator}$id.source');
    final reference = File(
      '${directory.path}${Platform.pathSeparator}$id.reference',
    );
    if (!await jsonFile.exists() || !await source.exists()) return null;
    try {
      final json =
          jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
      final colorCodes = (json['colors'] as List).cast<String>();
      final palette = BeadPalettes.forStoredProject(
        json['paletteId'] as String?,
        colorCodes,
      );
      final colors = colorCodes
          .map((code) => palette.byCode[code])
          .whereType<BeadColor>()
          .toList();
      if (colors.length != colorCodes.length) return null;
      final packed = base64Decode(json['cells'] as String);
      final byteData = ByteData.sublistView(packed);
      final cells = <int>[
        for (var offset = 0; offset < packed.length; offset += 2)
          byteData.getUint16(offset, Endian.little) == 0xFFFF
              ? -1
              : byteData.getUint16(offset, Endian.little),
      ];
      return BeadPattern(
        id: id,
        title: json['title'] as String,
        width: json['width'] as int,
        height: json['height'] as int,
        colors: colors,
        cells: cells,
        sourceBytes: await source.readAsBytes(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        requestedColorCount: json['requestedColorCount'] as int,
        portraitMode: json['portraitMode'] as bool,
        backgroundRemoved: json['backgroundRemoved'] as bool? ?? false,
        template: PatternTemplate.values.firstWhere(
          (value) => value.name == json['template'],
          orElse: () => PatternTemplate.none,
        ),
        referenceBytes: await reference.exists()
            ? await reference.readAsBytes()
            : null,
        sourceName: (json['sourceName'] as String?)?.trim().isEmpty ?? true
            ? null
            : json['sourceName'] as String,
        processingDurationMs: (json['processingDurationMs'] as int?) == 0
            ? null
            : json['processingDurationMs'] as int?,
        smoothing: json['smoothing'] as bool? ?? true,
        variantSeed: json['variantSeed'] as int? ?? 0,
        isCustomBoard: json['isCustomBoard'] as bool? ?? false,
        isPhotoProject: json['isPhotoProject'] as bool? ?? false,
        paletteId: palette.id,
      );
    } on Object {
      return null;
    }
  }

  Future<List<BeadPattern>> loadAll() async {
    final summaries = await loadSummaries();
    final result = <BeadPattern>[];
    for (final summary in summaries) {
      final pattern = await load(summary.id);
      if (pattern != null) result.add(pattern);
    }
    return result;
  }

  Future<int> backfillMissingThumbnails(
    Iterable<ProjectSummary> summaries,
  ) async {
    final directory = await _directory();
    var created = 0;
    for (final summary in summaries) {
      if (summary.thumbnailPath != null) continue;
      final pattern = await load(summary.id);
      if (pattern == null) continue;
      final thumbnail = pattern.isPhotoProject
          ? await compute(_renderPhotoThumbnail, pattern.sourceBytes)
          : await compute(_renderProjectThumbnail, {
              'width': pattern.width,
              'height': pattern.height,
              'cells': pattern.cells,
              'colors': [
                for (final color in pattern.colors)
                  [color.red, color.green, color.blue],
              ],
            });
      final file = File(
        '${directory.path}${Platform.pathSeparator}${pattern.id}.thumb.png',
      );
      await file.writeAsBytes(thumbnail, flush: true);
      created++;
    }
    return created;
  }

  Future<void> delete(String id) async {
    final directory = await _directory();
    for (final extension in _projectExtensions) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}$id.$extension',
      );
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> deleteMany(Iterable<String> ids) async {
    for (final id in ids) {
      await delete(id);
    }
  }

  Future<void> moveToTrash(String id, {String deletionSource = '我的作品'}) async {
    final directory = await _directory();
    final trash = await _trashDirectory();
    final projectFile = File(
      '${directory.path}${Platform.pathSeparator}$id.json',
    );
    if (!await projectFile.exists()) return;

    final summaryFile = File(
      '${directory.path}${Platform.pathSeparator}$id.summary.json',
    );
    Map<String, dynamic> summary;
    if (await summaryFile.exists()) {
      summary =
          jsonDecode(await summaryFile.readAsString()) as Map<String, dynamic>;
    } else {
      summary = await _readProjectHeader(projectFile);
      summary.remove('cells');
      summary.remove('colors');
      summary['colorCount'] =
          summary['colorCount'] as int? ??
          ((await _readProjectHeader(projectFile))['colors'] as List).length;
      summary['isFavorite'] = false;
    }
    summary['deletedAt'] = DateTime.now().toIso8601String();
    summary['deletedFrom'] = deletionSource;
    await _replaceJsonFile(summaryFile, summary);

    for (final extension in _projectExtensions) {
      final source = File(
        '${directory.path}${Platform.pathSeparator}$id.$extension',
      );
      if (!await source.exists()) continue;
      final destination = File(
        '${trash.path}${Platform.pathSeparator}$id.$extension',
      );
      if (await destination.exists()) await destination.delete();
      await source.rename(destination.path);
    }
  }

  Future<void> moveManyToTrash(
    Iterable<String> ids, {
    String deletionSource = '我的作品',
  }) async {
    for (final id in ids) {
      await moveToTrash(id, deletionSource: deletionSource);
    }
  }

  /// Keeps a recoverable copy of the current project before an overwrite.
  /// The live project remains in place, while the snapshot receives its own
  /// id so it can coexist with the replacement in the recycle bin.
  Future<String?> snapshotToTrash(
    String id, {
    required String deletionSource,
  }) async {
    final directory = await _directory();
    final trash = await _trashDirectory();
    final projectFile = File(
      '${directory.path}${Platform.pathSeparator}$id.json',
    );
    if (!await projectFile.exists()) return null;
    final snapshotId =
        '${id}_snapshot_${DateTime.now().microsecondsSinceEpoch}';
    final deletedAt = DateTime.now().toIso8601String();

    final projectJson =
        jsonDecode(await projectFile.readAsString()) as Map<String, dynamic>;
    projectJson['id'] = snapshotId;
    await _replaceJsonFile(
      File('${trash.path}${Platform.pathSeparator}$snapshotId.json'),
      projectJson,
    );

    final summaryFile = File(
      '${directory.path}${Platform.pathSeparator}$id.summary.json',
    );
    final summaryJson = summaryFile.existsSync()
        ? jsonDecode(await summaryFile.readAsString()) as Map<String, dynamic>
        : Map<String, dynamic>.from(projectJson);
    summaryJson
      ..['id'] = snapshotId
      ..['deletedAt'] = deletedAt
      ..['deletedFrom'] = deletionSource
      ..['colorCount'] =
          summaryJson['colorCount'] ?? (projectJson['colors'] as List).length
      ..['isFavorite'] = summaryJson['isFavorite'] as bool? ?? false
      ..remove('cells')
      ..remove('colors');
    await _replaceJsonFile(
      File('${trash.path}${Platform.pathSeparator}$snapshotId.summary.json'),
      summaryJson,
    );

    for (final extension in const ['source', 'reference', 'thumb.png']) {
      final source = File(
        '${directory.path}${Platform.pathSeparator}$id.$extension',
      );
      if (!await source.exists()) continue;
      final target = File(
        '${trash.path}${Platform.pathSeparator}$snapshotId.$extension',
      );
      await source.copy(target.path);
    }
    return snapshotId;
  }

  Future<List<ProjectSummary>> loadTrashSummaries() async {
    await purgeExpiredTrash();
    return _loadTrashSummariesWithoutPurge();
  }

  Future<List<ProjectSummary>> _loadTrashSummariesWithoutPurge() async {
    final directory = await _trashDirectory();
    final result = <ProjectSummary>[];
    final loadedIds = <String>{};
    final files = await directory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    for (final file in files.where(
      (file) => file.path.endsWith('.summary.json'),
    )) {
      try {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final summary = await _summaryFromJson(directory, json);
        result.add(summary);
        loadedIds.add(summary.id);
      } on Object {
        // Ignore a damaged recycled project and keep the rest available.
      }
    }
    for (final file in files.where(
      (file) =>
          file.path.endsWith('.json') && !file.path.endsWith('.summary.json'),
    )) {
      try {
        final json = await _readProjectHeader(file);
        final id = json['id'] as String;
        if (loadedIds.contains(id)) continue;
        result.add(await _summaryFromJson(directory, json));
      } on Object {
        // Ignore a damaged recycled project and keep the rest available.
      }
    }
    result.sort(
      (a, b) =>
          (b.deletedAt ?? b.createdAt).compareTo(a.deletedAt ?? a.createdAt),
    );
    return result;
  }

  Future<void> restoreFromTrash(String id) async {
    final directory = await _directory();
    final trash = await _trashDirectory();
    final activeProject = File(
      '${directory.path}${Platform.pathSeparator}$id.json',
    );
    if (await activeProject.exists()) {
      throw StateError('作品列表中已存在同一个作品，无法恢复');
    }
    final trashProject = File('${trash.path}${Platform.pathSeparator}$id.json');
    if (!await trashProject.exists()) return;
    final trashSummary = File(
      '${trash.path}${Platform.pathSeparator}$id.summary.json',
    );
    if (await trashSummary.exists()) {
      final summary =
          jsonDecode(await trashSummary.readAsString()) as Map<String, dynamic>;
      summary.remove('deletedAt');
      await _replaceJsonFile(trashSummary, summary);
    }
    for (final extension in _projectExtensions) {
      final source = File(
        '${trash.path}${Platform.pathSeparator}$id.$extension',
      );
      if (!await source.exists()) continue;
      final destination = File(
        '${directory.path}${Platform.pathSeparator}$id.$extension',
      );
      await source.rename(destination.path);
    }
  }

  Future<void> deletePermanently(String id) async {
    final trash = await _trashDirectory();
    for (final extension in _projectExtensions) {
      final file = File('${trash.path}${Platform.pathSeparator}$id.$extension');
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> emptyTrash() async {
    final summaries = await _loadTrashSummariesWithoutPurge();
    for (final summary in summaries) {
      await deletePermanently(summary.id);
    }
  }

  Future<int> getTrashRetentionDays() async {
    final file = await _settingsFile();
    if (!await file.exists()) return defaultTrashRetentionDays;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return (json['retentionDays'] as int? ?? defaultTrashRetentionDays).clamp(
        1,
        maxTrashRetentionDays,
      );
    } on Object {
      return defaultTrashRetentionDays;
    }
  }

  Future<void> setTrashRetentionDays(int days) async {
    if (days < 1 || days > maxTrashRetentionDays) {
      throw RangeError.range(days, 1, maxTrashRetentionDays, 'days');
    }
    final file = await _settingsFile();
    await _replaceJsonFile(file, {'retentionDays': days});
    await purgeExpiredTrash();
  }

  Future<int> purgeExpiredTrash() async {
    final days = await getTrashRetentionDays();
    final deadline = DateTime.now().subtract(Duration(days: days));
    final summaries = await _loadTrashSummariesWithoutPurge();
    var deleted = 0;
    for (final summary in summaries) {
      final deletedAt = summary.deletedAt;
      if (deletedAt != null && deletedAt.isBefore(deadline)) {
        await deletePermanently(summary.id);
        deleted++;
      }
    }
    return deleted;
  }

  Future<void> rename(String id, String title) async {
    final nextTitle = title.trim();
    if (nextTitle.isEmpty) throw ArgumentError('作品名称不能为空');
    final directory = await _directory();
    final projectFile = File(
      '${directory.path}${Platform.pathSeparator}$id.json',
    );
    if (!await projectFile.exists()) throw StateError('作品不存在');

    final projectJson =
        jsonDecode(await projectFile.readAsString()) as Map<String, dynamic>;
    projectJson['title'] = nextTitle;
    await _replaceJsonFile(projectFile, projectJson);

    final summaryFile = File(
      '${directory.path}${Platform.pathSeparator}$id.summary.json',
    );
    Map<String, dynamic> summaryJson;
    if (await summaryFile.exists()) {
      summaryJson =
          jsonDecode(await summaryFile.readAsString()) as Map<String, dynamic>;
    } else {
      summaryJson = Map<String, dynamic>.from(projectJson);
    }
    summaryJson['title'] = nextTitle;
    summaryJson['colorCount'] =
        summaryJson['colorCount'] ?? (projectJson['colors'] as List).length;
    summaryJson['isFavorite'] = summaryJson['isFavorite'] as bool? ?? false;
    summaryJson.remove('cells');
    summaryJson.remove('colors');
    summaryJson.remove('requestedColorCount');
    summaryJson.remove('portraitMode');
    await _replaceJsonFile(summaryFile, summaryJson);
  }

  Future<void> reorderProjects(List<String> orderedIds) async {
    final existing = (await loadSummaries()).map((value) => value.id).toSet();
    final normalized = <String>[
      for (final id in orderedIds)
        if (existing.contains(id)) id,
      for (final id in existing)
        if (!orderedIds.contains(id)) id,
    ];
    final file = await _projectOrderFile();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(normalized), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<ProjectSummary> _summaryFromJson(
    Directory directory,
    Map<String, dynamic> json,
  ) async {
    final id = json['id'] as String;
    final thumbnail = File(
      '${directory.path}${Platform.pathSeparator}$id.thumb.png',
    );
    return ProjectSummary(
      id: id,
      title: json['title'] as String,
      width: json['width'] as int,
      height: json['height'] as int,
      colorCount: json['colorCount'] as int? ?? (json['colors'] as List).length,
      createdAt: DateTime.parse(json['createdAt'] as String),
      thumbnailPath: await thumbnail.exists() ? thumbnail.path : null,
      isFavorite: json['isFavorite'] as bool? ?? false,
      beadCount: json['beadCount'] as int?,
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.tryParse(json['deletedAt'] as String),
      favoriteCategory: json['favoriteCategory'] as String?,
      sourceName: json['sourceName'] as String?,
      deletedFrom: json['deletedFrom'] as String?,
      isCustomBoard: json['isCustomBoard'] as bool? ?? false,
      isPhotoProject: json['isPhotoProject'] as bool? ?? false,
    );
  }

  Future<void> setFavorite(
    String id,
    bool isFavorite, {
    String? category,
  }) async {
    final directory = await _directory();
    final sidecar = File(
      '${directory.path}${Platform.pathSeparator}$id.summary.json',
    );
    Map<String, dynamic> json;
    if (await sidecar.exists()) {
      json = jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
    } else {
      final project = File(
        '${directory.path}${Platform.pathSeparator}$id.json',
      );
      if (!await project.exists()) return;
      json = await _readProjectHeader(project);
    }
    json['schema'] = 2;
    json['colorCount'] =
        json['colorCount'] as int? ?? (json['colors'] as List).length;
    json['isFavorite'] = isFavorite;
    if (isFavorite) {
      json['favoriteCategory'] =
          (category ?? json['favoriteCategory'] as String? ?? '未分类').trim();
    } else {
      json.remove('favoriteCategory');
    }
    for (final key in const [
      'cells',
      'colors',
      'requestedColorCount',
      'portraitMode',
      'backgroundRemoved',
      'template',
      'processingDurationMs',
      'smoothing',
      'variantSeed',
      'paletteId',
    ]) {
      json.remove(key);
    }
    await _writeSummaryFile(sidecar, json.cast<String, Object>());
  }

  Future<void> assignFavoriteCategory(String id, String category) async {
    final value = category.trim();
    if (value.isEmpty) throw ArgumentError('分类名称不能为空');
    await setFavorite(id, true, category: value);
    final categories = await loadFavoriteCategories();
    if (!categories.contains(value)) {
      categories.add(value);
      await saveFavoriteCategories(categories);
    }
  }

  Future<List<String>> loadFavoriteCategories() async {
    final file = await _favoriteCategoriesFile();
    final categories = <String>{'未分类', ...defaultFavoriteCategories};
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString()) as List;
        categories.addAll(
          json
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty),
        );
      } on Object {
        // Rebuild the list from project summaries below.
      }
    }
    for (final summary in await loadSummaries()) {
      final category = summary.favoriteCategory;
      if (summary.isFavorite &&
          category != null &&
          category.trim().isNotEmpty) {
        categories.add(category.trim());
      }
    }
    final result = categories.toList()..sort();
    result.remove('未分类');
    return ['未分类', ...result];
  }

  Future<void> saveFavoriteCategories(Iterable<String> values) async {
    final categories = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    categories.add('未分类');
    categories.addAll(defaultFavoriteCategories);
    final file = await _favoriteCategoriesFile();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(categories.toList()..sort()),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<void> renameFavoriteCategory(String oldName, String newName) async {
    final next = newName.trim();
    if (next.isEmpty || oldName == '未分类') return;
    final summaries = await loadSummaries();
    for (final summary in summaries.where(
      (item) => item.favoriteCategory == oldName,
    )) {
      await assignFavoriteCategory(summary.id, next);
    }
    final categories = await loadFavoriteCategories();
    categories.remove(oldName);
    categories.add(next);
    await saveFavoriteCategories(categories);
  }

  Future<void> deleteFavoriteCategory(String name) async {
    if (name == '未分类') return;
    final summaries = await loadSummaries();
    for (final summary in summaries.where(
      (item) => item.favoriteCategory == name,
    )) {
      await assignFavoriteCategory(summary.id, '未分类');
    }
    final categories = await loadFavoriteCategories()
      ..remove(name);
    await saveFavoriteCategories(categories);
  }

  Future<bool> isFavorite(String id) async {
    final directory = await _directory();
    final sidecar = File(
      '${directory.path}${Platform.pathSeparator}$id.summary.json',
    );
    if (!await sidecar.exists()) return false;
    try {
      final json =
          jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
      return json['isFavorite'] as bool? ?? false;
    } on Object {
      return false;
    }
  }

  Future<Map<String, dynamic>> _readProjectHeader(File file) async {
    final handle = await file.open();
    try {
      final bytes = await handle.read(32768);
      final text = utf8.decode(bytes, allowMalformed: true);
      final marker = text.lastIndexOf('"cells":');
      if (marker < 0) {
        return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
      return jsonDecode('${text.substring(0, marker)}"cells":""}')
          as Map<String, dynamic>;
    } finally {
      await handle.close();
    }
  }

  Future<void> _writeSummaryFile(File file, Map<String, Object> payload) async {
    await _replaceJsonFile(file, payload);
  }

  Future<void> _replaceJsonFile(File file, Map<String, dynamic> payload) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(payload), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}

Uint8List _renderProjectThumbnail(Map<String, Object> payload) {
  final width = payload['width']! as int;
  final height = payload['height']! as int;
  final cells = (payload['cells']! as List).cast<int>();
  final colors = (payload['colors']! as List)
      .map((value) => (value as List).cast<int>())
      .toList();
  const outputSize = 320;
  final output = img.Image(
    width: outputSize,
    height: outputSize,
    numChannels: 3,
  );
  img.fill(output, color: img.ColorRgb8(247, 241, 235));
  for (var y = 0; y < outputSize; y++) {
    final sourceY = (y * height ~/ outputSize).clamp(0, height - 1);
    for (var x = 0; x < outputSize; x++) {
      final sourceX = (x * width ~/ outputSize).clamp(0, width - 1);
      final colorIndex = cells[sourceY * width + sourceX];
      if (colorIndex < 0) continue;
      final rgb = colors[colorIndex];
      output.setPixelRgb(x, y, rgb[0], rgb[1], rgb[2]);
    }
  }
  return Uint8List.fromList(img.encodePng(output, level: 6));
}

Uint8List _renderPhotoThumbnail(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('无法读取照片缩略图');
  final oriented = img.bakeOrientation(decoded);
  const maxSide = 480;
  final scale = math.min(
    1.0,
    maxSide / math.max(oriented.width, oriented.height),
  );
  final thumbnail = scale < 1
      ? img.copyResize(
          oriented,
          width: math.max(1, (oriented.width * scale).round()),
          height: math.max(1, (oriented.height * scale).round()),
          interpolation: img.Interpolation.average,
        )
      : oriented;
  return Uint8List.fromList(img.encodePng(thumbnail, level: 6));
}
