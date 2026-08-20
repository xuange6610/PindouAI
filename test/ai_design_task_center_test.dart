import 'dart:async';
import 'dart:io';

import 'package:bead_ai_designer/services/ai_design_service.dart';
import 'package:bead_ai_designer/services/ai_design_task_center.dart';
import 'package:bead_ai_designer/services/app_notice_center.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('后台生图任务可在失败后自动重试直到成功并保存记录', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/ai_task_center_${DateTime.now().microsecondsSinceEpoch}',
    );
    await documents.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
      if (await documents.exists()) await documents.delete(recursive: true);
    });

    var calls = 0;
    final completed = Completer<void>();
    final center = AiDesignTaskCenter(
      retryBaseDelay: const Duration(milliseconds: 5),
      generator:
          ({required prompt, required imageBytes, required model}) async {
            calls++;
            if (calls == 1) throw StateError('temporary failure');
            return AiImageResult(
              model: model,
              bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
            );
          },
    );
    center.addListener(() {
      if (center.tasks.firstOrNull?.status == AiDesignTaskStatus.succeeded &&
          !completed.isCompleted) {
        completed.complete();
      }
    });
    center.enqueue(
      styleId: 'refined',
      styleTitle: '精致像素风',
      displayPrompt: '测试',
      apiPrompt: '测试 prompt',
      sourceImage: Uint8List.fromList([1, 2, 3]),
      model: 'qwen-max',
      autoRetry: true,
      backgrounded: true,
    );

    await completed.future.timeout(const Duration(seconds: 2));
    final task = center.tasks.single;
    expect(task.attempts, 2);
    expect(task.historyEntry?.model, 'qwen-max');
    expect(task.historyEntry?.imagePath, isNotNull);
    expect(await File(task.historyEntry!.imagePath!).exists(), isTrue);
    expect(task.progress, 1);
    expect(task.phase, '生成记录已保存');
    expect(AppNoticeCenter.instance.notice?.kind, AppNoticeKind.success);
    expect(AppNoticeCenter.instance.notice?.message, contains('后台生成成功'));
    AppNoticeCenter.instance.dismiss();
    center.dispose();
  });

  test('后台生图最终失败时会发送全局错误提示并保留详细阶段', () async {
    final completed = Completer<void>();
    final center = AiDesignTaskCenter(
      generator:
          ({required prompt, required imageBytes, required model}) async {
            throw StateError('provider returned HTTP 503');
          },
    );
    center.addListener(() {
      if (center.tasks.firstOrNull?.status == AiDesignTaskStatus.failed &&
          !completed.isCompleted) {
        completed.complete();
      }
    });
    center.enqueue(
      styleId: 'pixel',
      styleTitle: '清晰像素风',
      displayPrompt: '失败通知测试',
      apiPrompt: 'full test prompt',
      sourceImage: Uint8List.fromList([1, 2, 3, 4]),
      model: 'gpt-5.6-sol',
      autoRetry: false,
      backgrounded: true,
    );

    await completed.future.timeout(const Duration(seconds: 2));
    final task = center.tasks.single;
    expect(task.phase, '生成失败，等待手动重试');
    expect(task.error, contains('503'));
    expect(task.sourceImageByteLength, 4);
    expect(AppNoticeCenter.instance.notice?.kind, AppNoticeKind.error);
    AppNoticeCenter.instance.dismiss();
    center.dispose();
  });

  test('图片色号识别和 AI 拼豆图纸共享串行调度但任务列表完全隔离', () async {
    final pending = Completer<AiImageResult>();
    final center = AiDesignTaskCenter(
      generator: ({required prompt, required imageBytes, required model}) =>
          pending.future,
    );
    final designId = center.enqueue(
      styleId: 'pixel',
      styleTitle: 'AI 拼豆图纸',
      displayPrompt: '图纸任务',
      apiPrompt: 'design',
      sourceImage: Uint8List.fromList([1]),
      model: 'image-model',
      autoRetry: false,
      backgrounded: true,
    );
    final recognitionId = center.enqueue(
      styleId: 'color_recognition',
      styleTitle: '图片色号识别',
      displayPrompt: '识别任务',
      apiPrompt: 'recognition',
      sourceImage: Uint8List.fromList([2]),
      model: 'image-model',
      autoRetry: false,
      backgrounded: true,
      scope: AiDesignTaskScope.colorRecognition,
    );

    expect(center.visibleTasks, hasLength(1));
    expect(center.visibleTasks.single.id, designId);
    expect(
      center.visibleTasksFor(AiDesignTaskScope.colorRecognition).single.id,
      recognitionId,
    );
    expect(center.activeBackgroundCount, 1);
    expect(
      center.activeBackgroundCountFor(AiDesignTaskScope.colorRecognition),
      1,
    );

    center.cancel(designId);
    center.cancel(recognitionId);
    pending.complete(
      AiImageResult(model: 'image-model', bytes: Uint8List.fromList([1])),
    );
    await Future<void>.delayed(Duration.zero);
    center.dispose();
  });
}
