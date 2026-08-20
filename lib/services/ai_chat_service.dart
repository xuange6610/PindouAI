import 'dart:convert';
import 'dart:io';

import 'app_settings.dart';
import 'ai_attachment_reader.dart';
import 'ai_chat_store.dart';
import 'ai_model_profile.dart';

class AiChatReply {
  const AiChatReply({
    required this.model,
    required this.content,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalTokens = 0,
    this.reasoning = '',
  });

  final String model;
  final String content;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final String reasoning;
}

class AiChatCancelledException implements Exception {
  const AiChatCancelledException();

  @override
  String toString() => '已停止本次 AI 对话';
}

class AiChatTimeoutException implements Exception {
  const AiChatTimeoutException([this.message = 'AI 对话等待响应超时']);

  final String message;

  @override
  String toString() => message;
}

class AiChatCancelToken {
  HttpClient? _client;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
    _client = null;
  }

  void attach(HttpClient client) {
    if (_cancelled) {
      client.close(force: true);
      throw const AiChatCancelledException();
    }
    _client = client;
  }

  void detach(HttpClient client) {
    if (identical(_client, client)) _client = null;
  }

  void throwIfCancelled() {
    if (_cancelled) throw const AiChatCancelledException();
  }
}

class AiModelCatalog {
  const AiModelCatalog({required this.models, this.activeModel});

  final List<String> models;
  final String? activeModel;
}

class AiBalanceInfo {
  const AiBalanceInfo({
    required this.available,
    this.amount,
    this.currency = 'USD',
    this.label = '供应商未提供余额接口',
  });

  final bool available;
  final double? amount;
  final String currency;
  final String label;

  String get displayText {
    if (!available || amount == null) return label;
    final symbol = currency.toUpperCase() == 'CNY' ? '¥' : '\$';
    return '$symbol${amount!.toStringAsFixed(2)}';
  }
}

class AiChatService {
  const AiChatService();

  Future<List<String>> listModels() async => (await loadCatalog()).models;

  Future<AiBalanceInfo> loadBalance() async {
    await AppSettings.instance.initialize();
    final settings = AppSettings.instance;
    final proxy = settings.aiProxyBaseUrl.trim();
    final providerBase = settings.aiProviderBaseUrl.trim();
    final providerKey = settings.aiProviderKey.trim();
    if (proxy.isEmpty && (providerBase.isEmpty || providerKey.isEmpty)) {
      throw StateError('请先配置 API 地址和密钥');
    }
    final candidates = proxy.isNotEmpty
        ? [Uri.parse('${proxy.replaceFirst(RegExp(r'/$'), '')}/ai/balance')]
        : _balanceEndpoints(providerBase);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      for (final uri in candidates) {
        try {
          final request = await client.getUrl(uri);
          request.headers.set(HttpHeaders.acceptHeader, 'application/json');
          if (proxy.isNotEmpty) {
            if (providerBase.isNotEmpty) {
              request.headers.set('X-AI-Provider-Base-Url', providerBase);
            }
            if (providerKey.isNotEmpty) {
              request.headers.set('X-AI-Provider-Key', providerKey);
            }
          } else {
            request.headers.set(
              HttpHeaders.authorizationHeader,
              'Bearer $providerKey',
            );
          }
          final response = await request.close();
          final body = await utf8.decoder.bind(response).join();
          if (response.statusCode == HttpStatus.notFound) continue;
          if (response.statusCode < 200 || response.statusCode >= 300) continue;
          final decoded = jsonDecode(body);
          if (decoded is! Map) continue;
          final json = decoded.cast<String, dynamic>();
          final source = json['data'] is Map
              ? (json['data'] as Map).cast<String, dynamic>()
              : json;
          final amount = _firstDouble(source, const [
            'total_available',
            'available_balance',
            'balance',
            'remaining',
            'credit',
            'amount',
          ]);
          if (amount == null) continue;
          return AiBalanceInfo(
            available: true,
            amount: amount,
            currency:
                source['currency']?.toString().toUpperCase() ??
                json['currency']?.toString().toUpperCase() ??
                'USD',
            label: 'API 账户余额',
          );
        } on Object {
          continue;
        }
      }
      return const AiBalanceInfo(available: false);
    } finally {
      client.close(force: true);
    }
  }

  Future<AiModelCatalog> loadCatalog() async {
    await AppSettings.instance.initialize();
    final settings = AppSettings.instance;
    final proxy = settings.aiProxyBaseUrl.trim();
    final providerBase = settings.aiProviderBaseUrl.trim();
    final providerKey = settings.aiProviderKey.trim();
    final protocol = _effectiveProtocol(settings);
    if (proxy.isEmpty && (providerBase.isEmpty || providerKey.isEmpty)) {
      throw StateError('请先在“我的 > API 设置”填写 API 地址和密钥');
    }
    final candidates = proxy.isNotEmpty
        ? [Uri.parse('${proxy.replaceFirst(RegExp(r'/$'), '')}/ai/models')]
        : _providerModelEndpoints(providerBase, providerKey, protocol);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      Object? lastError;
      for (final uri in candidates) {
        try {
          final request = await client.getUrl(uri);
          request.headers.set(HttpHeaders.acceptHeader, 'application/json');
          if (proxy.isNotEmpty) {
            if (providerBase.isNotEmpty) {
              request.headers.set('X-AI-Provider-Base-Url', providerBase);
            }
            if (providerKey.isNotEmpty) {
              request.headers.set('X-AI-Provider-Key', providerKey);
            }
          } else {
            _applyProviderAuth(request, providerKey, protocol);
          }
          final response = await request.close();
          final body = await utf8.decoder.bind(response).join();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            lastError = HttpException(
              '模型列表返回 HTTP ${response.statusCode}',
              uri: uri,
            );
            continue;
          }
          final decoded = jsonDecode(body);
          final values = decoded is List
              ? decoded
              : decoded is Map
              ? decoded['data'] ?? decoded['models'] ?? const []
              : const [];
          final models =
              (values as List? ?? const [])
                  .map(
                    (value) => value is Map
                        ? value['id']?.toString() ??
                              value['model_id']?.toString() ??
                              value['name']?.toString() ??
                              ''
                        : value.toString(),
                  )
                  .map((value) => value.replaceFirst(RegExp(r'^models/'), ''))
                  .where((value) => value.trim().isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
          if (models.isNotEmpty) {
            final activeModel = _activeModelFromResponse(decoded, values);
            return AiModelCatalog(
              models: models,
              activeModel: models.contains(activeModel) ? activeModel : null,
            );
          }
          lastError = const FormatException('接口没有返回任何可用模型');
        } on Object catch (error) {
          lastError = error;
        }
      }
      throw StateError('无法读取模型列表：${lastError ?? '未知错误'}');
    } finally {
      client.close(force: true);
    }
  }

  Future<AiChatReply> send({
    required String model,
    required List<AiChatMessage> messages,
    AiChatCancelToken? cancelToken,
    void Function(String delta)? onDelta,
    void Function(String delta)? onReasoningDelta,
  }) async {
    await AppSettings.instance.initialize();
    final settings = AppSettings.instance;
    final proxy = settings.aiProxyBaseUrl.trim();
    final providerBase = settings.aiProviderBaseUrl.trim();
    final providerKey = settings.aiProviderKey.trim();
    final profile = runtimeProfileForModel(model);
    final runtimeMessages = <AiChatMessage>[
      AiChatMessage(
        id: 'runtime_profile',
        role: 'system',
        content:
            '${profile.systemInstruction(model)}\n'
            '你可以阅读用户上传的图片、Word、Excel、PPT、代码、HTML 和文本附件。'
            '需要生成可下载文件时，请把完整内容放进 Markdown 代码块，并在代码块第一行写：'
            'filename: 文件名.扩展名。修改代码时必须返回修改后的完整代码，不能只描述修改步骤。',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      ...messages.where((message) => message.id != 'runtime_profile'),
    ];
    if (proxy.isNotEmpty) {
      return _sendToAppGateway(
        proxy: proxy,
        providerBase: providerBase,
        providerKey: providerKey,
        model: model,
        messages: runtimeMessages,
        cancelToken: cancelToken,
        onDelta: onDelta,
        onReasoningDelta: onReasoningDelta,
      );
    }
    if (providerBase.isEmpty || providerKey.isEmpty) {
      throw StateError('请先在“我的 > API 设置”填写 API 地址和密钥');
    }
    return _sendDirect(
      providerBase: providerBase,
      providerKey: providerKey,
      model: model,
      messages: runtimeMessages,
      cancelToken: cancelToken,
      onDelta: onDelta,
      onReasoningDelta: onReasoningDelta,
    );
  }

  Future<AiChatReply> _sendToAppGateway({
    required String proxy,
    required String providerBase,
    required String providerKey,
    required String model,
    required List<AiChatMessage> messages,
    AiChatCancelToken? cancelToken,
    void Function(String delta)? onDelta,
    void Function(String delta)? onReasoningDelta,
  }) async {
    final root = proxy.replaceFirst(RegExp(r'/$'), '');
    final uris = [
      if (onDelta != null) Uri.parse('$root/ai/chat/stream'),
      Uri.parse('$root/ai/chat'),
    ];
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(minutes: 3);
    cancelToken?.attach(client);
    try {
      Object? lastError;
      final gatewayMessages = await _gatewayMessages(messages);
      for (final uri in uris) {
        cancelToken?.throwIfCancelled();
        try {
          final request = await client.postUrl(uri);
          request.headers.contentType = ContentType.json;
          request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
          if (providerBase.isNotEmpty) {
            request.headers.set('X-AI-Provider-Base-Url', providerBase);
          }
          if (providerKey.isNotEmpty) {
            request.headers.set('X-AI-Provider-Key', providerKey);
          }
          request.write(
            jsonEncode({
              'model': model,
              'messages': gatewayMessages,
              if (onDelta != null) 'stream': true,
            }),
          );
          final response = await request.close();
          cancelToken?.throwIfCancelled();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            final body = await utf8.decoder.bind(response).join();
            final json = _decodeJson(body, response.statusCode);
            lastError = HttpException(
              json['detail']?.toString() ??
                  'AI 网关返回 HTTP ${response.statusCode}',
              uri: uri,
            );
            if (response.statusCode == HttpStatus.notFound &&
                uri != uris.last) {
              continue;
            }
            throw lastError;
          }
          return _readReplyResponse(
            response,
            fallbackModel: model,
            onDelta: onDelta,
            onReasoningDelta: onReasoningDelta,
          );
        } on Object catch (error) {
          cancelToken?.throwIfCancelled();
          lastError = error;
          rethrow;
        }
      }
      throw StateError('AI 网关调用失败：${lastError ?? '未知错误'}');
    } finally {
      cancelToken?.detach(client);
      client.close(force: true);
    }
  }

  Future<AiChatReply> _sendDirect({
    required String providerBase,
    required String providerKey,
    required String model,
    required List<AiChatMessage> messages,
    AiChatCancelToken? cancelToken,
    void Function(String delta)? onDelta,
    void Function(String delta)? onReasoningDelta,
  }) async {
    final protocol = _effectiveProtocol(AppSettings.instance);
    if (protocol == AiProviderProtocol.anthropic) {
      return _sendAnthropic(
        providerBase: providerBase,
        providerKey: providerKey,
        model: model,
        messages: messages,
        cancelToken: cancelToken,
        onDelta: onDelta,
        onReasoningDelta: onReasoningDelta,
      );
    }
    if (protocol == AiProviderProtocol.gemini) {
      return _sendGemini(
        providerBase: providerBase,
        providerKey: providerKey,
        model: model,
        messages: messages,
        cancelToken: cancelToken,
        onDelta: onDelta,
        onReasoningDelta: onReasoningDelta,
      );
    }
    final base = _normalizedBase(providerBase);
    final uri = Uri.tryParse(base);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const FormatException('API 中转地址格式不正确');
    }
    if (uri.scheme != 'https' && !_isLocalHost(uri.host)) {
      throw const FormatException('AI API 地址必须使用 HTTPS');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(minutes: 3);
    cancelToken?.attach(client);
    try {
      Object? lastError;
      final endpoints = _chatEndpoints(base, uri, model);
      for (var attempt = 0; attempt < 3; attempt++) {
        for (final endpoint in endpoints) {
          cancelToken?.throwIfCancelled();
          try {
            final request = await client.postUrl(endpoint.uri);
            request.headers.contentType = ContentType.json;
            request.headers.set(
              HttpHeaders.authorizationHeader,
              'Bearer $providerKey',
            );
            request.headers.set(
              HttpHeaders.acceptHeader,
              onDelta == null ? 'application/json' : 'text/event-stream',
            );
            request.write(
              jsonEncode(
                endpoint.responses
                    ? {
                        'model': model,
                        'input': await _responsesMessages(messages),
                        if (onDelta != null) 'stream': true,
                      }
                    : {
                        'model': model,
                        'messages': await _chatCompletionMessages(messages),
                        if (onDelta != null) 'stream': true,
                      },
              ),
            );
            final response = await request.close();
            cancelToken?.throwIfCancelled();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              final body = await utf8.decoder.bind(response).join();
              final json = _decodeJson(body, response.statusCode);
              final endpointError = HttpException(
                '${_errorMessage(json) ?? 'AI 接口调用失败'}'
                '（HTTP ${response.statusCode}）',
                uri: endpoint.uri,
              );
              lastError = _preferEndpointError(lastError, endpointError);
              continue;
            }
            return await _readReplyResponse(
              response,
              fallbackModel: model,
              onDelta: onDelta,
              onReasoningDelta: onReasoningDelta,
            );
          } on Object catch (error) {
            cancelToken?.throwIfCancelled();
            lastError = _preferEndpointError(lastError, error);
          }
        }
        if (attempt == 2 || !_isTransientAiError(lastError)) break;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
      throw StateError('AI 对话调用失败：${lastError ?? '未知错误'}');
    } finally {
      cancelToken?.detach(client);
      client.close(force: true);
    }
  }

  Future<AiChatReply> _sendAnthropic({
    required String providerBase,
    required String providerKey,
    required String model,
    required List<AiChatMessage> messages,
    AiChatCancelToken? cancelToken,
    void Function(String delta)? onDelta,
    void Function(String delta)? onReasoningDelta,
  }) async {
    final base = providerBase.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      base.endsWith('/v1') ? '$base/messages' : '$base/v1/messages',
    );
    final converted = await _anthropicMessages(messages);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(minutes: 3);
    cancelToken?.attach(client);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set('x-api-key', providerKey);
      request.headers.set('anthropic-version', '2023-06-01');
      request.headers.set(
        HttpHeaders.acceptHeader,
        onDelta == null ? 'application/json' : 'text/event-stream',
      );
      request.write(
        jsonEncode({
          'model': model,
          'max_tokens': 8192,
          if (converted.system.isNotEmpty) 'system': converted.system,
          'messages': converted.messages,
          if (onDelta != null) 'stream': true,
        }),
      );
      final response = await request.close();
      cancelToken?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decoder.bind(response).join();
        Map<String, dynamic> json;
        try {
          json = (jsonDecode(body) as Map).cast<String, dynamic>();
        } on Object {
          throw HttpException(
            'Anthropic 返回 HTTP ${response.statusCode}',
            uri: uri,
          );
        }
        throw HttpException(
          _errorMessage(json) ?? 'Anthropic 返回 HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      if (onDelta == null) {
        final body = await utf8.decoder.bind(response).join();
        final json = _decodeJson(body, response.statusCode);
        final parsed = _anthropicContent(json);
        if (parsed.text.isEmpty) throw const FormatException('Claude 没有返回文本内容');
        if (parsed.reasoning.isNotEmpty) {
          onReasoningDelta?.call(parsed.reasoning);
        }
        onDelta?.call(parsed.text);
        final usage = _anthropicUsage(json);
        return AiChatReply(
          model: json['model']?.toString() ?? model,
          content: parsed.text,
          reasoning: parsed.reasoning,
          inputTokens: usage.input,
          outputTokens: usage.output,
          totalTokens: usage.input + usage.output,
        );
      }
      final text = StringBuffer();
      final reasoning = StringBuffer();
      var actualModel = model;
      var inputTokens = 0;
      var outputTokens = 0;
      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        Map<String, dynamic> event;
        try {
          event = (jsonDecode(data) as Map).cast<String, dynamic>();
        } on Object {
          continue;
        }
        if (event['type'] == 'error') {
          throw StateError(_errorMessage(event) ?? 'Anthropic 流式响应失败');
        }
        final message = event['message'];
        if (message is Map) {
          actualModel = message['model']?.toString() ?? actualModel;
          final usage = _anthropicUsage(message.cast<String, dynamic>());
          if (usage.input > 0) inputTokens = usage.input;
          if (usage.output > 0) outputTokens = usage.output;
        }
        final usage = _anthropicUsage(event);
        if (usage.input > 0) inputTokens = usage.input;
        if (usage.output > 0) outputTokens = usage.output;
        final delta = event['delta'];
        if (delta is! Map) continue;
        final type = delta['type']?.toString() ?? '';
        final value =
            delta['text']?.toString() ?? delta['thinking']?.toString() ?? '';
        if (value.isEmpty) continue;
        if (type.contains('thinking')) {
          reasoning.write(value);
          onReasoningDelta?.call(value);
        } else {
          text.write(value);
          onDelta(value);
        }
      }
      if (text.isEmpty) throw const FormatException('Claude 没有返回文本内容');
      return AiChatReply(
        model: actualModel,
        content: text.toString(),
        reasoning: reasoning.toString(),
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: inputTokens + outputTokens,
      );
    } finally {
      cancelToken?.detach(client);
      client.close(force: true);
    }
  }

  Future<AiChatReply> _sendGemini({
    required String providerBase,
    required String providerKey,
    required String model,
    required List<AiChatMessage> messages,
    AiChatCancelToken? cancelToken,
    void Function(String delta)? onDelta,
    void Function(String delta)? onReasoningDelta,
  }) async {
    var base = providerBase.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!base.endsWith('/v1beta')) base = '$base/v1beta';
    final modelId = model.replaceFirst(RegExp(r'^models/'), '');
    final method = onDelta == null
        ? 'generateContent'
        : 'streamGenerateContent';
    final uri = Uri.parse(
      '$base/models/${Uri.encodeComponent(modelId)}:$method'
      '?${onDelta == null ? '' : 'alt=sse&'}key=${Uri.encodeQueryComponent(providerKey)}',
    );
    final converted = await _geminiMessages(messages);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(minutes: 3);
    cancelToken?.attach(client);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.acceptHeader,
        onDelta == null ? 'application/json' : 'text/event-stream',
      );
      request.write(
        jsonEncode({
          if (converted.system.isNotEmpty)
            'systemInstruction': {
              'parts': [
                {'text': converted.system},
              ],
            },
          'contents': converted.contents,
        }),
      );
      final response = await request.close();
      cancelToken?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decoder.bind(response).join();
        try {
          final json = (jsonDecode(body) as Map).cast<String, dynamic>();
          throw HttpException(
            _errorMessage(json) ?? 'Gemini 返回 HTTP ${response.statusCode}',
            uri: uri,
          );
        } on FormatException {
          throw HttpException(
            'Gemini 返回 HTTP ${response.statusCode}',
            uri: uri,
          );
        }
      }
      if (onDelta == null) {
        final json = _decodeJson(
          await utf8.decoder.bind(response).join(),
          response.statusCode,
        );
        final parsed = _geminiContent(json);
        if (parsed.text.isEmpty) throw const FormatException('Gemini 没有返回文本内容');
        if (parsed.reasoning.isNotEmpty) {
          onReasoningDelta?.call(parsed.reasoning);
        }
        final usage = _geminiUsage(json);
        return AiChatReply(
          model: modelId,
          content: parsed.text,
          reasoning: parsed.reasoning,
          inputTokens: usage.input,
          outputTokens: usage.output,
          totalTokens: usage.total,
        );
      }
      final text = StringBuffer();
      final reasoning = StringBuffer();
      var inputTokens = 0;
      var outputTokens = 0;
      var totalTokens = 0;
      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        Map<String, dynamic> event;
        try {
          event = (jsonDecode(data) as Map).cast<String, dynamic>();
        } on Object {
          continue;
        }
        final parsed = _geminiContent(event);
        if (parsed.reasoning.isNotEmpty) {
          reasoning.write(parsed.reasoning);
          onReasoningDelta?.call(parsed.reasoning);
        }
        if (parsed.text.isNotEmpty) {
          text.write(parsed.text);
          onDelta(parsed.text);
        }
        final usage = _geminiUsage(event);
        if (usage.input > 0) inputTokens = usage.input;
        if (usage.output > 0) outputTokens = usage.output;
        if (usage.total > 0) totalTokens = usage.total;
      }
      if (text.isEmpty) throw const FormatException('Gemini 没有返回文本内容');
      return AiChatReply(
        model: modelId,
        content: text.toString(),
        reasoning: reasoning.toString(),
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: totalTokens > 0 ? totalTokens : inputTokens + outputTokens,
      );
    } finally {
      cancelToken?.detach(client);
      client.close(force: true);
    }
  }

  static Future<({String system, List<Map<String, Object?>> messages})>
  _anthropicMessages(List<AiChatMessage> messages) async {
    final system = messages
        .where((message) => message.role == 'system')
        .map((message) => message.content)
        .join('\n\n');
    final result = <Map<String, Object?>>[];
    for (final message in messages.where(
      (message) => message.role != 'system',
    )) {
      final attachment = message.attachment;
      Object content = message.content;
      if (attachment != null && message.role != 'assistant') {
        if (attachment.isImage) {
          final file = File(attachment.path);
          final bytes = await file.readAsBytes();
          content = [
            {'type': 'text', 'text': message.content},
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': attachment.mimeType,
                'data': base64Encode(bytes),
              },
            },
          ];
        } else {
          final extracted = await AiAttachmentReader.extractText(attachment);
          if (extracted == null) {
            throw FormatException('Claude 直连接口无法读取 ${attachment.name}');
          }
          content = '${message.content}\n\n附件 ${attachment.name}：\n$extracted';
        }
      }
      result.add({
        'role': message.role == 'assistant' ? 'assistant' : 'user',
        'content': content,
      });
    }
    return (system: system, messages: result);
  }

  static Future<({String system, List<Map<String, Object?>> contents})>
  _geminiMessages(List<AiChatMessage> messages) async {
    final system = messages
        .where((message) => message.role == 'system')
        .map((message) => message.content)
        .join('\n\n');
    final result = <Map<String, Object?>>[];
    for (final message in messages.where(
      (message) => message.role != 'system',
    )) {
      final parts = <Map<String, Object?>>[
        {'text': message.content},
      ];
      final attachment = message.attachment;
      if (attachment != null && message.role != 'assistant') {
        if (attachment.isImage) {
          parts.add({
            'inlineData': {
              'mimeType': attachment.mimeType,
              'data': base64Encode(await File(attachment.path).readAsBytes()),
            },
          });
        } else {
          final extracted = await AiAttachmentReader.extractText(attachment);
          if (extracted == null) {
            throw FormatException('Gemini 直连接口无法读取 ${attachment.name}');
          }
          parts.add({'text': '附件 ${attachment.name}：\n$extracted'});
        }
      }
      result.add({
        'role': message.role == 'assistant' ? 'model' : 'user',
        'parts': parts,
      });
    }
    return (system: system, contents: result);
  }

  static ({String text, String reasoning}) _anthropicContent(
    Map<String, dynamic> json,
  ) {
    final text = StringBuffer();
    final reasoning = StringBuffer();
    for (final item
        in (json['content'] as List? ?? const []).whereType<Map>()) {
      final value =
          item['text']?.toString() ?? item['thinking']?.toString() ?? '';
      if (item['type']?.toString().contains('thinking') == true) {
        reasoning.write(value);
      } else {
        text.write(value);
      }
    }
    return (text: text.toString(), reasoning: reasoning.toString());
  }

  static ({int input, int output}) _anthropicUsage(Map<String, dynamic> json) {
    final usage = json['usage'] is Map ? json['usage'] as Map : const {};
    return (
      input: (usage['input_tokens'] as num?)?.toInt() ?? 0,
      output: (usage['output_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  static ({String text, String reasoning}) _geminiContent(
    Map<String, dynamic> json,
  ) {
    final text = StringBuffer();
    final reasoning = StringBuffer();
    for (final candidate
        in (json['candidates'] as List? ?? const []).whereType<Map>()) {
      final content = candidate['content'];
      if (content is! Map) continue;
      for (final part
          in (content['parts'] as List? ?? const []).whereType<Map>()) {
        final value = part['text']?.toString() ?? '';
        if (part['thought'] == true) {
          reasoning.write(value);
        } else {
          text.write(value);
        }
      }
    }
    return (text: text.toString(), reasoning: reasoning.toString());
  }

  static ({int input, int output, int total}) _geminiUsage(
    Map<String, dynamic> json,
  ) {
    final usage = json['usageMetadata'] is Map
        ? json['usageMetadata'] as Map
        : const {};
    return (
      input: (usage['promptTokenCount'] as num?)?.toInt() ?? 0,
      output: (usage['candidatesTokenCount'] as num?)?.toInt() ?? 0,
      total: (usage['totalTokenCount'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<List<Map<String, Object?>>> _gatewayMessages(
    List<AiChatMessage> messages,
  ) async {
    final result = <Map<String, Object?>>[];
    for (final message in messages) {
      final attachment = message.attachment;
      if (attachment == null || message.role == 'assistant') {
        result.add({'role': message.role, 'content': message.content});
        continue;
      }
      if (!attachment.isImage) {
        final extracted = await AiAttachmentReader.extractText(attachment);
        if (extracted != null) {
          result.add({
            'role': message.role,
            'content':
                '${message.content}\n\n已读取附件 ${attachment.name}：\n$extracted',
          });
          continue;
        }
      }
      result.add({
        'role': message.role,
        'content': message.content,
        'attachment': await _attachmentPayload(attachment),
      });
    }
    return result;
  }

  static Future<List<Map<String, Object?>>> _responsesMessages(
    List<AiChatMessage> messages,
  ) async {
    final result = <Map<String, Object?>>[];
    for (final message in messages) {
      final content = <Map<String, Object?>>[
        {
          'type': message.role == 'assistant' ? 'output_text' : 'input_text',
          'text': message.content,
        },
      ];
      final attachment = message.attachment;
      if (attachment != null && message.role != 'assistant') {
        final payload = await _attachmentPayload(attachment);
        content.add(
          attachment.isImage
              ? {'type': 'input_image', 'image_url': payload['data_url']}
              : {
                  'type': 'input_file',
                  'filename': attachment.name,
                  'file_data': payload['data_url'],
                },
        );
      }
      result.add({'role': message.role, 'content': content});
    }
    return result;
  }

  static Future<List<Map<String, Object?>>> _chatCompletionMessages(
    List<AiChatMessage> messages,
  ) async {
    final result = <Map<String, Object?>>[];
    for (final message in messages) {
      final attachment = message.attachment;
      if (attachment == null || message.role == 'assistant') {
        result.add({'role': message.role, 'content': message.content});
        continue;
      }
      if (!attachment.isImage) {
        final text = await AiAttachmentReader.extractText(attachment);
        if (text != null) {
          result.add({
            'role': message.role,
            'content': '${message.content}\n\n已读取附件 ${attachment.name}：\n$text',
          });
          continue;
        }
        throw FormatException(
          '模型的 Chat Completions 接口不支持 ${attachment.name}；请改用支持 Responses 文件输入的模型',
        );
      }
      final payload = await _attachmentPayload(attachment);
      result.add({
        'role': message.role,
        'content': [
          {'type': 'text', 'text': message.content},
          {
            'type': 'image_url',
            'image_url': {'url': payload['data_url']},
          },
        ],
      });
    }
    return result;
  }

  static Future<Map<String, Object?>> _attachmentPayload(
    AiChatAttachment attachment,
  ) async {
    final file = File(attachment.path);
    if (!await file.exists()) throw StateError('附件已从本机删除：${attachment.name}');
    final bytes = await file.readAsBytes();
    if (bytes.length > AiChatStore.maxAttachmentBytes) {
      throw const FormatException('单个附件不能超过 20MB');
    }
    return {
      'name': attachment.name,
      'mime_type': attachment.mimeType,
      'data_url': 'data:${attachment.mimeType};base64,${base64Encode(bytes)}',
    };
  }

  static Future<AiChatReply> _readReplyResponse(
    HttpClientResponse response, {
    required String fallbackModel,
    void Function(String delta)? onDelta,
    void Function(String delta)? onReasoningDelta,
  }) async {
    final mediaType =
        response.headers.contentType?.mimeType.toLowerCase() ?? '';
    if (mediaType != 'text/event-stream') {
      final body = await utf8.decoder.bind(response).join();
      final json = _decodeJson(body, response.statusCode);
      final content = json['content']?.toString().isNotEmpty == true
          ? json['content'].toString()
          : _outputText(json);
      if (content.isEmpty) {
        throw const FormatException('模型没有返回文本内容');
      }
      onDelta?.call(content);
      final usage = _usageFrom(json);
      final reasoning = _reasoningText(json);
      if (reasoning.isNotEmpty) onReasoningDelta?.call(reasoning);
      return AiChatReply(
        model: json['model']?.toString() ?? fallbackModel,
        content: content,
        inputTokens: usage.input,
        outputTokens: usage.output,
        totalTokens: usage.total,
        reasoning: reasoning,
      );
    }

    final output = StringBuffer();
    final reasoningOutput = StringBuffer();
    var model = fallbackModel;
    var inputTokens = 0;
    var outputTokens = 0;
    var totalTokens = 0;
    await for (final line
        in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trimLeft();
      if (data.isEmpty || data == '[DONE]') continue;
      Map<String, dynamic> event;
      try {
        event = (jsonDecode(data) as Map).cast<String, dynamic>();
      } on Object {
        continue;
      }
      final error = event['error'];
      if (error != null) {
        final message = error is Map
            ? error['message']?.toString() ?? error.toString()
            : error.toString();
        throw StateError('AI 流式响应失败：$message');
      }
      final responseValue = event['response'];
      final responseMap = responseValue is Map
          ? responseValue.cast<String, dynamic>()
          : const <String, dynamic>{};
      model =
          event['model']?.toString() ??
          responseMap['model']?.toString() ??
          model;
      final usageSource = responseMap.isNotEmpty ? responseMap : event;
      final usage = _usageFrom(usageSource);
      if (usage.input > 0) inputTokens = usage.input;
      if (usage.output > 0) outputTokens = usage.output;
      if (usage.total > 0) totalTokens = usage.total;
      final delta = _streamDelta(event);
      final reasoningDelta = _streamReasoningDelta(event);
      if (reasoningDelta.isNotEmpty) {
        reasoningOutput.write(reasoningDelta);
        onReasoningDelta?.call(reasoningDelta);
      }
      if (delta.isNotEmpty) {
        output.write(delta);
        onDelta?.call(delta);
      } else if (output.isEmpty) {
        final completedText = _outputText(
          responseMap.isNotEmpty ? responseMap : event,
        );
        if (completedText.isNotEmpty) {
          output.write(completedText);
          onDelta?.call(completedText);
        }
      }
    }
    final content = output.toString();
    if (content.isEmpty) throw const FormatException('模型没有返回文本内容');
    return AiChatReply(
      model: model,
      content: content,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: totalTokens,
      reasoning: reasoningOutput.toString(),
    );
  }

  static String _streamDelta(Map<String, dynamic> event) {
    final eventType = event['type']?.toString() ?? '';
    if (eventType.contains('reasoning') || eventType.contains('thinking')) {
      return '';
    }
    final direct = event['delta'];
    if (direct is String) return direct;
    if (direct is Map && direct['text'] is String) {
      return direct['text'] as String;
    }
    final choices = event['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final choice = choices.first as Map;
      final choiceDelta = choice['delta'];
      if (choiceDelta is Map) {
        final content = choiceDelta['content'];
        if (content is String) return content;
        if (content is List) {
          return content
              .whereType<Map>()
              .map((item) => item['text']?.toString() ?? '')
              .join();
        }
      }
      final text = choice['text'];
      if (text is String) return text;
    }
    return '';
  }

  static String _streamReasoningDelta(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';
    if (type.contains('reasoning') && type.endsWith('.delta')) {
      final delta = event['delta'];
      if (delta is String) return delta;
      if (delta is Map) return delta['text']?.toString() ?? '';
    }
    final direct = event['reasoning_content'] ?? event['thinking'];
    if (direct is String) return direct;
    final choices = event['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final delta = (choices.first as Map)['delta'];
      if (delta is Map) {
        final value =
            delta['reasoning_content'] ??
            delta['reasoning'] ??
            delta['thinking'];
        if (value is String) return value;
      }
    }
    return '';
  }

  static String _reasoningText(Map<String, dynamic> json) {
    final direct =
        json['reasoning_content'] ?? json['reasoning'] ?? json['thinking'];
    if (direct is String) return direct;
    if (direct is Map) {
      return direct['summary']?.toString() ?? direct['text']?.toString() ?? '';
    }
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final message = (choices.first as Map)['message'];
      if (message is Map) {
        final value =
            message['reasoning_content'] ??
            message['reasoning'] ??
            message['thinking'];
        if (value is String) return value;
      }
    }
    final output = json['output'];
    if (output is List) {
      return output
          .whereType<Map>()
          .where(
            (item) => item['type']?.toString().contains('reasoning') == true,
          )
          .map((item) {
            final summary = item['summary'];
            if (summary is List) {
              return summary
                  .whereType<Map>()
                  .map((value) => value['text']?.toString() ?? '')
                  .join();
            }
            return item['text']?.toString() ?? '';
          })
          .join();
    }
    return '';
  }

  static Map<String, dynamic> _decodeJson(String body, int statusCode) {
    try {
      return (jsonDecode(body) as Map).cast<String, dynamic>();
    } on Object {
      throw HttpException('AI 服务返回了无法解析的内容（HTTP $statusCode）');
    }
  }

  static String? _activeModelFromResponse(Object? decoded, Object? values) {
    if (decoded is Map) {
      for (final key in const [
        'active_model',
        'activeModel',
        'current_model',
        'currentModel',
        'default_model',
        'defaultModel',
      ]) {
        final value = decoded[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
    }
    if (values is List) {
      for (final value in values.whereType<Map>()) {
        final active =
            value['active'] == true ||
            value['is_active'] == true ||
            value['default'] == true ||
            value['is_default'] == true ||
            value['current'] == true;
        if (!active) continue;
        final id =
            value['id']?.toString().trim() ??
            value['model_id']?.toString().trim() ??
            value['name']?.toString().trim() ??
            '';
        if (id.isNotEmpty) return id;
      }
    }
    return null;
  }

  static String _outputText(Map<String, dynamic> json) {
    final direct = json['output_text'];
    if (direct is String && direct.isNotEmpty) return direct;
    final choices = json['choices'] as List? ?? const [];
    if (choices.isNotEmpty && choices.first is Map) {
      final message = (choices.first as Map)['message'];
      final content = message is Map ? message['content'] : null;
      if (content is String) return content;
      if (content is List) {
        return content
            .whereType<Map>()
            .map((item) => item['text']?.toString() ?? '')
            .join();
      }
    }
    final output = json['output'] as List? ?? const [];
    return output
        .whereType<Map>()
        .expand(
          (item) => (item['content'] as List? ?? const []).whereType<Map>(),
        )
        .map((item) => item['text']?.toString() ?? '')
        .join();
  }

  static String? _errorMessage(Map<String, dynamic> json) {
    final error = json['error'];
    if (error is Map) return error['message']?.toString();
    return error?.toString() ?? json['detail']?.toString();
  }

  static ({int input, int output, int total}) _usageFrom(
    Map<String, dynamic> json,
  ) {
    final raw = json['raw'];
    final source = json['usage'] is Map
        ? json['usage'] as Map
        : raw is Map && raw['usage'] is Map
        ? raw['usage'] as Map
        : const <String, Object?>{};
    int valueOf(List<String> keys) {
      for (final key in keys) {
        final value = source[key];
        if (value is num) return value.toInt();
        final parsed = int.tryParse(value?.toString() ?? '');
        if (parsed != null) return parsed;
      }
      return 0;
    }

    final input = valueOf(const ['input_tokens', 'prompt_tokens']);
    final output = valueOf(const ['output_tokens', 'completion_tokens']);
    final reportedTotal = valueOf(const ['total_tokens']);
    return (
      input: input,
      output: output,
      total: reportedTotal > 0 ? reportedTotal : input + output,
    );
  }

  static String _normalizedBase(String value) {
    var base = value.trim().replaceFirst(RegExp(r'/+$'), '');
    for (final suffix in const ['/chat/completions', '/responses', '/models']) {
      if (base.endsWith(suffix)) {
        base = base.substring(0, base.length - suffix.length);
      }
    }
    return base;
  }

  static List<Uri> _modelEndpoints(String value) {
    final base = _normalizedBase(value);
    final uri = Uri.parse(base);
    return uri.path.endsWith('/v1')
        ? [Uri.parse('$base/models')]
        : [Uri.parse('$base/models'), Uri.parse('$base/v1/models')];
  }

  static AiProviderProtocol _effectiveProtocol(AppSettings settings) {
    if (settings.aiProviderProtocol != AiProviderProtocol.auto) {
      return settings.aiProviderProtocol;
    }
    final uri = Uri.tryParse(settings.aiProviderBaseUrl.trim());
    final host = uri?.host.toLowerCase() ?? '';
    final path = uri?.path.toLowerCase() ?? '';
    if (path.contains('/openai')) return AiProviderProtocol.openAiCompatible;
    if (host.contains('anthropic.com')) return AiProviderProtocol.anthropic;
    if (host.contains('generativelanguage.googleapis.com')) {
      return AiProviderProtocol.gemini;
    }
    return AiProviderProtocol.openAiCompatible;
  }

  static List<Uri> _providerModelEndpoints(
    String value,
    String apiKey,
    AiProviderProtocol protocol,
  ) {
    final base = value.trim().replaceFirst(RegExp(r'/+$'), '');
    return switch (protocol) {
      AiProviderProtocol.anthropic => [
        Uri.parse(base.endsWith('/v1') ? '$base/models' : '$base/v1/models'),
      ],
      AiProviderProtocol.gemini => [
        Uri.parse(
          '${base.endsWith('/v1beta') ? base : '$base/v1beta'}/models'
          '?key=${Uri.encodeQueryComponent(apiKey)}',
        ),
      ],
      _ => _modelEndpoints(value),
    };
  }

  static void _applyProviderAuth(
    HttpClientRequest request,
    String apiKey,
    AiProviderProtocol protocol,
  ) {
    if (protocol == AiProviderProtocol.anthropic) {
      request.headers.set('x-api-key', apiKey);
      request.headers.set('anthropic-version', '2023-06-01');
      return;
    }
    if (protocol != AiProviderProtocol.gemini) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    }
  }

  static List<Uri> _balanceEndpoints(String providerBase) {
    final base = _normalizedBase(providerBase);
    final uri = Uri.tryParse(base);
    if (uri == null || !uri.hasAuthority) return const [];
    final roots = <String>{base};
    if (base.endsWith('/v1')) roots.add(base.substring(0, base.length - 3));
    final result = <Uri>[];
    for (final root in roots) {
      for (final path in const [
        '/dashboard/billing/credit_grants',
        '/v1/dashboard/billing/credit_grants',
        '/balance',
        '/v1/balance',
        '/user/balance',
      ]) {
        result.add(Uri.parse('${root.replaceFirst(RegExp(r'/$'), '')}$path'));
      }
    }
    return result;
  }

  static double? _firstDouble(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  static List<({Uri uri, bool responses})> _chatEndpoints(
    String base,
    Uri uri,
    String model,
  ) {
    final responses = uri.path.endsWith('/v1')
        ? [(uri: Uri.parse('$base/responses'), responses: true)]
        : [
            (uri: Uri.parse('$base/responses'), responses: true),
            (uri: Uri.parse('$base/v1/responses'), responses: true),
          ];
    final completions = uri.path.endsWith('/v1')
        ? [(uri: Uri.parse('$base/chat/completions'), responses: false)]
        : [
            (uri: Uri.parse('$base/chat/completions'), responses: false),
            (uri: Uri.parse('$base/v1/chat/completions'), responses: false),
          ];
    return runtimeProfileForModel(model).preferResponsesApi
        ? [...responses, ...completions]
        : [...completions, ...responses];
  }

  static bool _isLocalHost(String host) =>
      const {'127.0.0.1', 'localhost', '10.0.2.2'}.contains(host);

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
}
