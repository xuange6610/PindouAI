import 'dart:convert';
import 'dart:io';

import 'package:bead_ai_designer/services/ai_chat_service.dart';
import 'package:bead_ai_designer/services/ai_chat_store.dart';
import 'package:bead_ai_designer/services/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AI 聊天可自动读取模型并携带多轮上下文', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async => null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map<String, dynamic>>[];
    final serving = server.forEach((request) async {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer test-key',
      );
      if (request.method == 'GET' && request.uri.path == '/v1/models') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'active_model': 'model-b',
            'data': [
              {'id': 'model-b'},
              {'id': 'model-a'},
            ],
          }),
        );
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/responses') {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        requests.add((body as Map).cast<String, dynamic>());
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'model': 'model-a',
            'output_text': '第二轮回答',
            'usage': {
              'input_tokens': 31,
              'output_tokens': 9,
              'total_tokens': 40,
            },
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    await AppSettings.instance.initialize();
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}/v1',
    );
    await AppSettings.instance.setAiProviderKey('test-key');

    const service = AiChatService();
    expect(await service.listModels(), ['model-a', 'model-b']);
    final catalog = await service.loadCatalog();
    expect(catalog.activeModel, 'model-b');
    final reply = await service.send(
      model: 'model-a',
      messages: [
        AiChatMessage(
          id: '1',
          role: 'user',
          content: '第一问',
          createdAt: DateTime(2026),
        ),
        AiChatMessage(
          id: '2',
          role: 'assistant',
          content: '第一答',
          createdAt: DateTime(2026),
        ),
        AiChatMessage(
          id: '3',
          role: 'user',
          content: '继续',
          createdAt: DateTime(2026),
        ),
      ],
    );
    expect(reply.content, '第二轮回答');
    expect(reply.inputTokens, 31);
    expect(reply.outputTokens, 9);
    expect(reply.totalTokens, 40);
    expect((requests.single['input'] as List), hasLength(4));
    expect((requests.single['input'] as List).first['role'], 'system');
    expect(
      ((requests.single['input'] as List).first['content'] as List)
          .first['text'],
      contains('model-a'),
    );

    await server.close(force: true);
    await serving;
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  test('Qwen 等非 OpenAI 模型优先使用 Chat Completions 并传递真实模型名', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    await AppSettings.instance.initialize();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final serving = server.forEach((request) async {
      paths.add(request.uri.path);
      final payload =
          jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(payload['model'], 'qwen-max');
      expect((payload['messages'] as List).first['role'], 'system');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'model': 'qwen-max',
          'choices': [
            {
              'message': {'content': '我是 qwen-max'},
            },
          ],
        }),
      );
      await request.response.close();
    });
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}/v1',
    );
    await AppSettings.instance.setAiProviderKey('qwen-key');

    final reply = await const AiChatService().send(
      model: 'qwen-max',
      messages: [
        AiChatMessage(
          id: 'q1',
          role: 'user',
          content: '你是什么模型？',
          createdAt: DateTime(2026),
        ),
      ],
    );

    expect(paths.single, '/v1/chat/completions');
    expect(reply.model, 'qwen-max');
    expect(reply.content, '我是 qwen-max');
    await server.close(force: true);
    await serving;
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  test('Chat Completions SSE 会逐段输出并合并最终回答', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.first.then((request) async {
      final payload =
          jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(payload['model'], 'qwen-max');
      expect(payload['stream'], isTrue);
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.write(
        'data: ${jsonEncode({
          'model': 'qwen-max',
          'choices': [
            {
              'delta': {'content': '实时'},
            },
          ],
        })}\n\n',
      );
      await request.response.flush();
      request.response.write(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': '回答'},
            },
          ],
          'usage': {'total_tokens': 12},
        })}\n\ndata: [DONE]\n\n',
      );
      await request.response.close();
    });
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}/v1',
    );
    await AppSettings.instance.setAiProviderKey('stream-key');
    final deltas = <String>[];
    final reasoning = <String>[];

    final reply = await const AiChatService().send(
      model: 'qwen-max',
      messages: [
        AiChatMessage(
          id: 'stream',
          role: 'user',
          content: '请实时回答',
          createdAt: DateTime(2026),
        ),
      ],
      onDelta: deltas.add,
      onReasoningDelta: reasoning.add,
    );

    expect(deltas, ['实时', '回答']);
    expect(reply.content, '实时回答');
    expect(reply.totalTokens, 12);
    await server.close(force: true);
    await serving;
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  test('Anthropic Messages 协议可流式返回思考摘要和正文', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.first.then((request) async {
      expect(request.uri.path, '/v1/messages');
      expect(request.headers.value('x-api-key'), 'anthropic-key');
      final payload =
          jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(payload['model'], 'claude-sonnet-4');
      expect(payload['stream'], isTrue);
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.add(
        utf8.encode(
          'data: ${jsonEncode({
            'type': 'message_start',
            'message': {
              'model': 'claude-sonnet-4',
              'usage': {'input_tokens': 7},
            },
          })}\n\n',
        ),
      );
      request.response.add(
        utf8.encode(
          'data: ${jsonEncode({
            'type': 'content_block_delta',
            'delta': {'type': 'thinking_delta', 'thinking': '先分析'},
          })}\n\n',
        ),
      );
      request.response.add(
        utf8.encode(
          'data: ${jsonEncode({
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': '最终回答'},
          })}\n\n',
        ),
      );
      request.response.add(
        utf8.encode(
          'data: ${jsonEncode({
            'type': 'message_delta',
            'usage': {'output_tokens': 5},
          })}\n\n',
        ),
      );
      await request.response.close();
    });
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}',
    );
    await AppSettings.instance.setAiProviderKey('anthropic-key');
    await AppSettings.instance.setAiProviderProtocol(
      AiProviderProtocol.anthropic,
    );
    final textDeltas = <String>[];
    final reasoningDeltas = <String>[];
    final reply = await const AiChatService().send(
      model: 'claude-sonnet-4',
      messages: [
        AiChatMessage(
          id: 'a1',
          role: 'user',
          content: '分析问题',
          createdAt: DateTime(2026),
        ),
      ],
      onDelta: textDeltas.add,
      onReasoningDelta: reasoningDeltas.add,
    );
    expect(textDeltas, ['最终回答']);
    expect(reasoningDeltas, ['先分析']);
    expect(reply.reasoning, '先分析');
    expect(reply.totalTokens, 12);
    await server.close(force: true);
    await serving;
    await AppSettings.instance.setAiProviderProtocol(AiProviderProtocol.auto);
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  test('Gemini generateContent 协议可解析 thought 与正文', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.first.then((request) async {
      expect(request.uri.path, '/v1beta/models/gemini-2.5-pro:generateContent');
      expect(request.uri.queryParameters['key'], 'gemini-key');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'thought': true, 'text': '检查条件'},
                  {'text': 'Gemini 回答'},
                ],
              },
            },
          ],
          'usageMetadata': {
            'promptTokenCount': 4,
            'candidatesTokenCount': 6,
            'totalTokenCount': 10,
          },
        }),
      );
      await request.response.close();
    });
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}',
    );
    await AppSettings.instance.setAiProviderKey('gemini-key');
    await AppSettings.instance.setAiProviderProtocol(AiProviderProtocol.gemini);
    final reply = await const AiChatService().send(
      model: 'gemini-2.5-pro',
      messages: [
        AiChatMessage(
          id: 'g1',
          role: 'user',
          content: '你好',
          createdAt: DateTime(2026),
        ),
      ],
    );
    expect(reply.content, 'Gemini 回答');
    expect(reply.reasoning, '检查条件');
    expect(reply.totalTokens, 10);
    await server.close(force: true);
    await serving;
    await AppSettings.instance.setAiProviderProtocol(AiProviderProtocol.auto);
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  test('临时 503 后会保留原模型并自动重试', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    await AppSettings.instance.initialize();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var attempts = 0;
    server.listen((request) async {
      if (request.uri.path == '/v1/responses') {
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'unsupported endpoint'}));
        await request.response.close();
        return;
      }
      expect(request.uri.path, '/v1/chat/completions');
      attempts++;
      request.response.headers.contentType = ContentType.json;
      if (attempts == 1) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write(
          jsonEncode({
            'error': {'message': 'Service temporarily unavailable'},
          }),
        );
      } else {
        request.response.write(
          jsonEncode({
            'model': 'provider-internal-alias',
            'choices': [
              {
                'message': {'content': '连接成功'},
              },
            ],
          }),
        );
      }
      await request.response.close();
    });
    await AppSettings.instance.setAiProviderProtocol(
      AiProviderProtocol.openAiCompatible,
    );
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}/v1',
    );
    await AppSettings.instance.setAiProviderKey('retry-key');
    await AppSettings.instance.setAiModels('qwen-max');

    final reply = await const AiChatService().send(
      model: 'qwen-max',
      messages: [
        AiChatMessage(
          id: 'retry',
          role: 'user',
          content: 'ping',
          createdAt: DateTime(2026),
        ),
      ],
    );

    expect(attempts, 2);
    expect(reply.content, '连接成功');
    expect(reply.model, 'provider-internal-alias');
    expect(AppSettings.instance.aiChatModel, 'qwen-max');
    await server.close(force: true);
    await AppSettings.instance.setAiProviderProtocol(AiProviderProtocol.auto);
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });
}
