import 'package:bead_ai_designer/services/ai_model_profile.dart';
import 'package:bead_ai_designer/services/ai_usage_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('各模型族会自动选择对应运行环境和接口顺序', () {
    expect(runtimeProfileForModel('gpt-5').provider, AiModelProvider.openAi);
    expect(runtimeProfileForModel('gpt-5').preferResponsesApi, isTrue);
    expect(
      runtimeProfileForModel('claude-sonnet-4').provider,
      AiModelProvider.anthropic,
    );
    expect(runtimeProfileForModel('qwen-max').provider, AiModelProvider.qwen);
    expect(runtimeProfileForModel('glm-5.2').provider, AiModelProvider.glm);
    expect(
      runtimeProfileForModel('kimi-k2-code').provider,
      AiModelProvider.kimi,
    );
    expect(
      runtimeProfileForModel('deepseek-r1').provider,
      AiModelProvider.deepSeek,
    );
    expect(
      runtimeProfileForModel('gemini-2.5-pro').provider,
      AiModelProvider.gemini,
    );
    expect(runtimeProfileForModel('llama-4').provider, AiModelProvider.llama);
    expect(
      runtimeProfileForModel('qwen-max').systemInstruction('qwen-max'),
      contains('不要自称为其他模型'),
    );
  });

  test('推荐会结合型号定位和本机速度失败率', () {
    final initial = recommendAiModel([
      'claude-haiku-4',
      'claude-sonnet-4',
      'claude-opus-4',
    ]);
    expect(initial?.model, 'claude-sonnet-4');

    final withFeedback = recommendAiModel(
      ['qwen-plus', 'qwen-max'],
      localUsage: const {
        'qwen-plus': AiModelUsageSummary(
          requests: 5,
          failures: 0,
          averageElapsedMs: 800,
        ),
        'qwen-max': AiModelUsageSummary(
          requests: 5,
          failures: 4,
          averageElapsedMs: 12000,
        ),
      },
    );
    expect(withFeedback?.model, 'qwen-plus');
    expect(withFeedback?.reason, contains('本机'));
  });

  test('GPT 5.6 Sol 不再写死，按 API 目录中的型号综合推荐', () {
    final recommendation = recommendAiModel([
      'gpt-6.0-sol',
      'gpt5.6sol',
      'qwen-max',
    ]);

    expect(recommendation?.model, 'gpt-6.0-sol');
    expect(recommendation?.reason, isNot(contains('固定推荐')));
  });

  test('图片和视频模型按能力独立筛选及推荐', () {
    const models = [
      'claude-sonnet-4',
      'qwen-max',
      'qwen-image-plus',
      'gpt-image-1.5',
      'kling-video-v2',
      'sora-2',
    ];

    expect(isLikelyImageGenerationModel('qwen-image-plus'), isTrue);
    expect(isLikelyImageGenerationModel('claude-sonnet-4'), isFalse);
    expect(isLikelyVideoGenerationModel('kling-video-v2'), isTrue);
    expect(isLikelyVideoGenerationModel('qwen-max'), isFalse);
    expect(recommendAiImageModel(models)?.model, 'gpt-image-1.5');
    expect(recommendAiVideoModel(models)?.model, 'sora-2');
  });
}
