import 'package:bead_ai_designer/services/ai_usage_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AI 用量流水持久化成功、失败、Token、耗时和模型反馈', () async {
    SharedPreferences.setMockInitialValues({});
    const store = AiUsageStore();

    await store.record(
      model: 'qwen-max',
      inputTokens: 12,
      outputTokens: 24,
      totalTokens: 36,
      elapsedMs: 800,
      operation: 'AI 聊天',
      estimatedCost: 0.02,
    );
    await store.record(
      model: 'qwen-max',
      inputTokens: 5,
      outputTokens: 10,
      totalTokens: 15,
      elapsedMs: 1200,
      operation: '图片识别',
    );
    await store.recordFailure(
      model: 'qwen-max',
      elapsedMs: 3000,
      operation: 'AI 视频',
      errorCategory: '网络连接',
    );

    final stats = await store.load();
    expect(stats.requestCount, 3);
    expect(stats.inputTokens, 17);
    expect(stats.outputTokens, 34);
    expect(stats.totalTokens, 51);
    expect(stats.totalElapsedMs, 5000);
    expect(stats.events, hasLength(3));
    expect(stats.events.first.succeeded, isFalse);
    expect(stats.events.first.errorCategory, '网络连接');
    final model = stats.modelSummaries['qwen-max']!;
    expect(model.requests, 3);
    expect(model.failures, 1);
    expect(model.averageElapsedMs, 1000);
  });
}
