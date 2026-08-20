import 'dart:typed_data';

import 'package:bead_ai_designer/services/ai_background_image_workflow.dart';
import 'package:bead_ai_designer/services/ai_design_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI 拼豆图先通过对话识图，再使用纯文本图片生成', () async {
    final reference = Uint8List.fromList([1, 2, 3, 4]);
    Uint8List? generatedReference;
    String? generatedPrompt;
    String? analyzedModel;
    final phases = <String>[];
    final workflow = AiBackgroundImageWorkflow(
      referenceAnalyzer:
          ({required prompt, required imageBytes, required model}) async {
            expect(imageBytes, same(reference));
            analyzedModel = model;
            return const AiDesignResult(
              model: 'vision-model',
              content: '红色小熊，正面构图，白色背景',
            );
          },
      imageGenerator:
          ({required prompt, required imageBytes, required model}) async {
            generatedReference = imageBytes;
            generatedPrompt = prompt;
            return AiImageResult(
              model: model,
              bytes: Uint8List.fromList([137, 80, 78, 71]),
            );
          },
    );

    final result = await workflow.generateBeadDesign(
      prompt: '生成清晰拼豆图',
      referenceImage: reference,
      imageModel: 'image-model',
      visionModel: 'chat-model',
      onProgress: (_, phase) => phases.add(phase),
    );

    expect(analyzedModel, 'chat-model');
    expect(generatedReference, isNull, reason: '最终生图必须避开不兼容的图片编辑端点');
    expect(generatedPrompt, contains('红色小熊'));
    expect(result.model, 'image-model');
    expect(phases, contains('后台调用 AI 对话模型识别参考图'));
    expect(phases, contains('参考图识别完成，后台调用图片模型生成'));
  });

  test('对话识图失败时仍尝试支持参考图的兼容图片接口', () async {
    final reference = Uint8List.fromList([9, 8, 7]);
    var directAttempts = 0;
    final workflow = AiBackgroundImageWorkflow(
      referenceAnalyzer:
          ({required prompt, required imageBytes, required model}) async {
            throw StateError('vision unavailable');
          },
      imageGenerator:
          ({required prompt, required imageBytes, required model}) async {
            directAttempts++;
            expect(imageBytes, same(reference));
            return AiImageResult(model: model, bytes: Uint8List.fromList([1]));
          },
    );

    final result = await workflow.generateBeadDesign(
      prompt: 'beads',
      referenceImage: reference,
      imageModel: 'image-model',
      visionModel: 'chat-model',
    );

    expect(directAttempts, 1);
    expect(result.bytes, [1]);
  });

  test('AI 抠图会真实请求图片模型，并在失败后使用原图本地降级', () async {
    final source = Uint8List.fromList([4, 5, 6]);
    Uint8List? localInput;
    var aiAttempts = 0;
    final workflow = AiBackgroundImageWorkflow(
      imageGenerator:
          ({required prompt, required imageBytes, required model}) async {
            aiAttempts++;
            expect(imageBytes, same(source));
            throw StateError('images edits unsupported');
          },
      localCutout: (bytes) async {
        localInput = bytes;
        return Uint8List.fromList([7, 8, 9]);
      },
    );

    final result = await workflow.cutout(
      sourceImage: source,
      imageModel: 'image-model',
    );

    expect(aiAttempts, 1);
    expect(localInput, same(source));
    expect(result.usedAi, isFalse);
    expect(result.warning, contains('images edits unsupported'));
    expect(result.bytes, [7, 8, 9]);
  });

  test('AI 抠图成功后仍清理透明边缘', () async {
    final generated = Uint8List.fromList([10, 11]);
    Uint8List? localInput;
    final workflow = AiBackgroundImageWorkflow(
      imageGenerator:
          ({required prompt, required imageBytes, required model}) async =>
              AiImageResult(model: model, bytes: generated),
      localCutout: (bytes) async {
        localInput = bytes;
        return Uint8List.fromList([12]);
      },
    );

    final result = await workflow.cutout(
      sourceImage: Uint8List.fromList([1]),
      imageModel: 'image-model',
    );

    expect(localInput, same(generated));
    expect(result.usedAi, isTrue);
    expect(result.model, 'image-model');
    expect(result.bytes, [12]);
  });
}
