import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bead_ai_designer/services/ai_design_service.dart';
import 'package:bead_ai_designer/services/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('自定义中转地址和密钥可以立即用于 AI 直连', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureStorage = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestHandled = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer test-key',
      );
      final payload =
          jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(payload['model'], 'gpt-5.6-sol');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'model': 'gpt-5.6-sol',
          'choices': [
            {
              'message': {'content': '连接成功'},
            },
          ],
        }),
      );
      await request.response.close();
    });

    await AppSettings.instance.initialize();
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}/v1',
    );
    await AppSettings.instance.setAiProviderKey('test-key');
    final result = await AiDesignService.instance.generate(prompt: 'ping');

    expect(result.content, '连接成功');
    expect(result.model, 'gpt-5.6-sol');
    await requestHandled;
    await server.close(force: true);
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test('图片直连会回退到生成端点并读取 Base64 图片', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureStorage = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final generated = Completer<void>();
    var editRequests = 0;
    server.listen((request) async {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer image-key',
      );
      if (request.uri.path.endsWith('/images/edits')) {
        editRequests++;
        final multipartBody = latin1.decode(
          await request.fold<List<int>>(<int>[], (bytes, chunk) {
            bytes.addAll(chunk);
            return bytes;
          }),
        );
        expect(multipartBody, contains('name="model"'));
        expect(multipartBody, isNot(contains('name="n"')));
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'error': {'message': 'not supported'},
          }),
        );
      } else {
        expect(request.uri.path, endsWith('/v1/images/generations'));
        final payload =
            jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(payload['model'], 'image-test-model');
        expect(payload.containsKey('response_format'), isFalse);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'model': 'image-test-model',
            'data': [
              {
                'b64_json': base64Encode([137, 80, 78, 71, 13, 10, 26, 10]),
              },
            ],
          }),
        );
        generated.complete();
      }
      await request.response.close();
    });

    await AppSettings.instance.initialize();
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}/v1/chat/completions',
    );
    await AppSettings.instance.setAiProviderKey('image-key');
    await AppSettings.instance.setAiImageModel('image-test-model');
    final result = await AiDesignService.instance.generateImage(
      prompt: 'test image',
      imageBytes: Uint8List.fromList([1, 2, 3]),
      size: '256x256',
    );

    expect(editRequests, 1);
    expect(result.model, 'image-test-model');
    expect(result.bytes, [137, 80, 78, 71, 13, 10, 26, 10]);
    await generated.future;
    await server.close(force: true);
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test('GPT-5 图片模型通过 Responses image_generation 返回图片', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureStorage = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = Completer<void>();
    server.listen((request) async {
      expect(request.uri.path, '/v1/responses');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer responses-key',
      );
      final payload =
          jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(payload['model'], 'gpt-5.6-sol');
      final tool = (payload['tools'] as List).single as Map;
      expect(tool['type'], 'image_generation');
      expect(tool['size'], '1024x1024');
      expect(tool.containsKey('action'), isFalse);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'model': 'gpt-5.6-sol',
          'output': [
            {
              'type': 'image_generation_call',
              'result': base64Encode([137, 80, 78, 71, 13, 10, 26, 10]),
            },
          ],
        }),
      );
      await request.response.close();
      handled.complete();
    });

    await AppSettings.instance.initialize();
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}/v1',
    );
    await AppSettings.instance.setAiProviderKey('responses-key');
    await AppSettings.instance.setAiImageModel('gpt-5.6-sol');
    final result = await AiDesignService.instance.generateImage(
      prompt: 'make a bead pattern',
    );

    expect(result.model, 'gpt-5.6-sol');
    expect(result.bytes, [137, 80, 78, 71, 13, 10, 26, 10]);
    await handled.future;
    await server.close(force: true);
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test('Qwen 等模型在 Images 不可用时会回退 Responses 生图工具', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureStorage = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final serving = server.forEach((request) async {
      paths.add(request.uri.path);
      if (request.uri.path.endsWith('/images/generations')) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'not supported'}));
      } else {
        expect(request.uri.path, '/v1/responses');
        final payload =
            jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(payload['model'], 'qwen-max');
        expect((payload['tools'] as List).single['type'], 'image_generation');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'model': 'qwen-max',
            'output': [
              {
                'type': 'image_generation_call',
                'result': base64Encode([137, 80, 78, 71, 13, 10, 26, 10]),
              },
            ],
          }),
        );
      }
      await request.response.close();
    });
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}/v1',
    );
    await AppSettings.instance.setAiProviderKey('qwen-image-key');
    final result = await AiDesignService.instance.generateImage(
      prompt: '拼豆图',
      model: 'qwen-max',
    );
    expect(result.model, 'qwen-max');
    expect(paths, ['/v1/images/generations', '/v1/responses']);
    await server.close(force: true);
    await serving;
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test('任意中转模型名都可提交到兼容视频生成端点', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureStorage = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.first.then((request) async {
      expect(request.uri.path, '/v1/videos');
      final payload =
          jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(payload['model'], 'glm-5.2');
      expect(payload['size'], '1280x720');
      expect(payload['seconds'], '5');
      expect(payload.containsKey('duration_seconds'), isFalse);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'model': 'glm-5.2',
          'data': [
            {
              'b64_video': base64Encode([0, 0, 0, 20, 102, 116, 121, 112]),
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
    await AppSettings.instance.setAiProviderKey('video-key');
    final result = await AiDesignService.instance.generateVideo(
      prompt: '拼豆旋转动画',
      model: 'glm-5.2',
    );
    expect(result.model, 'glm-5.2');
    expect(result.bytes, [0, 0, 0, 20, 102, 116, 121, 112]);
    await server.close(force: true);
    await serving;
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test('纯对话模型会自动路由到账户可用的图片和视频执行模型', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureStorage = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final executionModels = <String>[];
    server.listen((request) async {
      if (request.method == 'GET' && request.uri.path == '/v1/models') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {'id': 'claude-sonnet-4'},
              {'id': 'gpt-image-1.5'},
              {'id': 'kling-video-v2'},
            ],
          }),
        );
        await request.response.close();
        return;
      }
      final payload =
          jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      final requestModel = payload['model']?.toString() ?? '';
      executionModels.add(requestModel);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/v1/images/generations' &&
          requestModel == 'gpt-image-1.5') {
        request.response.write(
          jsonEncode({
            'data': [
              {
                'b64_json': base64Encode([137, 80, 78, 71]),
              },
            ],
          }),
        );
      } else if (request.uri.path == '/v1/videos' &&
          requestModel == 'kling-video-v2') {
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.add([0, 0, 0, 20, 102, 116, 121, 112]);
      } else {
        request.response.statusCode =
            request.uri.path.endsWith('/videos') ||
                request.uri.path.endsWith('/video/generations')
            ? HttpStatus.notFound
            : HttpStatus.badRequest;
        request.response.write(
          jsonEncode({
            'error': {'message': 'configured model has no media capability'},
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
    await AppSettings.instance.setAiProviderKey('media-key');

    final image = await AiDesignService.instance.generateImage(
      prompt: '生成拼豆图',
      model: 'claude-sonnet-4',
    );
    expect(image.model, 'claude-sonnet-4');
    expect(image.bytes, [137, 80, 78, 71]);

    final video = await AiDesignService.instance.generateVideo(
      prompt: '生成拼豆视频',
      model: 'claude-sonnet-4',
    );
    expect(video.model, 'claude-sonnet-4');
    expect(video.bytes, [0, 0, 0, 20, 102, 116, 121, 112]);
    expect(executionModels, contains('gpt-image-1.5'));
    expect(executionModels, contains('kling-video-v2'));

    await server.close(force: true);
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test('严格 Images 中转无需 response_format 并兼容 images/base64 响应', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureStorage = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.first.then((request) async {
      expect(request.uri.path, '/v1/images/generations');
      final payload =
          jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(payload['model'], 'cogview-4');
      expect(payload['size'], '1024x1024');
      expect(payload['n'], 1);
      expect(payload['n'], isA<int>());
      expect(payload.containsKey('response_format'), isFalse);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'images': [
            {
              'base64': base64Encode([137, 80, 78, 71, 13, 10, 26, 10]),
            },
          ],
        }),
      );
      await request.response.close();
    });
    await AppSettings.instance.setAiProviderProtocol(
      AiProviderProtocol.openAiCompatible,
    );
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}/v1',
    );
    await AppSettings.instance.setAiProviderKey('strict-image-key');
    final result = await AiDesignService.instance.generateImage(
      prompt: '清晰拼豆图',
      model: 'cogview-4',
    );
    expect(result.bytes, [137, 80, 78, 71, 13, 10, 26, 10]);
    await serving;
    await server.close(force: true);
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test('Gemini 图片协议可解析 generateContent inlineData', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureStorage = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.first.then((request) async {
      expect(
        request.uri.path,
        '/v1beta/models/gemini-2.5-flash-image:generateContent',
      );
      expect(request.uri.queryParameters['key'], 'gemini-image-key');
      final payload =
          jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect((payload['generationConfig'] as Map)['responseModalities'], [
        'TEXT',
        'IMAGE',
      ]);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'modelVersion': 'gemini-2.5-flash-image',
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'inlineData': {
                      'mimeType': 'image/png',
                      'data': base64Encode([137, 80, 78, 71, 13, 10, 26, 10]),
                    },
                  },
                ],
              },
            },
          ],
        }),
      );
      await request.response.close();
    });
    await AppSettings.instance.setAiProviderProtocol(AiProviderProtocol.gemini);
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}',
    );
    await AppSettings.instance.setAiProviderKey('gemini-image-key');
    final result = await AiDesignService.instance.generateImage(
      prompt: '生成拼豆图',
      model: 'gemini-2.5-flash-image',
    );
    expect(result.model, 'gemini-2.5-flash-image');
    expect(result.bytes, [137, 80, 78, 71, 13, 10, 26, 10]);
    await serving;
    await server.close(force: true);
    await AppSettings.instance.setAiProviderProtocol(AiProviderProtocol.auto);
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test('OpenAI 视频异步任务完成后会下载 content 成品', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureStorage = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final serving = server.forEach((request) async {
      paths.add(request.uri.path);
      if (request.method == 'POST') {
        final payload =
            jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(payload, {
          'model': 'sora-2',
          'prompt': '拼豆旋转',
          'size': '1280x720',
          'seconds': '5',
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'id': 'video_123', 'status': 'queued'}),
        );
      } else if (request.uri.path == '/v1/videos/video_123') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'id': 'video_123', 'status': 'completed'}),
        );
      } else if (request.uri.path == '/v1/videos/video_123/content') {
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.add([0, 0, 0, 20, 102, 116, 121, 112]);
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
    await AppSettings.instance.setAiProviderKey('video-key');
    final result = await AiDesignService.instance.generateVideo(
      prompt: '拼豆旋转',
      model: 'sora-2',
    );
    expect(result.bytes, [0, 0, 0, 20, 102, 116, 121, 112]);
    expect(paths, [
      '/v1/videos',
      '/v1/videos/video_123',
      '/v1/videos/video_123/content',
    ]);
    await server.close(force: true);
    await serving;
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test('Gemini Veo 长任务完成后可携带密钥下载视频', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureStorage = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final serving = server.forEach((request) async {
      paths.add(request.uri.path);
      if (request.method == 'POST') {
        expect(
          request.uri.path,
          '/v1beta/models/veo-3.0-generate-preview:predictLongRunning',
        );
        expect(request.uri.queryParameters['key'], 'gemini-video-key');
        final payload =
            jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect((payload['parameters'] as Map)['aspectRatio'], '16:9');
        expect((payload['parameters'] as Map)['durationSeconds'], 5);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'name': 'http://127.0.0.1:${server.port}/operation/video_456',
          }),
        );
      } else if (request.uri.path == '/operation/video_456') {
        expect(request.headers.value('x-goog-api-key'), 'gemini-video-key');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'done': true,
            'response': {
              'generateVideoResponse': {
                'generatedSamples': [
                  {
                    'video': {
                      'uri':
                          'http://127.0.0.1:${server.port}/download/video_456',
                    },
                  },
                ],
              },
            },
          }),
        );
      } else if (request.uri.path == '/download/video_456') {
        expect(request.headers.value('x-goog-api-key'), 'gemini-video-key');
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.add([0, 0, 0, 20, 102, 116, 121, 112]);
      }
      await request.response.close();
    });
    await AppSettings.instance.setAiProviderProtocol(AiProviderProtocol.gemini);
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}',
    );
    await AppSettings.instance.setAiProviderKey('gemini-video-key');
    final result = await AiDesignService.instance.generateVideo(
      prompt: '拼豆旋转',
      model: 'veo-3.0-generate-preview',
    );
    expect(result.model, 'veo-3.0-generate-preview');
    expect(result.bytes, [0, 0, 0, 20, 102, 116, 121, 112]);
    expect(paths, [
      '/v1beta/models/veo-3.0-generate-preview:predictLongRunning',
      '/operation/video_456',
      '/download/video_456',
    ]);
    await server.close(force: true);
    await serving;
    await AppSettings.instance.setAiProviderProtocol(AiProviderProtocol.auto);
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test('图片接口遇到临时 503 会自动重试并保留所选模型', () async {
    final testHttpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    const secureStorage = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    final serving = server.forEach((request) async {
      requests++;
      expect(request.uri.path, '/v1/responses');
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      if (requests < 3) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write(
          jsonEncode({
            'error': {'message': 'temporarily unavailable'},
          }),
        );
      } else {
        request.response.write(
          jsonEncode({
            'model': 'provider-image-alias',
            'output': [
              {
                'type': 'image_generation_call',
                'result': base64Encode([137, 80, 78, 71, 13, 10, 26, 10]),
              },
            ],
          }),
        );
      }
      await request.response.close();
    });
    await AppSettings.instance.setAiProviderProtocol(AiProviderProtocol.auto);
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderBaseUrl(
      'http://127.0.0.1:${server.port}/v1',
    );
    await AppSettings.instance.setAiProviderKey('retry-image-key');
    await AppSettings.instance.setAiModels('gpt-5.6-sol');

    final result = await AiDesignService.instance.generateImage(
      prompt: 'retry image test',
      model: 'gpt-5.6-sol',
    );

    expect(requests, 3);
    expect(result.model, 'provider-image-alias');
    expect(result.bytes, [137, 80, 78, 71, 13, 10, 26, 10]);
    await server.close(force: true);
    await serving;
    HttpOverrides.global = testHttpOverride;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });
}
