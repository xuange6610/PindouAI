import 'dart:convert';
import 'dart:io';

import 'package:bead_ai_designer/data/mard_palette.dart';
import 'package:bead_ai_designer/models/bead_pattern.dart';
import 'package:bead_ai_designer/services/project_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('大量作品只读取轻量索引并支持批量删除', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/project_repository_${DateTime.now().microsecondsSinceEpoch}',
    );
    final patterns = Directory(
      '${documents.path}${Platform.pathSeparator}patterns',
    );
    await patterns.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => documents.absolute.path,
        );

    for (var index = 0; index < 250; index++) {
      final id = 'work_$index';
      await File(
        '${patterns.path}${Platform.pathSeparator}$id.summary.json',
      ).writeAsString(
        jsonEncode({
          'schema': 1,
          'id': id,
          'title': '作品 $index',
          'width': 200,
          'height': 200,
          'colorCount': 48,
          'createdAt': DateTime(2026, 7, 29, 0, index).toIso8601String(),
        }),
      );
    }

    final repository = ProjectRepository();
    final summaries = await repository.loadSummaries();
    expect(summaries, hasLength(250));
    expect(summaries.first.title, '作品 249');

    await repository.setFavorite(summaries.first.id, true);
    final favorited = await repository.loadSummaries();
    expect(favorited.first.isFavorite, isTrue);
    expect(await repository.isFavorite(favorited.first.id), isTrue);
    await repository.setFavorite(favorited.first.id, false);
    expect(await repository.isFavorite(favorited.first.id), isFalse);

    await repository.reorderProjects(['work_12', 'work_3', 'work_201']);
    final reordered = await repository.loadSummaries();
    expect(reordered.take(3).map((item) => item.id), [
      'work_12',
      'work_3',
      'work_201',
    ]);

    final deleting = summaries.take(50).map((summary) => summary.id).toList();
    await repository.deleteMany(deleting);
    expect(await repository.loadSummaries(), hasLength(200));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await documents.delete(recursive: true);
  });

  test('作品重命名会同步完整工程和列表索引并保留收藏', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/project_rename_${DateTime.now().microsecondsSinceEpoch}',
    );
    await documents.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => documents.absolute.path,
        );
    final source = img.Image(width: 2, height: 2);
    img.fill(source, color: img.ColorRgb8(200, 80, 90));
    final pattern = BeadPattern(
      id: 'rename-test',
      title: '旧名称',
      width: 2,
      height: 2,
      colors: [MardPalette.byCode['A8']!],
      cells: const [-1, 0, 0, -1],
      sourceBytes: Uint8List.fromList(img.encodePng(source)),
      referenceBytes: Uint8List.fromList(img.encodePng(source)),
      createdAt: DateTime(2026),
      requestedColorCount: 1,
      portraitMode: false,
      backgroundRemoved: true,
    );
    final repository = ProjectRepository();
    await repository.save(pattern);
    await repository.setFavorite(pattern.id, true);
    await repository.rename(pattern.id, '新的作品名称');

    final loaded = await repository.load(pattern.id);
    expect(loaded?.title, '新的作品名称');
    expect(loaded?.cells, [-1, 0, 0, -1]);
    expect(loaded?.referenceBytes, isNotNull);
    expect(loaded?.backgroundRemoved, isTrue);
    final summary = (await repository.loadSummaries()).single;
    expect(summary.title, '新的作品名称');
    expect(summary.isFavorite, isTrue);
    expect(summary.totalBeads, 2);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await documents.delete(recursive: true);
  });

  test('回收站支持恢复、保留天数和到期自动清理', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/project_trash_${DateTime.now().microsecondsSinceEpoch}',
    );
    await documents.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => documents.absolute.path,
        );
    final source = img.Image(width: 2, height: 2);
    img.fill(source, color: img.ColorRgb8(70, 150, 210));
    final pattern = BeadPattern(
      id: 'trash-test',
      title: '可恢复作品',
      width: 2,
      height: 2,
      colors: [MardPalette.byCode['A8']!],
      cells: const [0, 0, 0, 0],
      sourceBytes: Uint8List.fromList(img.encodePng(source)),
      createdAt: DateTime(2026),
      requestedColorCount: 1,
      portraitMode: false,
      template: PatternTemplate.classic,
    );
    final repository = ProjectRepository();
    await repository.save(pattern);
    await repository.setFavorite(pattern.id, true);
    await repository.moveToTrash(pattern.id);

    expect(await repository.loadSummaries(), isEmpty);
    final recycled = (await repository.loadTrashSummaries()).single;
    expect(recycled.deletedAt, isNotNull);
    expect(recycled.deletedFrom, '我的作品');
    expect(recycled.isFavorite, isTrue);
    expect(
      await repository.getTrashRetentionDays(),
      ProjectRepository.defaultTrashRetentionDays,
    );

    await repository.setTrashRetentionDays(3650);
    await repository.restoreFromTrash(pattern.id);
    final restored = await repository.load(pattern.id);
    expect(restored?.template, PatternTemplate.classic);
    expect((await repository.loadSummaries()).single.isFavorite, isTrue);

    await repository.moveToTrash(pattern.id);
    final trashSummary = File(
      '${documents.path}${Platform.pathSeparator}patterns_trash'
      '${Platform.pathSeparator}${pattern.id}.summary.json',
    );
    final json =
        jsonDecode(await trashSummary.readAsString()) as Map<String, dynamic>;
    json['deletedAt'] = DateTime.now()
        .subtract(const Duration(days: 2))
        .toIso8601String();
    await trashSummary.writeAsString(jsonEncode(json));
    await repository.setTrashRetentionDays(1);
    expect(await repository.loadTrashSummaries(), isEmpty);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await documents.delete(recursive: true);
  });

  test('覆盖前快照以独立作品进入回收站并记录来源', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/project_snapshot_${DateTime.now().microsecondsSinceEpoch}',
    );
    await documents.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => documents.absolute.path,
        );
    final source = img.Image(width: 3, height: 3);
    img.fill(source, color: img.ColorRgb8(90, 130, 210));
    final repository = ProjectRepository();
    final original = BeadPattern(
      id: 'overwrite-test',
      title: '覆盖前作品',
      width: 3,
      height: 3,
      colors: [MardPalette.byCode['A8']!],
      cells: List<int>.filled(9, 0),
      sourceBytes: Uint8List.fromList(img.encodePng(source)),
      createdAt: DateTime(2026),
      requestedColorCount: 1,
      portraitMode: false,
      isCustomBoard: true,
    );
    await repository.save(original);
    final snapshotId = await repository.snapshotToTrash(
      original.id,
      deletionSource: '不同方案覆盖',
    );
    expect(snapshotId, isNotNull);
    expect(await repository.load(original.id), isNotNull);
    final recycled = (await repository.loadTrashSummaries()).single;
    expect(recycled.id, snapshotId);
    expect(recycled.deletedFrom, '不同方案覆盖');
    expect(recycled.isCustomBoard, isTrue);

    final categories = await repository.loadFavoriteCategories();
    expect(
      categories,
      containsAll(ProjectRepository.defaultFavoriteCategories),
    );
    await repository.saveFavoriteCategories([...categories, '旅行照片']);
    expect(await repository.loadFavoriteCategories(), contains('旅行照片'));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await documents.delete(recursive: true);
  });

  test('AI 图片按原始照片字节保存并可直接收藏', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/photo_project_${DateTime.now().microsecondsSinceEpoch}',
    );
    await documents.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    final image = img.Image(width: 18, height: 11);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x * 10, y * 18, 120);
      }
    }
    final original = Uint8List.fromList(img.encodePng(image));
    final repository = ProjectRepository();
    final saved = await repository.savePhotoProject(
      original,
      title: '聊天生成原图',
      sourceName: 'AI聊天/generated.png',
    );

    expect(saved.isPhotoProject, isTrue);
    final loaded = await repository.load(saved.id);
    expect(loaded?.isPhotoProject, isTrue);
    expect(loaded?.sourceBytes, orderedEquals(original));
    final summary = (await repository.loadSummaries()).single;
    expect(summary.isPhotoProject, isTrue);
    expect(summary.sourceName, 'AI聊天/generated.png');
    expect(summary.thumbnailPath, isNotNull);
    expect(
      img.decodeImage(await File(summary.thumbnailPath!).readAsBytes()),
      isNotNull,
    );

    await repository.setFavorite(saved.id, true);
    expect((await repository.loadSummaries()).single.isFavorite, isTrue);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await documents.delete(recursive: true);
  });
}
