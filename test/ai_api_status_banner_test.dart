import 'package:bead_ai_designer/services/ai_api_health_service.dart';
import 'package:bead_ai_designer/services/ai_chat_service.dart';
import 'package:bead_ai_designer/services/ai_chat_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AI 检测失败提示在去配置旁提供关闭按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AiApiStatusBanner(onOpenSettings: () {})),
      ),
    );
    expect(find.text('去配置'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dismissAiApiStatusBanner')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('dismissAiApiStatusBanner')));
    await tester.pump();
    expect(find.text('去配置'), findsNothing);
  });

  testWidgets('选择模型后的对话与图片后台检测失败会显示可关闭详情', (tester) async {
    await AiApiHealthService.instance.checkSelectedModelCapabilities(
      model: 'qwen-max',
      chatService: const _SuccessfulChatService(),
      imageProbe: (_) async => throw StateError('图片端点未开通'),
    );

    expect(
      AiApiHealthService.instance.selectedModelState,
      AiSelectedModelHealthState.unhealthy,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AiApiStatusBanner(onOpenSettings: () {})),
      ),
    );
    expect(find.textContaining('模型 qwen-max 后台检测未全部通过'), findsOneWidget);
    expect(find.textContaining('AI 图片模型'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dismissAiApiStatusBanner')));
    await tester.pump();
    expect(find.textContaining('模型 qwen-max'), findsNothing);
  });
}

class _SuccessfulChatService extends AiChatService {
  const _SuccessfulChatService();

  @override
  Future<AiChatReply> send({
    required String model,
    required List<AiChatMessage> messages,
    AiChatCancelToken? cancelToken,
    void Function(String delta)? onDelta,
    void Function(String delta)? onReasoningDelta,
  }) async => AiChatReply(model: model, content: 'OK');
}
