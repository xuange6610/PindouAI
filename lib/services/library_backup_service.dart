import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/bead_palettes.dart';
import '../models/bead_color.dart';
import '../models/bead_palette.dart';
import '../models/bead_pattern.dart';
import 'project_repository.dart';

class LibraryImportResult {
  const LibraryImportResult({required this.imported, required this.skipped});

  final int imported;
  final int skipped;
}

class LibraryBackupService {
  LibraryBackupService({ProjectRepository? repository})
    : _repository = repository ?? ProjectRepository();

  static const _mediaChannel = MethodChannel(
    'com.xuan.bead_ai_designer/media',
  );
  final ProjectRepository _repository;

  Future<File> createBackup() async {
    final summaries = await _repository.loadSummaries();
    final projects = <Map<String, Object?>>[];
    for (final summary in summaries) {
      final pattern = await _repository.load(summary.id);
      if (pattern == null) continue;
      projects.add({
        'id': pattern.id,
        'title': pattern.title,
        'width': pattern.width,
        'height': pattern.height,
        'colors': pattern.colors.map((color) => color.code).toList(),
        'cells': pattern.cells,
        'source': base64Encode(pattern.sourceBytes),
        if (pattern.referenceBytes != null)
          'reference': base64Encode(pattern.referenceBytes!),
        'createdAt': pattern.createdAt.toIso8601String(),
        'requestedColorCount': pattern.requestedColorCount,
        'portraitMode': pattern.portraitMode,
        'backgroundRemoved': pattern.backgroundRemoved,
        'template': pattern.template.name,
        'sourceName': pattern.sourceName,
        'processingDurationMs': pattern.processingDurationMs,
        'smoothing': pattern.smoothing,
        'variantSeed': pattern.variantSeed,
        'paletteId': pattern.paletteId.storageId,
        'isCustomBoard': pattern.isCustomBoard,
        'isFavorite': summary.isFavorite,
        'favoriteCategory': summary.favoriteCategory,
      });
    }
    final payload = utf8.encode(
      jsonEncode({
        'format': 'bead-ai-library',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'projects': projects,
      }),
    );
    final compressed = GZipCodec(level: 6).encode(payload);
    final directory = await getTemporaryDirectory();
    final now = DateTime.now();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final file = File(
      '${directory.path}${Platform.pathSeparator}拼豆AI_全部作品_$stamp.beadbackup',
    );
    return file.writeAsBytes(compressed, flush: true);
  }

  Future<void> shareBackup() async {
    final file = await createBackup();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/octet-stream')],
        text: '拼豆 AI 全部作品备份，可在另一台设备的“我的作品”中导入。',
      ),
    );
  }

  Future<LibraryImportResult?> pickAndImport() async {
    if (Platform.isAndroid) {
      final bytes = await _mediaChannel.invokeMethod<Uint8List>('pickBackup');
      if (bytes == null) return null;
      return importBytes(bytes);
    }
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: '拼豆 AI 作品备份', extensions: ['beadbackup']),
      ],
    );
    if (file == null) return null;
    return importBytes(await file.readAsBytes());
  }

  Future<LibraryImportResult> importBytes(Uint8List bytes) async {
    final decoded =
        jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    if (decoded['format'] != 'bead-ai-library' || decoded['version'] != 1) {
      throw const FormatException('不是受支持的拼豆 AI 作品备份');
    }
    final existingIds = (await _repository.loadSummaries())
        .map((item) => item.id)
        .toSet();
    var imported = 0;
    var skipped = 0;
    for (final raw in (decoded['projects'] as List? ?? const [])) {
      try {
        final json = (raw as Map).cast<String, dynamic>();
        final colorCodes = (json['colors'] as List).cast<String>();
        final palette = BeadPalettes.forStoredProject(
          json['paletteId'] as String?,
          colorCodes,
        );
        final colors = colorCodes
            .map((code) => palette.byCode[code])
            .whereType<BeadColor>()
            .toList();
        final cells = (json['cells'] as List).cast<int>();
        final width = json['width'] as int;
        final height = json['height'] as int;
        if (colors.length != colorCodes.length ||
            cells.length != width * height) {
          throw const FormatException('作品颜色或格子数据不完整');
        }
        var id =
            json['id'] as String? ??
            DateTime.now().microsecondsSinceEpoch.toString();
        while (existingIds.contains(id)) {
          id = '${DateTime.now().microsecondsSinceEpoch}_$imported';
        }
        existingIds.add(id);
        final pattern = BeadPattern(
          id: id,
          title: json['title'] as String? ?? '导入的作品',
          width: width,
          height: height,
          colors: colors,
          cells: cells,
          sourceBytes: base64Decode(json['source'] as String),
          referenceBytes: json['reference'] == null
              ? null
              : base64Decode(json['reference'] as String),
          createdAt:
              DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now(),
          requestedColorCount:
              json['requestedColorCount'] as int? ?? colors.length,
          portraitMode: json['portraitMode'] as bool? ?? false,
          backgroundRemoved: json['backgroundRemoved'] as bool? ?? false,
          template: PatternTemplate.values.firstWhere(
            (value) => value.name == json['template'],
            orElse: () => PatternTemplate.none,
          ),
          sourceName: json['sourceName'] as String?,
          processingDurationMs: json['processingDurationMs'] as int?,
          smoothing: json['smoothing'] as bool? ?? true,
          variantSeed: json['variantSeed'] as int? ?? 0,
          isCustomBoard: json['isCustomBoard'] as bool? ?? false,
          paletteId: palette.id,
        );
        await _repository.save(pattern);
        if (json['isFavorite'] as bool? ?? false) {
          await _repository.setFavorite(
            id,
            true,
            category: json['favoriteCategory'] as String? ?? '未分类',
          );
        }
        imported++;
      } on Object {
        skipped++;
      }
    }
    return LibraryImportResult(imported: imported, skipped: skipped);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
