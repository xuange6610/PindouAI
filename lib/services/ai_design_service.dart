import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ai_chat_service.dart';
import 'ai_model_profile.dart';
import 'app_settings.dart';

class AiDesignResult {
  const AiDesignResult({required this.model, required this.content, this.raw});

  final String model;
  final String content;
  final Map<String, dynamic>? raw;
}

class AiImageResult {
  const AiImageResult({required this.model, required this.bytes, this.raw});

  final String model;
  final Uint8List bytes;
  final Map<String, dynamic>? raw;
}

class AiVideoResult {
  const AiVideoResult({
    required this.model,
    required this.bytes,
    this.mimeType = 'video/mp4',
    this.raw,
  });

  final String model;
  final Uint8List bytes;
  final String mimeType;
  final Map<String, dynamic>? raw;

  String get extension => mimeType.contains('webm')
      ? 'webm'
      : mimeType.contains('quicktime')
      ? 'mov'
      : 'mp4';
}

class AiDesignService {
  AiDesignService._();

  static final instance = AiDesignService._();

  Future<AiDesignResult> generate({
    required String prompt,
    Uint8List? imageBytes,
    String? model,
  }) async {
    await AppSettings.instance.initialize();
    final configured = AppSettings.instance.aiProxyBaseUrl.trim();
    final compiledBase = const String.fromEnvironment('AI_PROXY_BASE_URL');
    final providerBase = AppSettings.instance.aiProviderBaseUrl.trim();
    final providerKey = AppSettings.instance.aiProviderKey.trim();
    if (configured.isEmpty && compiledBase.isEmpty) {
      if (providerBase.isEmpty && providerKey.isEmpty) {
        throw StateError(
          '尚未配置 AI 服务。请在“我的 > API 设置”填写 API 中转地址和 API 密钥，或配置 APP 服务端地址。',
        );
      }
      if (providerBase.isEmpty || providerKey.isEmpty) {
        throw const FormatException('AI 直连需要同时填写“API 中转地址”和“API 密钥”');
      }
      return _generateDirect(
        providerBase: providerBase,
        providerKey: providerKey,
        prompt: prompt,
        imageBytes: imageBytes,
        model: model ?? AppSettings.instance.aiChatModel,
      );
    }
    final baseUrl = configured.isNotEmpty
        ? configured
        : compiledBase.isNotEmpty
        ? compiledBase
        : throw StateError('尚未配置 APP 服务端地址');
    if (baseUrl.toLowerCase().startsWith('sk-')) {
      throw const FormatException('这里需要填写服务地址，API 密钥请填写到设置中的“API 密钥”');
    }
    final uri = Uri.tryParse(
      '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/ai/generate',
    );
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const FormatException('AI 服务端地址格式不正确');
    }
    final isLocalHost = const {
      '127.0.0.1',
      'localhost',
      '10.0.2.2',
    }.contains(uri.host);
    if (providerKey.isNotEmpty && uri.scheme != 'https' && !isLocalHost) {
      throw const FormatException('填写 API 密钥时，AI 服务端地址必须使用 HTTPS');
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (providerBase.isNotEmpty) {
        request.headers.set('X-AI-Provider-Base-Url', providerBase);
      }
      if (providerKey.isNotEmpty) {
        request.headers.set('X-AI-Provider-Key', providerKey);
      }
      request.write(
        jsonEncode({
          'prompt': prompt,
          'model': model?.trim().isNotEmpty == true
              ? model!.trim()
              : AppSettings.instance.aiChatModel,
          if (imageBytes != null)
            'image_data_url':
                'data:image/png;base64,${base64Encode(imageBytes)}',
        }),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      Map<String, dynamic> json;
      try {
        json = (jsonDecode(body) as Map).cast<String, dynamic>();
      } on Object {
        throw HttpException('AI 服务返回了无法解析的内容（HTTP ${response.statusCode}）');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          json['detail']?.toString() ??
              'AI 服务调用失败（HTTP ${response.statusCode}）',
        );
      }
      return AiDesignResult(
        model:
            json['model']?.toString() ??
            model ??
            AppSettings.instance.aiChatModel,
        content: json['content']?.toString() ?? '',
        raw: (json['raw'] as Map?)?.cast<String, dynamic>(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<AiImageResult> generateImage({
    required String prompt,
    Uint8List? imageBytes,
    String? model,
    String size = '1024x1024',
  }) async {
    await AppSettings.instance.initialize();
    final configured = AppSettings.instance.aiProxyBaseUrl.trim();
    final compiledBase = const String.fromEnvironment('AI_PROXY_BASE_URL');
    final providerBase = AppSettings.instance.aiProviderBaseUrl.trim();
    final providerKey = AppSettings.instance.aiProviderKey.trim();
    if (configured.isEmpty && compiledBase.isEmpty) {
      if (providerBase.isEmpty && providerKey.isEmpty) {
        throw StateError('尚未配置 AI 图片服务。请填写支持 OpenAI Images API 的中转地址、密钥和图片模型。');
      }
      if (providerBase.isEmpty || providerKey.isEmpty) {
        throw const FormatException('AI 图片直连需要同时填写“API 中转地址”和“API 密钥”');
      }
      final selectedModel = model ?? AppSettings.instance.aiImageModel;
      if (_usesGeminiMediaProtocol(providerBase)) {
        return _generateGeminiImage(
          providerBase: providerBase,
          providerKey: providerKey,
          prompt: prompt,
          imageBytes: imageBytes,
          model: selectedModel,
        );
      }
      return _generateImageDirect(
        providerBase: providerBase,
        providerKey: providerKey,
        prompt: prompt,
        imageBytes: imageBytes,
        model: selectedModel,
        size: size,
      );
    }
    final baseUrl = configured.isNotEmpty
        ? configured
        : compiledBase.isNotEmpty
        ? compiledBase
        : throw StateError('尚未配置 APP 服务端地址');
    final uri = Uri.tryParse(
      '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/ai/image',
    );
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const FormatException('AI 图片服务端地址格式不正确');
    }
    final isLocalHost = const {
      '127.0.0.1',
      'localhost',
      '10.0.2.2',
    }.contains(uri.host);
    if (providerKey.isNotEmpty && uri.scheme != 'https' && !isLocalHost) {
      throw const FormatException('填写 API 密钥时，AI 服务端地址必须使用 HTTPS');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 45);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (providerBase.isNotEmpty) {
        request.headers.set('X-AI-Provider-Base-Url', providerBase);
      }
      if (providerKey.isNotEmpty) {
        request.headers.set('X-AI-Provider-Key', providerKey);
      }
      request.write(
        jsonEncode({
          'prompt': prompt,
          if (imageBytes != null)
            'image_data_url':
                'data:image/png;base64,${base64Encode(imageBytes)}',
          'model': model?.trim().isNotEmpty == true
              ? model!.trim()
              : AppSettings.instance.aiImageModel,
          'size': size,
        }),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      final json = _decodeResponse(body, response.statusCode, 'AI 图片服务');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          json['detail']?.toString() ??
              'AI 图片调用失败（HTTP ${response.statusCode}）',
        );
      }
      return _imageResultFromJson(
        json,
        fallbackModel: model?.trim().isNotEmpty == true
            ? model!.trim()
            : AppSettings.instance.aiImageModel,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Sends the selected relay model unchanged to standard compatible video
  /// endpoints. This deliberately does not restrict model names by provider;
  /// capability is determined by the configured relay at runtime.
  Future<AiVideoResult> generateVideo({
    required String prompt,
    Uint8List? imageBytes,
    String? model,
    String size = '1280x720',
    int durationSeconds = 5,
  }) async {
    await AppSettings.instance.initialize();
    final configured = AppSettings.instance.aiProxyBaseUrl.trim();
    final compiledBase = const String.fromEnvironment('AI_PROXY_BASE_URL');
    final providerBase = AppSettings.instance.aiProviderBaseUrl.trim();
    final providerKey = AppSettings.instance.aiProviderKey.trim();
    final selectedModel = model?.trim().isNotEmpty == true
        ? model!.trim()
        : AppSettings.instance.aiVideoModel;
    if (configured.isEmpty && compiledBase.isEmpty) {
      if (providerBase.isEmpty || providerKey.isEmpty) {
        throw StateError('请先配置支持视频生成端点的 API 中转地址和密钥');
      }
      if (_usesGeminiMediaProtocol(providerBase)) {
        return _generateGeminiVideo(
          providerBase: providerBase,
          providerKey: providerKey,
          prompt: prompt,
          imageBytes: imageBytes,
          model: selectedModel,
          size: size,
          durationSeconds: durationSeconds,
        );
      }
      return _generateVideoDirect(
        providerBase: providerBase,
        providerKey: providerKey,
        prompt: prompt,
        imageBytes: imageBytes,
        model: selectedModel,
        size: size,
        durationSeconds: durationSeconds,
      );
    }
    final baseUrl = configured.isNotEmpty ? configured : compiledBase;
    final uri = Uri.tryParse(
      '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/ai/video',
    );
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const FormatException('AI 视频服务端地址格式不正确');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 45)
      ..idleTimeout = const Duration(minutes: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (providerBase.isNotEmpty) {
        request.headers.set('X-AI-Provider-Base-Url', providerBase);
      }
      if (providerKey.isNotEmpty) {
        request.headers.set('X-AI-Provider-Key', providerKey);
      }
      request.write(
        jsonEncode({
          'prompt': prompt,
          'model': selectedModel,
          'size': size,
          'duration_seconds': durationSeconds,
          if (imageBytes != null)
            'image_data_url':
                'data:image/png;base64,${base64Encode(imageBytes)}',
        }),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      final json = _decodeResponse(body, response.statusCode, 'AI 视频服务');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          _apiErrorMessage(json) ??
              json['detail']?.toString() ??
              'AI 视频调用失败（HTTP ${response.statusCode}）',
          uri: uri,
        );
      }
      final result = await _tryVideoResultFromJson(
        json,
        client: client,
        fallbackModel: selectedModel,
      );
      if (result == null) throw const FormatException('AI 视频服务没有返回视频文件');
      return result;
    } finally {
      client.close(force: true);
    }
  }

  Future<AiVideoResult> _generateVideoDirect({
    required String providerBase,
    required String providerKey,
    required String prompt,
    required Uint8List? imageBytes,
    required String model,
    required String size,
    required int durationSeconds,
  }) async {
    final base = _normalizedApiBase(providerBase);
    final baseUri = Uri.tryParse(base);
    if (baseUri == null || !baseUri.hasScheme || !baseUri.hasAuthority) {
      throw const FormatException('API 中转地址格式不正确');
    }
    if (baseUri.scheme != 'https' &&
        !const {'127.0.0.1', 'localhost', '10.0.2.2'}.contains(baseUri.host)) {
      throw const FormatException('直连 API 中转地址必须使用 HTTPS');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 45)
      ..idleTimeout = const Duration(minutes: 10);
    try {
      Object? lastError;
      try {
        return await _generateVideoWithModel(
          client: client,
          base: base,
          baseUri: baseUri,
          providerKey: providerKey,
          prompt: prompt,
          imageBytes: imageBytes,
          requestModel: model,
          configuredModel: model,
          size: size,
          durationSeconds: durationSeconds,
        );
      } on Object catch (error) {
        lastError = _preferEndpointError(lastError, error);
      }
      final fallbackModels = await _mediaFallbackModels(
        configuredModel: model,
        video: true,
        providerBase: providerBase,
      );
      for (final fallbackModel in fallbackModels) {
        try {
          return await _generateVideoWithModel(
            client: client,
            base: base,
            baseUri: baseUri,
            providerKey: providerKey,
            prompt: prompt,
            imageBytes: imageBytes,
            requestModel: fallbackModel,
            configuredModel: model,
            size: size,
            durationSeconds: durationSeconds,
          );
        } on Object catch (error) {
          lastError = _preferEndpointError(lastError, error);
        }
      }
      final capabilityMessage = fallbackModels.isEmpty
          ? '账户 /models 列表中没有发现任何视频生成模型。'
          : '已自动尝试视频模型 ${fallbackModels.join('、')}。';
      throw StateError(
        'AI 视频服务无法调用：${lastError ?? '未知错误'}。$capabilityMessage'
        '请在中转账户开通视频模型与 /videos/generations 端点。',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<AiVideoResult> _generateVideoWithModel({
    required HttpClient client,
    required String base,
    required Uri baseUri,
    required String providerKey,
    required String prompt,
    required Uint8List? imageBytes,
    required String requestModel,
    required String configuredModel,
    required String size,
    required int durationSeconds,
  }) async {
    Object? lastError;
    for (final endpoint in _directVideoEndpoints(base, baseUri)) {
      try {
        final request = await client.postUrl(endpoint);
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $providerKey',
        );
        _writeVideoRequest(
          request,
          endpoint: endpoint,
          model: requestModel,
          prompt: prompt,
          size: size,
          durationSeconds: durationSeconds,
          sourceImage: imageBytes,
        );
        final response = await request.close();
        final contentType = response.headers.contentType?.mimeType ?? '';
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            contentType.startsWith('video/')) {
          return AiVideoResult(
            model: configuredModel,
            bytes: await _readBytes(response),
            mimeType: contentType,
          );
        }
        final body = await utf8.decoder.bind(response).join();
        final json = _decodeResponse(body, response.statusCode, '视频中转服务');
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final endpointError = HttpException(
            '${_apiErrorMessage(json) ?? '视频中转调用失败'}'
            '（HTTP ${response.statusCode}，端点 ${endpoint.path}，'
            '执行模型 $requestModel）',
            uri: endpoint,
          );
          lastError = _preferEndpointError(lastError, endpointError);
          continue;
        }
        final immediate = await _tryVideoResultFromJson(
          json,
          client: client,
          fallbackModel: requestModel,
        );
        if (immediate != null) {
          return _withConfiguredVideoModel(immediate, configuredModel);
        }
        final jobId = _videoJobId(json);
        if (jobId != null && jobId.isNotEmpty) {
          final polled = await _pollVideoJob(
            client: client,
            base: base,
            baseUri: baseUri,
            providerKey: providerKey,
            jobId: jobId,
            model: requestModel,
          );
          if (polled != null) {
            return _withConfiguredVideoModel(polled, configuredModel);
          }
        }
        lastError = _preferEndpointError(
          lastError,
          FormatException('视频端点 ${endpoint.path} 没有返回视频数据或可轮询的任务编号'),
        );
      } on Object catch (error) {
        lastError = _preferEndpointError(lastError, error);
      }
    }
    throw StateError('视频端点调用失败：${lastError ?? '未知错误'}');
  }

  static AiVideoResult _withConfiguredVideoModel(
    AiVideoResult result,
    String configuredModel,
  ) => AiVideoResult(
    model: configuredModel,
    bytes: result.bytes,
    mimeType: result.mimeType,
    raw: result.raw,
  );

  Future<AiImageResult> _generateImageDirect({
    required String providerBase,
    required String providerKey,
    required String prompt,
    required Uint8List? imageBytes,
    required String? model,
    required String size,
  }) async {
    final base = _normalizedApiBase(providerBase);
    final baseUri = Uri.tryParse(base);
    if (baseUri == null || !baseUri.hasScheme || !baseUri.hasAuthority) {
      throw const FormatException('API 中转地址格式不正确');
    }
    final isLocalHost = const {
      '127.0.0.1',
      'localhost',
      '10.0.2.2',
    }.contains(baseUri.host);
    if (baseUri.scheme != 'https' && !isLocalHost) {
      throw const FormatException('直连 API 中转地址必须使用 HTTPS');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 45);
    try {
      final imageModel = model?.trim().isNotEmpty == true
          ? model!.trim()
          : AppSettings.instance.aiImageModel;
      Object? lastError;

      // GPT-5 family models generate images through the Responses API's
      // image_generation tool. Image-only models still use the Images API.
      // Trying the correct route first also makes OpenAI-compatible relays
      // that expose a GPT-5 alias work without a separate provider switch.
      if (imageModel.toLowerCase().startsWith('gpt-5')) {
        try {
          return await _generateImageWithResponses(
            client: client,
            base: base,
            baseUri: baseUri,
            providerKey: providerKey,
            prompt: prompt,
            sourceImage: imageBytes,
            model: imageModel,
            size: size,
          );
        } on Object catch (error) {
          lastError = _preferEndpointError(lastError, error);
        }
      }
      try {
        return await _generateImageWithImagesApi(
          client: client,
          base: base,
          baseUri: baseUri,
          providerKey: providerKey,
          prompt: prompt,
          sourceImage: imageBytes,
          requestModel: imageModel,
          configuredModel: imageModel,
          size: size,
        );
      } on Object catch (error) {
        lastError = _preferEndpointError(lastError, error);
      }
      if (!imageModel.toLowerCase().startsWith('gpt-5')) {
        try {
          return await _generateImageWithResponses(
            client: client,
            base: base,
            baseUri: baseUri,
            providerKey: providerKey,
            prompt: prompt,
            sourceImage: imageBytes,
            model: imageModel,
            size: size,
          );
        } on Object catch (error) {
          lastError = _preferEndpointError(lastError, error);
        }
      }
      final fallbackModels = await _mediaFallbackModels(
        configuredModel: imageModel,
        video: false,
        providerBase: providerBase,
      );
      for (final fallbackModel in fallbackModels) {
        try {
          return await _generateImageWithImagesApi(
            client: client,
            base: base,
            baseUri: baseUri,
            providerKey: providerKey,
            prompt: prompt,
            sourceImage: imageBytes,
            requestModel: fallbackModel,
            configuredModel: imageModel,
            size: size,
          );
        } on Object catch (error) {
          lastError = _preferEndpointError(lastError, error);
        }
      }
      throw StateError(
        'AI 图片服务无法调用：${lastError ?? '未知错误'}。已尝试当前配置模型'
        '“$imageModel”及账户模型目录中的图片模型；请确认中转开放了图片生成能力。',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<AiImageResult> _generateImageWithImagesApi({
    required HttpClient client,
    required String base,
    required Uri baseUri,
    required String providerKey,
    required String prompt,
    required Uint8List? sourceImage,
    required String requestModel,
    required String configuredModel,
    required String size,
  }) async {
    Object? lastError;
    final endpoints = _directImageEndpoints(base, baseUri, sourceImage != null);
    for (var attempt = 0; attempt < 3; attempt++) {
      for (final endpoint in endpoints) {
        try {
          final request = await client.postUrl(endpoint.uri);
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $providerKey',
          );
          _writeImageRequest(
            request,
            model: requestModel,
            prompt: prompt,
            size: size,
            sourceImage: endpoint.isEdit ? sourceImage : null,
          );
          final response = await request.close();
          final contentType = response.headers.contentType?.mimeType ?? '';
          if (response.statusCode >= 200 &&
              response.statusCode < 300 &&
              contentType.startsWith('image/')) {
            return AiImageResult(
              model: configuredModel,
              bytes: await _readImageBytes(response),
            );
          }
          final body = await utf8.decoder.bind(response).join();
          final json = _decodeResponse(body, response.statusCode, '图片中转服务');
          if (response.statusCode < 200 || response.statusCode >= 300) {
            final endpointError = HttpException(
              '${_apiErrorMessage(json) ?? '图片中转调用失败'}'
              '（HTTP ${response.statusCode}，端点 ${endpoint.uri.path}，'
              '执行模型 $requestModel）',
              uri: endpoint.uri,
            );
            lastError = _preferEndpointError(lastError, endpointError);
            continue;
          }
          final result = await _imageResultFromOpenAiJson(
            json,
            client: client,
            fallbackModel: requestModel,
          );
          return AiImageResult(
            model: configuredModel,
            bytes: result.bytes,
            raw: result.raw,
          );
        } on Object catch (error) {
          lastError = _preferEndpointError(lastError, error);
        }
      }
      if (attempt == 2 || !_isTransientAiError(lastError)) break;
      await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
    }
    throw StateError('Images API 调用失败：${lastError ?? '未知错误'}');
  }

  Future<List<String>> _mediaFallbackModels({
    required String configuredModel,
    required bool video,
    required String providerBase,
  }) async {
    final candidates = <String>[];
    try {
      final catalog = await const AiChatService().loadCatalog().timeout(
        const Duration(seconds: 20),
      );
      candidates.addAll(
        catalog.models.where(
          video ? isLikelyVideoGenerationModel : isLikelyImageGenerationModel,
        ),
      );
      final recommendation = video
          ? recommendAiVideoModel(candidates)
          : recommendAiImageModel(candidates);
      if (recommendation != null) {
        candidates
          ..remove(recommendation.model)
          ..insert(0, recommendation.model);
      }
    } on Object {
      // The original provider error remains more useful if model discovery is
      // unavailable. Known relays can still use their documented media alias.
    }
    final host = Uri.tryParse(providerBase)?.host.toLowerCase() ?? '';
    if (!video &&
        host == 'ciyuan.fast' &&
        !candidates.contains('gpt-image-1.5')) {
      candidates.add('gpt-image-1.5');
    }
    return candidates
        .where((model) => model.trim().isNotEmpty && model != configuredModel)
        .toSet()
        .toList();
  }

  bool _usesGeminiMediaProtocol(String providerBase) {
    if (AppSettings.instance.aiProviderProtocol == AiProviderProtocol.gemini) {
      return true;
    }
    if (AppSettings.instance.aiProviderProtocol != AiProviderProtocol.auto) {
      return false;
    }
    final host = Uri.tryParse(providerBase)?.host.toLowerCase() ?? '';
    return host.contains('generativelanguage.googleapis.com');
  }

  Future<AiImageResult> _generateGeminiImage({
    required String providerBase,
    required String providerKey,
    required String prompt,
    required Uint8List? imageBytes,
    required String model,
  }) async {
    var base = providerBase.trim().replaceFirst(RegExp(r'/+$'), '');
    final modelsIndex = base.indexOf('/models/');
    if (modelsIndex >= 0) base = base.substring(0, modelsIndex);
    if (!base.endsWith('/v1beta')) {
      base = base.endsWith('/v1')
          ? '${base.substring(0, base.length - 3)}/v1beta'
          : '$base/v1beta';
    }
    final modelId = model.replaceFirst(RegExp(r'^models/'), '');
    final uri = Uri.parse(
      '$base/models/${Uri.encodeComponent(modelId)}:generateContent'
      '?key=${Uri.encodeQueryComponent(providerKey)}',
    );
    if (uri.scheme != 'https' &&
        !const {'127.0.0.1', 'localhost', '10.0.2.2'}.contains(uri.host)) {
      throw const FormatException('Gemini 图片接口必须使用 HTTPS');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 45)
      ..idleTimeout = const Duration(minutes: 5);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': prompt},
                if (imageBytes != null)
                  {
                    'inlineData': {
                      'mimeType': 'image/png',
                      'data': base64Encode(imageBytes),
                    },
                  },
              ],
            },
          ],
          'generationConfig': {
            'responseModalities': ['TEXT', 'IMAGE'],
          },
        }),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      final json = _decodeResponse(body, response.statusCode, 'Gemini 图片服务');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          _apiErrorMessage(json) ??
              'Gemini 图片调用失败（HTTP ${response.statusCode}）',
          uri: uri,
        );
      }
      final encoded = _findImageBase64(json['candidates']);
      if (encoded == null || encoded.isEmpty) {
        throw const FormatException(
          'Gemini 当前模型只返回了文本，没有返回图片；请改用支持 IMAGE 输出的 Gemini/Imagen 模型',
        );
      }
      return AiImageResult(
        model: json['modelVersion']?.toString() ?? modelId,
        bytes: Uint8List.fromList(base64Decode(encoded)),
        raw: json,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<AiVideoResult> _generateGeminiVideo({
    required String providerBase,
    required String providerKey,
    required String prompt,
    required Uint8List? imageBytes,
    required String model,
    required String size,
    required int durationSeconds,
  }) async {
    var base = providerBase.trim().replaceFirst(RegExp(r'/+$'), '');
    final modelsIndex = base.indexOf('/models/');
    if (modelsIndex >= 0) base = base.substring(0, modelsIndex);
    if (!base.endsWith('/v1beta')) {
      base = base.endsWith('/v1')
          ? '${base.substring(0, base.length - 3)}/v1beta'
          : '$base/v1beta';
    }
    final modelId = model.replaceFirst(RegExp(r'^models/'), '');
    final uri = Uri.parse(
      '$base/models/${Uri.encodeComponent(modelId)}:predictLongRunning'
      '?key=${Uri.encodeQueryComponent(providerKey)}',
    );
    if (uri.scheme != 'https' &&
        !const {'127.0.0.1', 'localhost', '10.0.2.2'}.contains(uri.host)) {
      throw const FormatException('Gemini 视频接口必须使用 HTTPS');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 45)
      ..idleTimeout = const Duration(minutes: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'instances': [
            {
              'prompt': prompt,
              if (imageBytes != null)
                'image': {
                  'bytesBase64Encoded': base64Encode(imageBytes),
                  'mimeType': 'image/png',
                },
            },
          ],
          'parameters': {
            'aspectRatio': size.startsWith('720x') ? '9:16' : '16:9',
            'durationSeconds': durationSeconds,
            'numberOfVideos': 1,
          },
        }),
      );
      final response = await request.close();
      final json = _decodeResponse(
        await utf8.decoder.bind(response).join(),
        response.statusCode,
        'Gemini 视频服务',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          _apiErrorMessage(json) ??
              'Gemini 视频调用失败（HTTP ${response.statusCode}）',
          uri: uri,
        );
      }
      final operationName = json['name']?.toString();
      if (operationName == null || operationName.isEmpty) {
        throw const FormatException('Gemini 视频服务没有返回异步任务编号');
      }
      final parsedOperation = Uri.tryParse(operationName);
      final operationUri = parsedOperation?.hasScheme == true
          ? parsedOperation!
          : Uri.parse(
              '$base/${operationName.replaceFirst(RegExp(r'^/+'), '')}',
            ).replace(queryParameters: {'key': providerKey});
      for (var attempt = 0; attempt < 60; attempt++) {
        final statusRequest = await client.getUrl(operationUri);
        statusRequest.headers.set('x-goog-api-key', providerKey);
        final statusResponse = await statusRequest.close();
        final statusJson = _decodeResponse(
          await utf8.decoder.bind(statusResponse).join(),
          statusResponse.statusCode,
          'Gemini 视频任务服务',
        );
        if (statusResponse.statusCode < 200 ||
            statusResponse.statusCode >= 300) {
          throw HttpException(
            _apiErrorMessage(statusJson) ??
                'Gemini 视频任务查询失败（HTTP ${statusResponse.statusCode}）',
            uri: operationUri,
          );
        }
        if (statusJson['error'] != null) {
          throw StateError(_apiErrorMessage(statusJson) ?? 'Gemini 视频生成失败');
        }
        if (statusJson['done'] == true) {
          final videoUrl = _findVideoUrl(statusJson['response']);
          if (videoUrl == null) {
            throw const FormatException('Gemini 视频任务已完成，但没有返回成品地址');
          }
          final downloadUri = Uri.parse(videoUrl);
          final downloadRequest = await client.getUrl(downloadUri);
          downloadRequest.headers.set('x-goog-api-key', providerKey);
          final downloadResponse = await downloadRequest.close();
          if (downloadResponse.statusCode < 200 ||
              downloadResponse.statusCode >= 300) {
            await downloadResponse.drain<void>();
            throw HttpException(
              'Gemini 视频下载失败（HTTP ${downloadResponse.statusCode}）',
              uri: downloadUri,
            );
          }
          final mime =
              downloadResponse.headers.contentType?.mimeType ?? 'video/mp4';
          return AiVideoResult(
            model: modelId,
            bytes: await _readBytes(downloadResponse),
            mimeType: mime.startsWith('video/') ? mime : 'video/mp4',
            raw: statusJson,
          );
        }
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      throw StateError('Gemini 视频生成等待超过 5 分钟');
    } finally {
      client.close(force: true);
    }
  }

  static String? _findVideoUrl(Object? value, [int depth = 0]) {
    if (value == null || depth > 8) return null;
    if (value is List) {
      for (final item in value) {
        final found = _findVideoUrl(item, depth + 1);
        if (found != null) return found;
      }
      return null;
    }
    if (value is! Map) return null;
    for (final key in const ['uri', 'url', 'videoUri', 'video_url']) {
      final candidate = value[key];
      if (candidate is String && candidate.startsWith(RegExp(r'https?://'))) {
        return candidate;
      }
    }
    for (final nested in value.values) {
      final found = _findVideoUrl(nested, depth + 1);
      if (found != null) return found;
    }
    return null;
  }

  Future<AiImageResult> _generateImageWithResponses({
    required HttpClient client,
    required String base,
    required Uri baseUri,
    required String providerKey,
    required String prompt,
    required Uint8List? sourceImage,
    required String model,
    required String size,
  }) async {
    Object? lastError;
    final endpoints = _directChatEndpoints(
      base,
      baseUri,
    ).where((candidate) => candidate.responsesApi).toList(growable: false);
    for (var attempt = 0; attempt < 3; attempt++) {
      for (final endpoint in endpoints) {
        try {
          final request = await client.postUrl(endpoint.uri);
          request.headers.contentType = ContentType.json;
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $providerKey',
          );
          request.write(
            jsonEncode({
              'model': model,
              'input': [
                {
                  'role': 'user',
                  'content': [
                    {'type': 'input_text', 'text': prompt},
                    if (sourceImage != null)
                      {
                        'type': 'input_image',
                        'image_url':
                            'data:image/png;base64,${base64Encode(sourceImage)}',
                      },
                  ],
                },
              ],
              'tools': [
                {'type': 'image_generation', 'size': size},
              ],
            }),
          );
          final response = await request.close();
          final body = await utf8.decoder.bind(response).join();
          final json = _decodeResponse(body, response.statusCode, '图片中转服务');
          if (response.statusCode < 200 || response.statusCode >= 300) {
            final endpointError = HttpException(
              '${_apiErrorMessage(json) ?? 'Responses 图片调用失败'}'
              '（HTTP ${response.statusCode}，端点 ${endpoint.uri.path}）',
              uri: endpoint.uri,
            );
            lastError = _preferEndpointError(lastError, endpointError);
            continue;
          }
          return _imageResultFromResponsesJson(json, fallbackModel: model);
        } on Object catch (error) {
          lastError = _preferEndpointError(lastError, error);
        }
      }
      if (attempt == 2 || !_isTransientAiError(lastError)) break;
      await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
    }
    throw StateError('Responses 图片调用失败：${lastError ?? '未知错误'}');
  }

  static Map<String, dynamic> _decodeResponse(
    String body,
    int statusCode,
    String name,
  ) {
    try {
      return (jsonDecode(body) as Map).cast<String, dynamic>();
    } on Object {
      throw HttpException('$name返回了无法解析的内容（HTTP $statusCode）');
    }
  }

  static Object _preferEndpointError(Object? current, Object next) {
    if (current == null) return next;
    final currentText = current.toString().toLowerCase();
    final nextText = next.toString().toLowerCase();
    final currentIsMissingPath =
        currentText.contains('http 404') || currentText.contains('404 page');
    final nextIsMissingPath =
        nextText.contains('http 404') || nextText.contains('404 page');
    if (currentIsMissingPath && !nextIsMissingPath) return next;
    if (!currentIsMissingPath && nextIsMissingPath) return current;
    return next;
  }

  static AiImageResult _imageResultFromJson(
    Map<String, dynamic> json, {
    required String fallbackModel,
  }) {
    final value = json['image_data_url']?.toString() ?? '';
    final match = RegExp(
      r'^data:image/[^;]+;base64,(.+)$',
      dotAll: true,
    ).firstMatch(value);
    if (match == null) throw const FormatException('AI 图片服务没有返回有效图片');
    try {
      return AiImageResult(
        model: json['model']?.toString() ?? fallbackModel,
        bytes: Uint8List.fromList(base64Decode(match.group(1)!)),
        raw: (json['raw'] as Map?)?.cast<String, dynamic>(),
      );
    } on Object catch (error) {
      throw FormatException('AI 图片数据损坏：$error');
    }
  }

  static Future<AiImageResult> _imageResultFromOpenAiJson(
    Map<String, dynamic> json, {
    required HttpClient client,
    required String fallbackModel,
  }) async {
    final first = _imageCandidate(json);
    if (first == null) throw const FormatException('图片中转服务没有返回图片');
    final dataUrl =
        first['image_data_url']?.toString() ??
        first['data_url']?.toString() ??
        first['image']?.toString();
    final dataMatch = dataUrl == null
        ? null
        : RegExp(
            r'^data:image/[^;]+;base64,(.+)$',
            dotAll: true,
          ).firstMatch(dataUrl);
    final encoded =
        first['b64_json']?.toString() ??
        first['base64']?.toString() ??
        first['image_base64']?.toString() ??
        first['result']?.toString() ??
        dataMatch?.group(1);
    if (encoded != null && encoded.isNotEmpty) {
      try {
        return AiImageResult(
          model: json['model']?.toString() ?? fallbackModel,
          bytes: Uint8List.fromList(base64Decode(encoded)),
          raw: json,
        );
      } on FormatException {
        // Some relays use `result` for task metadata. Try URL fields below.
      }
    }
    final url =
        first['url']?.toString() ??
        first['image_url']?.toString() ??
        first['output_url']?.toString();
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const FormatException('图片中转服务没有返回 b64_json 或可下载的图片 URL');
    }
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('无法下载图片模型返回的图片（HTTP ${response.statusCode}）');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) throw const FormatException('图片模型返回了空图片');
    return AiImageResult(
      model: json['model']?.toString() ?? fallbackModel,
      bytes: bytes,
      raw: json,
    );
  }

  static Map<String, dynamic>? _imageCandidate(Map<String, dynamic> json) {
    Map<String, dynamic>? asCandidate(Object? value) {
      if (value is Map) return value.cast<String, dynamic>();
      if (value is List && value.isNotEmpty && value.first is Map) {
        return (value.first as Map).cast<String, dynamic>();
      }
      return null;
    }

    for (final value in [
      json['data'],
      json['images'],
      json['output'],
      json['result'],
      json['image'],
    ]) {
      final candidate = asCandidate(value);
      if (candidate == null) continue;
      final nested =
          asCandidate(candidate['data']) ??
          asCandidate(candidate['images']) ??
          asCandidate(candidate['result']);
      return nested ?? candidate;
    }
    if (const {
      'b64_json',
      'base64',
      'image_base64',
      'image_data_url',
      'url',
      'image_url',
    }.any(json.containsKey)) {
      return json;
    }
    return null;
  }

  static AiImageResult _imageResultFromResponsesJson(
    Map<String, dynamic> json, {
    required String fallbackModel,
  }) {
    final encoded =
        _findImageBase64(json['output']) ??
        _findImageBase64(json['data']) ??
        _findImageBase64(json['result']);
    if (encoded != null && encoded.isNotEmpty) {
      try {
        return AiImageResult(
          model: json['model']?.toString() ?? fallbackModel,
          bytes: Uint8List.fromList(base64Decode(encoded)),
          raw: json,
        );
      } on Object catch (error) {
        throw FormatException('Responses 返回的图片数据损坏：$error');
      }
    }
    throw const FormatException('Responses 服务没有返回 image_generation_call 图片结果');
  }

  static String? _findImageBase64(Object? value, [int depth = 0]) {
    if (depth > 6 || value == null) return null;
    if (value is List) {
      for (final item in value) {
        final found = _findImageBase64(item, depth + 1);
        if (found != null) return found;
      }
      return null;
    }
    if (value is! Map) return null;
    final map = value.cast<Object?, Object?>();
    for (final key in const [
      'b64_json',
      'image_base64',
      'base64',
      'result',
      'data',
    ]) {
      final raw = map[key];
      if (raw is! String || raw.isEmpty) continue;
      final match = RegExp(
        r'^data:image/[^;]+;base64,(.+)$',
        dotAll: true,
      ).firstMatch(raw);
      return match?.group(1) ?? raw;
    }
    final inlineData = map['inlineData'] ?? map['inline_data'];
    if (inlineData is Map) {
      final encoded = inlineData['data'];
      if (encoded is String && encoded.isNotEmpty) return encoded;
    }
    for (final key in const ['output', 'content', 'parts', 'images', 'image']) {
      final found = _findImageBase64(map[key], depth + 1);
      if (found != null) return found;
    }
    return null;
  }

  Future<AiDesignResult> _generateDirect({
    required String providerBase,
    required String providerKey,
    required String prompt,
    required Uint8List? imageBytes,
    required String? model,
  }) async {
    if (providerBase.toLowerCase().startsWith('sk-')) {
      throw const FormatException('API 中转地址需要填写 URL，密钥请填写到“API 密钥”');
    }
    final base = _normalizedApiBase(providerBase);
    final baseUri = Uri.tryParse(base);
    if (baseUri == null || !baseUri.hasScheme || !baseUri.hasAuthority) {
      throw const FormatException('API 中转地址格式不正确');
    }
    final isLocalHost = const {
      '127.0.0.1',
      'localhost',
      '10.0.2.2',
    }.contains(baseUri.host);
    if (baseUri.scheme != 'https' && !isLocalHost) {
      throw const FormatException('直连 API 中转地址必须使用 HTTPS');
    }
    final selectedModel = model?.trim().isNotEmpty == true
        ? model!.trim()
        : 'gpt-5.6-sol';
    final chatContent = <Map<String, dynamic>>[
      {'type': 'text', 'text': prompt},
      if (imageBytes != null)
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:image/png;base64,${base64Encode(imageBytes)}',
          },
        },
    ];
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      Object? lastError;
      final candidates = _directChatEndpoints(base, baseUri);
      for (var attempt = 0; attempt < 3; attempt++) {
        for (final candidate in candidates) {
          try {
            final request = await client.postUrl(candidate.uri);
            request.headers.contentType = ContentType.json;
            request.headers.set(
              HttpHeaders.authorizationHeader,
              'Bearer $providerKey',
            );
            request.write(
              jsonEncode(
                candidate.responsesApi
                    ? {
                        'model': selectedModel,
                        'input': [
                          {
                            'role': 'user',
                            'content': [
                              {'type': 'input_text', 'text': prompt},
                              if (imageBytes != null)
                                {
                                  'type': 'input_image',
                                  'image_url':
                                      'data:image/png;base64,${base64Encode(imageBytes)}',
                                },
                            ],
                          },
                        ],
                      }
                    : {
                        'model': selectedModel,
                        'messages': [
                          {'role': 'user', 'content': chatContent},
                        ],
                        if (selectedModel.startsWith('gpt-5'))
                          'reasoning_effort': 'none',
                      },
              ),
            );
            final response = await request.close();
            final body = await utf8.decoder.bind(response).join();
            final json = _decodeResponse(body, response.statusCode, 'API 中转服务');
            if (response.statusCode < 200 || response.statusCode >= 300) {
              final message =
                  ((json['error'] as Map?)?['message'] ?? json['detail'])
                      ?.toString();
              final endpointError = HttpException(
                '${message ?? 'API 中转调用失败'}（HTTP ${response.statusCode}）',
                uri: candidate.uri,
              );
              lastError = _preferEndpointError(lastError, endpointError);
              continue;
            }
            final output = _chatOutputFromJson(json);
            return AiDesignResult(
              model: json['model']?.toString() ?? selectedModel,
              content: output,
              raw: json,
            );
          } on Object catch (error) {
            lastError = _preferEndpointError(lastError, error);
          }
        }
        if (attempt == 2 || !_isTransientAiError(lastError)) break;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
      throw StateError('AI 中转服务无法调用：${lastError ?? '未知错误'}');
    } finally {
      client.close(force: true);
    }
  }

  static List<({Uri uri, bool responsesApi})> _directChatEndpoints(
    String base,
    Uri baseUri,
  ) {
    final values = <({Uri uri, bool responsesApi})>[];
    void add(String suffix, bool responsesApi) {
      final uri = Uri.parse('$base$suffix');
      if (!values.any((item) => item.uri == uri)) {
        values.add((uri: uri, responsesApi: responsesApi));
      }
    }

    if (baseUri.path.endsWith('/v1')) {
      add('/responses', true);
      add('/chat/completions', false);
    } else {
      add('/responses', true);
      add('/v1/responses', true);
      add('/chat/completions', false);
      add('/v1/chat/completions', false);
    }
    return values;
  }

  static String _normalizedApiBase(String value) {
    var base = AppSettings.normalizeAiProviderBaseUrl(
      value,
    ).replaceFirst(RegExp(r'/+$'), '');
    for (final suffix in const [
      '/chat/completions',
      '/responses',
      '/images/generations',
      '/images/edits',
      '/videos/generations',
      '/video/generations',
    ]) {
      if (base.endsWith(suffix)) {
        base = base.substring(0, base.length - suffix.length);
        break;
      }
    }
    return base;
  }

  static List<({Uri uri, bool isEdit})> _directImageEndpoints(
    String base,
    Uri baseUri,
    bool hasSourceImage,
  ) {
    final values = <({Uri uri, bool isEdit})>[];
    void add(String suffix, {bool isEdit = false}) {
      final uri = Uri.parse('$base$suffix');
      if (!values.any((value) => value.uri == uri)) {
        values.add((uri: uri, isEdit: isEdit));
      }
    }

    if (baseUri.path.endsWith('/v1')) {
      if (hasSourceImage) add('/images/edits', isEdit: true);
      add('/images/generations');
    } else {
      if (hasSourceImage) {
        add('/images/edits', isEdit: true);
        add('/v1/images/edits', isEdit: true);
      }
      add('/images/generations');
      add('/v1/images/generations');
    }
    return values;
  }

  static List<Uri> _directVideoEndpoints(String base, Uri baseUri) {
    final values = <Uri>[];
    void add(String suffix) {
      final uri = Uri.parse('$base$suffix');
      if (!values.contains(uri)) values.add(uri);
    }

    if (baseUri.path.endsWith('/v1')) {
      if (baseUri.host.toLowerCase() == 'ciyuan.fast') {
        add('/videos/generations');
        add('/videos');
      } else {
        add('/videos');
        add('/videos/generations');
      }
      add('/video/generations');
    } else {
      for (final suffix in const [
        '/videos',
        '/v1/videos',
        '/videos/generations',
        '/v1/videos/generations',
        '/video/generations',
        '/v1/video/generations',
      ]) {
        add(suffix);
      }
    }
    return values;
  }

  Future<AiVideoResult?> _pollVideoJob({
    required HttpClient client,
    required String base,
    required Uri baseUri,
    required String providerKey,
    required String jobId,
    required String model,
  }) async {
    final endpoints = <Uri>[];
    void add(String suffix) {
      final value = Uri.parse('$base$suffix');
      if (!endpoints.contains(value)) endpoints.add(value);
    }

    if (baseUri.path.endsWith('/v1')) {
      add('/videos/$jobId');
      add('/video/generations/$jobId');
      add('/tasks/$jobId');
    } else {
      add('/videos/$jobId');
      add('/v1/videos/$jobId');
      add('/video/generations/$jobId');
      add('/v1/video/generations/$jobId');
      add('/tasks/$jobId');
      add('/v1/tasks/$jobId');
    }
    for (var attempt = 0; attempt < 60; attempt++) {
      for (final endpoint in endpoints) {
        try {
          final request = await client.getUrl(endpoint);
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $providerKey',
          );
          final response = await request.close();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            await response.drain<void>();
            continue;
          }
          final contentType = response.headers.contentType?.mimeType ?? '';
          if (contentType.startsWith('video/')) {
            return AiVideoResult(
              model: model,
              bytes: await _readBytes(response),
              mimeType: contentType,
            );
          }
          final json = _decodeResponse(
            await utf8.decoder.bind(response).join(),
            response.statusCode,
            '视频任务服务',
          );
          final status = json['status']?.toString().toLowerCase() ?? '';
          if (const {
            'failed',
            'error',
            'cancelled',
            'canceled',
          }.contains(status)) {
            throw StateError(_apiErrorMessage(json) ?? '视频生成任务失败');
          }
          final result = await _tryVideoResultFromJson(
            json,
            client: client,
            fallbackModel: model,
          );
          if (result != null) return result;
          if (const {
            'completed',
            'succeeded',
            'success',
            'done',
          }.contains(status)) {
            final downloaded = await _downloadCompletedVideo(
              client: client,
              base: base,
              baseUri: baseUri,
              providerKey: providerKey,
              jobId: jobId,
              model: model,
            );
            if (downloaded != null) return downloaded;
          }
        } on StateError {
          rethrow;
        } on Object {
          // Providers use different status paths; keep trying the candidates.
        }
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    throw StateError('视频生成等待超过 5 分钟');
  }

  static String? _videoJobId(Map<String, dynamic> json) {
    String? from(Object? value) {
      if (value is! Map) return null;
      return value['id']?.toString() ??
          value['task_id']?.toString() ??
          value['taskId']?.toString() ??
          value['request_id']?.toString();
    }

    return json['id']?.toString() ??
        json['task_id']?.toString() ??
        json['taskId']?.toString() ??
        json['request_id']?.toString() ??
        from(json['data']) ??
        from(json['output']) ??
        from(json['result']);
  }

  Future<AiVideoResult?> _downloadCompletedVideo({
    required HttpClient client,
    required String base,
    required Uri baseUri,
    required String providerKey,
    required String jobId,
    required String model,
  }) async {
    final endpoints = <Uri>[];
    void add(String suffix) {
      final uri = Uri.parse('$base$suffix');
      if (!endpoints.contains(uri)) endpoints.add(uri);
    }

    if (baseUri.path.endsWith('/v1')) {
      add('/videos/$jobId/content');
      add('/videos/$jobId/download');
      add('/tasks/$jobId/content');
    } else {
      for (final suffix in [
        '/videos/$jobId/content',
        '/v1/videos/$jobId/content',
        '/videos/$jobId/download',
        '/v1/videos/$jobId/download',
        '/tasks/$jobId/content',
        '/v1/tasks/$jobId/content',
      ]) {
        add(suffix);
      }
    }
    for (final endpoint in endpoints) {
      try {
        final request = await client.getUrl(endpoint);
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $providerKey',
        );
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.drain<void>();
          continue;
        }
        final contentType = response.headers.contentType?.mimeType ?? '';
        if (contentType.startsWith('video/') ||
            contentType == 'application/octet-stream') {
          return AiVideoResult(
            model: model,
            bytes: await _readBytes(response),
            mimeType: contentType.startsWith('video/')
                ? contentType
                : 'video/mp4',
          );
        }
        final json = _decodeResponse(
          await utf8.decoder.bind(response).join(),
          response.statusCode,
          '视频下载服务',
        );
        final result = await _tryVideoResultFromJson(
          json,
          client: client,
          fallbackModel: model,
        );
        if (result != null) return result;
      } on Object {
        // Keep trying provider-specific content paths.
      }
    }
    return null;
  }

  static Future<AiVideoResult?> _tryVideoResultFromJson(
    Map<String, dynamic> json, {
    required HttpClient client,
    required String fallbackModel,
  }) async {
    final candidate = _videoCandidate(json);
    final model = json['model']?.toString() ?? fallbackModel;
    final dataUrl =
        candidate?['video_data_url']?.toString() ??
        candidate?['data_url']?.toString() ??
        candidate?['video']?.toString() ??
        json['video_data_url']?.toString() ??
        '';
    final dataMatch = RegExp(
      r'^data:(video/[^;]+);base64,(.+)$',
      dotAll: true,
    ).firstMatch(dataUrl);
    if (dataMatch != null) {
      return AiVideoResult(
        model: model,
        bytes: Uint8List.fromList(base64Decode(dataMatch.group(2)!)),
        mimeType: dataMatch.group(1)!,
        raw: json,
      );
    }
    final encoded =
        candidate?['b64_json']?.toString() ??
        candidate?['b64_video']?.toString() ??
        candidate?['video_base64']?.toString() ??
        candidate?['base64']?.toString() ??
        candidate?['result']?.toString();
    if (encoded != null && encoded.isNotEmpty && !encoded.startsWith('http')) {
      try {
        return AiVideoResult(
          model: model,
          bytes: Uint8List.fromList(base64Decode(encoded)),
          mimeType: candidate?['mime_type']?.toString() ?? 'video/mp4',
          raw: json,
        );
      } on FormatException {
        // Some APIs use `result` for non-base64 metadata; try URL fields next.
      }
    }
    final url =
        candidate?['url']?.toString() ??
        candidate?['video_url']?.toString() ??
        candidate?['download_url']?.toString() ??
        candidate?['content_url']?.toString() ??
        json['url']?.toString() ??
        json['video_url']?.toString() ??
        json['download_url']?.toString();
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException('无法下载视频模型返回的文件（HTTP ${response.statusCode}）');
    }
    final mime =
        response.headers.contentType?.mimeType ??
        candidate?['mime_type']?.toString() ??
        'video/mp4';
    return AiVideoResult(
      model: model,
      bytes: await _readBytes(response),
      mimeType: mime,
      raw: json,
    );
  }

  static Map<String, dynamic>? _videoCandidate(Map<String, dynamic> json) {
    Map<String, dynamic>? convert(Object? value) {
      if (value is Map) return value.cast<String, dynamic>();
      if (value is List) {
        for (final item in value) {
          if (item is Map) return item.cast<String, dynamic>();
        }
      }
      return null;
    }

    var candidate = json;
    for (var depth = 0; depth < 5; depth++) {
      Map<String, dynamic>? nested;
      for (final key in const ['data', 'output', 'result', 'video']) {
        nested = convert(candidate[key]);
        if (nested != null) break;
      }
      if (nested == null) break;
      candidate = nested;
    }
    return candidate;
  }

  static Future<Uint8List> _readBytes(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response) {
      length += chunk.length;
      if (length > 150 * 1024 * 1024) {
        throw const FormatException('AI 视频文件超过 150MB，已停止下载');
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) throw const FormatException('AI 视频服务返回了空文件');
    return bytes;
  }

  static Future<Uint8List> _readImageBytes(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response) {
      length += chunk.length;
      if (length > 40 * 1024 * 1024) {
        throw const FormatException('AI 图片文件超过 40MB，已停止下载');
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) throw const FormatException('AI 图片服务返回了空文件');
    return bytes;
  }

  static void _writeImageRequest(
    HttpClientRequest request, {
    required String model,
    required String prompt,
    required String size,
    required Uint8List? sourceImage,
  }) {
    // GPT Image rejects `response_format`, while DALL-E can return a URL by
    // default. Omitting it keeps both families and strict relays compatible.
    if (sourceImage == null) {
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({'model': model, 'prompt': prompt, 'size': size, 'n': 1}),
      );
      return;
    }

    final boundary = '----BeadAi${DateTime.now().microsecondsSinceEpoch}';
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );
    void field(String name, String value) {
      request.write('--$boundary\r\n');
      request.write('Content-Disposition: form-data; name="$name"\r\n\r\n');
      request.write('$value\r\n');
    }

    field('model', model);
    field('prompt', prompt);
    field('size', size);
    request.write('--$boundary\r\n');
    request.write(
      'Content-Disposition: form-data; name="image"; filename="reference.png"\r\n',
    );
    request.write('Content-Type: image/png\r\n\r\n');
    request.add(sourceImage);
    request.write('\r\n--$boundary--\r\n');
  }

  static void _writeVideoRequest(
    HttpClientRequest request, {
    required Uri endpoint,
    required String model,
    required String prompt,
    required String size,
    required int durationSeconds,
    required Uint8List? sourceImage,
  }) {
    final openAiVideos = endpoint.path.endsWith('/videos');
    if (!openAiVideos || sourceImage == null) {
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(
          openAiVideos
              ? {
                  'model': model,
                  'prompt': prompt,
                  'size': size,
                  'seconds': '$durationSeconds',
                }
              : {
                  'model': model,
                  'prompt': prompt,
                  'size': size,
                  'duration': durationSeconds,
                  'duration_seconds': durationSeconds,
                  'seconds': '$durationSeconds',
                  if (sourceImage != null)
                    'image_data_url':
                        'data:image/png;base64,${base64Encode(sourceImage)}',
                },
        ),
      );
      return;
    }

    final boundary = '----BeadVideo${DateTime.now().microsecondsSinceEpoch}';
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );
    void field(String name, String value) {
      request.write('--$boundary\r\n');
      request.write('Content-Disposition: form-data; name="$name"\r\n\r\n');
      request.write('$value\r\n');
    }

    field('model', model);
    field('prompt', prompt);
    field('size', size);
    field('seconds', '$durationSeconds');
    request.write('--$boundary\r\n');
    request.write(
      'Content-Disposition: form-data; name="input_reference"; '
      'filename="reference.png"\r\n',
    );
    request.write('Content-Type: image/png\r\n\r\n');
    request.add(sourceImage);
    request.write('\r\n--$boundary--\r\n');
  }

  static String? _apiErrorMessage(Map<String, dynamic> json) {
    final error = json['error'];
    if (error is Map) {
      return error['message']?.toString() ?? error['code']?.toString();
    }
    return error?.toString() ?? json['detail']?.toString();
  }

  static bool _isTransientAiError(Object? error) {
    final value = error?.toString().toLowerCase() ?? '';
    return value.contains('http 429') ||
        value.contains('http 500') ||
        value.contains('http 502') ||
        value.contains('http 503') ||
        value.contains('http 504') ||
        value.contains('temporarily unavailable') ||
        value.contains('service unavailable') ||
        value.contains('connection reset');
  }

  static String _chatOutputFromJson(Map<String, dynamic> json) {
    final direct = json['output_text'];
    if (direct is String && direct.isNotEmpty) return direct;
    final choices = json['choices'] as List? ?? const [];
    final message = choices.isEmpty
        ? null
        : (choices.first as Map?)?['message'];
    final contentValue = (message as Map?)?['content'];
    if (contentValue is List) {
      return contentValue
          .whereType<Map>()
          .map((item) => item['text']?.toString() ?? '')
          .join();
    }
    if (contentValue != null) return contentValue.toString();
    final output = json['output'] as List? ?? const [];
    return output
        .whereType<Map>()
        .expand(
          (item) => (item['content'] as List? ?? const []).whereType<Map>(),
        )
        .map((item) => item['text']?.toString() ?? '')
        .join();
  }
}
