import 'dart:io';

import 'package:bead_ai_designer/data/mard_palette.dart';
import 'package:bead_ai_designer/models/bead_pattern.dart';
import 'package:bead_ai_designer/services/library_backup_service.dart';
import 'package:bead_ai_designer/services/project_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('全部作品备份可完整恢复收藏分类与生成参数', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/library_backup_${DateTime.now().microsecondsSinceEpoch}',
    );
    await documents.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => documents.absolute.path,
        );

    final source = img.Image(width: 3, height: 2);
    img.fill(source, color: img.ColorRgb8(80, 140, 210));
    final pattern = BeadPattern(
      id: 'backup-test',
      title: '需要迁移的作品',
      width: 3,
      height: 2,
      colors: [MardPalette.byCode['A8']!, MardPalette.byCode['H23']!],
      cells: const [0, 1, -1, 1, 0, 0],
      sourceBytes: Uint8List.fromList(img.encodePng(source)),
      createdAt: DateTime(2026, 7, 30, 12, 34, 56),
      requestedColorCount: 16,
      portraitMode: true,
      smoothing: false,
      sourceName: '风景照片.webp',
      processingDurationMs: 2345,
      variantSeed: 77,
      template: PatternTemplate.fresh,
    );
    final repository = ProjectRepository();
    await repository.save(pattern);
    await repository.setFavorite(pattern.id, true, category: '风景');

    final service = LibraryBackupService(repository: repository);
    final backup = await service.createBackup();
    expect(await backup.exists(), isTrue);
    await repository.delete(pattern.id);

    final result = await service.importBytes(await backup.readAsBytes());
    expect(result.imported, 1);
    expect(result.skipped, 0);
    final summary = (await repository.loadSummaries()).single;
    expect(summary.isFavorite, isTrue);
    expect(summary.favoriteCategory, '风景');
    final restored = await repository.load(summary.id);
    expect(restored?.sourceName, '风景照片.webp');
    expect(restored?.processingDurationMs, 2345);
    expect(restored?.variantSeed, 77);
    expect(restored?.smoothing, isFalse);
    expect(restored?.template, PatternTemplate.fresh);
    expect(restored?.cells, pattern.cells);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await documents.delete(recursive: true);
  });
}
