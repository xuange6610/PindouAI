import 'dart:io';

import 'package:bead_ai_designer/models/processing_task.dart';
import 'package:bead_ai_designer/models/bead_pattern.dart';
import 'package:bead_ai_designer/services/pattern_processor.dart';
import 'package:bead_ai_designer/services/ai_background_image_workflow.dart';
import 'package:bead_ai_designer/services/ai_design_service.dart';
import 'package:bead_ai_designer/services/processing_center.dart';
import 'package:bead_ai_designer/services/project_repository.dart';
import 'package:bead_ai_designer/services/app_notice_center.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('处理中心完成后作品立即出现在轻量作品列表', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/processing_center_${DateTime.now().microsecondsSinceEpoch}',
    );
    await documents.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => documents.absolute.path,
        );

    final source = img.Image(width: 16, height: 16);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x * 12, y * 12, 140);
      }
    }
    final originalSource = img.Image(width: 24, height: 12);
    img.fill(originalSource, color: img.ColorRgb8(30, 160, 210));
    final originalBytes = Uint8List.fromList(img.encodePng(originalSource));
    final center = ProcessingCenter.instance;
    await center.initialize();
    final task = await center.enqueue(
      imageBytes: Uint8List.fromList(img.encodePng(source)),
      originalImageBytes: originalBytes,
      sourceName: 'queue-test.png',
      options: const ProcessingOptions(
        size: 20,
        maxColors: 8,
        portraitMode: false,
        smoothing: true,
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (task.status != ProcessingTaskStatus.completed &&
        task.status != ProcessingTaskStatus.failed &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect(task.status, ProcessingTaskStatus.completed, reason: task.error);
    expect(task.progress, 1);
    for (
      var attempt = 0;
      attempt < 10 && AppNoticeCenter.instance.notice == null;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(AppNoticeCenter.instance.notice?.kind, AppNoticeKind.success);
    expect(
      AppNoticeCenter.instance.notice?.message,
      contains('queue-test.png'),
    );
    final sidecar = File(
      '${documents.path}${Platform.pathSeparator}patterns'
      '${Platform.pathSeparator}${task.resultId}.summary.json',
    );
    expect(await sidecar.exists(), isTrue);
    await sidecar.delete();

    final summaries = await ProjectRepository().loadSummaries();
    expect(summaries.map((summary) => summary.id), contains(task.resultId));
    expect(summaries.first.thumbnailPath, isNotNull);
    expect(await sidecar.exists(), isTrue, reason: '旧工程应自动生成轻量索引');
    final storedPattern = await ProjectRepository().load(task.resultId!);
    final storedSource = img.decodeImage(storedPattern!.sourceBytes);
    expect(storedSource?.width, 24, reason: '重新生成必须保留完整原图，而不是上次裁剪图');
    expect(storedSource?.height, 12);

    final replacement = await center.enqueue(
      imageBytes: Uint8List.fromList(img.encodePng(source)),
      originalImageBytes: originalBytes,
      comparisonImageBytes: Uint8List.fromList(
        img.encodePng(img.Image(width: 7, height: 5)),
      ),
      sourceName: 'queue-replace.png',
      replaceProjectId: task.resultId,
      options: const ProcessingOptions(
        size: 20,
        maxColors: 8,
        portraitMode: false,
        smoothing: true,
        template: PatternTemplate.fresh,
      ),
    );
    final replacementDeadline = DateTime.now().add(const Duration(seconds: 15));
    while (replacement.status != ProcessingTaskStatus.completed &&
        replacement.status != ProcessingTaskStatus.failed &&
        DateTime.now().isBefore(replacementDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(
      replacement.status,
      ProcessingTaskStatus.completed,
      reason: replacement.error,
    );
    expect(replacement.resultId, task.resultId);
    expect(await ProjectRepository().loadSummaries(), hasLength(1));
    expect(
      (await ProjectRepository().load(task.resultId!))?.template,
      PatternTemplate.fresh,
    );
    final comparison = img.decodeImage(
      (await ProjectRepository().load(task.resultId!))!.referenceBytes!,
    );
    expect(comparison?.width, 7, reason: '变化方案必须保留刷新前预览用于对比');
    expect(comparison?.height, 5);

    await center.deleteTask(task.id);
    await center.deleteTask(replacement.id);
    await ProjectRepository().delete(task.resultId!);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        await documents.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt == 9) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
  });

  test('后台处理启用 AI 抠图时会先调用图片模型再生成拼豆图', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/processing_cutout_${DateTime.now().microsecondsSinceEpoch}',
    );
    await documents.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => documents.absolute.path,
        );

    final source = img.Image(width: 18, height: 18);
    img.fill(source, color: img.ColorRgb8(210, 40, 80));
    final sourceBytes = Uint8List.fromList(img.encodePng(source));
    var aiCalls = 0;
    final phases = <String>[];
    final workflow = AiBackgroundImageWorkflow(
      imageGenerator:
          ({required prompt, required imageBytes, required model}) async {
            aiCalls++;
            expect(imageBytes, isNotNull);
            return AiImageResult(model: model, bytes: imageBytes!);
          },
      localCutout: (bytes) async => bytes,
    );
    final center = ProcessingCenter.forTesting(imageWorkflow: workflow);
    center.addListener(() {
      if (center.tasks.isNotEmpty) phases.add(center.tasks.first.phase);
    });
    await center.initialize();
    final task = await center.enqueue(
      imageBytes: sourceBytes,
      sourceName: 'ai-cutout.png',
      options: const ProcessingOptions(
        size: 20,
        maxColors: 8,
        portraitMode: false,
        smoothing: true,
        removeBackground: true,
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (task.status != ProcessingTaskStatus.completed &&
        task.status != ProcessingTaskStatus.failed &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect(task.status, ProcessingTaskStatus.completed, reason: task.error);
    expect(aiCalls, 1);
    expect(phases, contains('后台调用 AI 图片模型识别并抠出主体'));
    expect(phases, contains('AI 抠图完成，正在清理透明边缘'));
    final pattern = await ProjectRepository().load(task.resultId!);
    expect(pattern?.backgroundRemoved, isTrue);

    await center.deleteTask(task.id);
    await ProjectRepository().delete(task.resultId!);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        await documents.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt == 9) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
  });
}
