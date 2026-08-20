import 'dart:convert';

import 'app_settings.dart';

class ApiClipboardImportData {
  const ApiClipboardImportData({
    this.profileName,
    this.appServerBaseUrl,
    this.apiKey,
    this.providerBaseUrl,
    this.collectionBaseUrl,
    this.model,
    this.protocol,
  });

  final String? profileName;
  final String? appServerBaseUrl;
  final String? apiKey;
  final String? providerBaseUrl;
  final String? collectionBaseUrl;
  final String? model;
  final AiProviderProtocol? protocol;

  bool get hasValues =>
      appServerBaseUrl != null ||
      apiKey != null ||
      providerBaseUrl != null ||
      collectionBaseUrl != null ||
      model != null ||
      protocol != null;

  bool get canOfferAutomatically =>
      appServerBaseUrl != null ||
      model != null ||
      apiKey != null && (providerBaseUrl != null || collectionBaseUrl != null);
}

abstract final class ApiClipboardImportParser {
  static final RegExp _urlPattern = RegExp(
    r'''https?://[^\s\"'<>，。；;]+''',
    caseSensitive: false,
  );

  static ApiClipboardImportData parse(String source) {
    final text = source.trim();
    if (text.isEmpty) return const ApiClipboardImportData();
    final structured = _structuredConfiguration(text);
    if (structured != null && structured.hasValues) return structured;
    final lines = text.split(RegExp(r'[\r\n]+'));
    final urls = <String>[];
    String? appServer;
    String? provider;
    String? collection;
    String? key;
    String? model;
    AiProviderProtocol? protocol;

    for (final match in _urlPattern.allMatches(text)) {
      final value = _cleanUrl(match.group(0)!);
      if (_validHttpUrl(value) && !urls.contains(value)) urls.add(value);
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final lower = line.toLowerCase();
      final lineUrls = _urlPattern
          .allMatches(line)
          .map((match) => _cleanUrl(match.group(0)!))
          .where(_validHttpUrl)
          .toList(growable: false);
      if (lineUrls.isNotEmpty) {
        if (_containsAny(lower, const [
          'app 服务端',
          'app服务端',
          '应用服务端',
          'app server',
          'proxy server',
        ])) {
          appServer ??= lineUrls.first;
        } else if (_containsAny(lower, const [
          '原图库',
          '图库地址',
          'collection',
          'library',
          'original',
        ])) {
          collection ??= lineUrls.first;
        } else if (_containsAny(lower, const [
          '中转',
          'base url',
          'base_url',
          'api url',
          'api_url',
          'endpoint',
          'provider',
        ])) {
          provider ??= lineUrls.first;
        }
      }

      key ??= _keyFromLabeledLine(line);
      final candidateModel = _modelFromLabeledLine(line);
      if (candidateModel != null) model ??= candidateModel;
      protocol ??= _protocolFromLine(line);
    }

    final textWithoutUrls = text.replaceAll(_urlPattern, ' ');
    model ??= _standaloneModel(textWithoutUrls);
    key ??= _standaloneKey(text);
    provider ??= urls
        .where((value) => value != appServer && value != collection)
        .firstOrNull;
    collection ??= urls.length > 1 ? urls[1] : provider;
    if (collection == appServer) collection = provider;
    model = _canonicalModel(model);
    return ApiClipboardImportData(
      appServerBaseUrl: appServer,
      apiKey: key,
      providerBaseUrl: provider,
      collectionBaseUrl: collection,
      model: model,
      protocol: protocol,
    );
  }

  static ApiClipboardImportData? _structuredConfiguration(String source) {
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on Object {
      return null;
    }
    if (decoded is! Map) return null;
    Map<String, dynamic> values = decoded.cast<String, dynamic>();
    final profiles = values['profiles'];
    if (profiles is List && profiles.isNotEmpty && profiles.first is Map) {
      values = (profiles.first as Map).cast<String, dynamic>();
    }
    String? read(List<String> keys) {
      for (final key in keys) {
        final value = values[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    final appServer = _validatedUrl(
      read(const ['appServerBaseUrl', 'aiProxyBaseUrl', 'appServer']),
    );
    final provider = _validatedUrl(
      read(const ['providerBaseUrl', 'aiProviderBaseUrl', 'baseUrl']),
    );
    final collection = _validatedUrl(
      read(const ['collectionBaseUrl', 'collectionUrl', 'libraryBaseUrl']),
    );
    return ApiClipboardImportData(
      profileName: read(const ['name', 'profileName']),
      appServerBaseUrl: appServer,
      apiKey: read(const ['apiKey', 'key', 'token']),
      providerBaseUrl: provider,
      collectionBaseUrl: collection ?? provider,
      model: _canonicalModel(
        read(const [
          'chatModel',
          'model',
          'aiChatModel',
          'imageModel',
          'videoModel',
        ]),
      ),
      protocol: _protocolFromValue(read(const ['protocol', 'apiProtocol'])),
    );
  }

  static String? firstHttpUrl(String source) => _urlPattern
      .allMatches(source)
      .map((match) => _cleanUrl(match.group(0)!))
      .where(_validHttpUrl)
      .firstOrNull;

  static String? apiKey(String source) =>
      _keyFromLabeledLine(source.trim()) ?? _standaloneKey(source);

  static String? _keyFromLabeledLine(String line) {
    final match = RegExp(
      r'(?:api\s*(?:key|密钥)|密钥|token|令牌)\s*[:：=]\s*([^\s,，;；]+)',
      caseSensitive: false,
    ).firstMatch(line);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty || _validHttpUrl(value)) return null;
    return value;
  }

  static String? _standaloneKey(String text) {
    final known = RegExp(
      r'\b(?:sk|sess|key)-[A-Za-z0-9._-]{6,}\b|\bAIza[A-Za-z0-9_-]{16,}\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (known != null) return known.group(0);
    final lines = text
        .split(RegExp(r'[\s,，;；]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && !_validHttpUrl(value));
    for (final value in lines) {
      if (value.length >= 20 &&
          RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value) &&
          !_looksLikeModelId(value) &&
          RegExp(r'[A-Za-z]').hasMatch(value) &&
          RegExp(r'\d').hasMatch(value)) {
        return value;
      }
    }
    return null;
  }

  static String? _modelFromLabeledLine(String line) {
    final match = RegExp(
      r'(?:model|模型)\s*[:：=]\s*([A-Za-z0-9._/-]+)',
      caseSensitive: false,
    ).firstMatch(line);
    return match?.group(1)?.trim();
  }

  static AiProviderProtocol? _protocolFromLine(String line) {
    final match = RegExp(
      r'(?:protocol|协议)\s*[:：=]\s*([^\s,，;；]+)',
      caseSensitive: false,
    ).firstMatch(line);
    return _protocolFromValue(match?.group(1));
  }

  static AiProviderProtocol? _protocolFromValue(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.trim().toLowerCase();
    for (final protocol in AiProviderProtocol.values) {
      if (protocol.name.toLowerCase() == normalized) return protocol;
    }
    if (normalized.contains('anthropic') || normalized.contains('claude')) {
      return AiProviderProtocol.anthropic;
    }
    if (normalized.contains('gemini') || normalized.contains('google')) {
      return AiProviderProtocol.gemini;
    }
    if (normalized.contains('openai')) {
      return AiProviderProtocol.openAiCompatible;
    }
    if (normalized.contains('自动') || normalized == 'auto') {
      return AiProviderProtocol.auto;
    }
    return null;
  }

  static String? _standaloneModel(String text) {
    for (final match in RegExp(r'[A-Za-z0-9._/-]+').allMatches(text)) {
      final value = _cleanModelCandidate(match.group(0)!);
      if (value.isNotEmpty && _looksLikeModelId(value)) return value;
    }
    return null;
  }

  static String _cleanModelCandidate(String value) => value
      .replaceFirst(RegExp(r'^[._/-]+'), '')
      .replaceFirst(RegExp(r'[._/-]+$'), '');

  static bool _looksLikeModelId(String value) {
    if (_validHttpUrl(value)) return false;
    final leaf = value.toLowerCase().split('/').last;
    return RegExp(
      r'^(?:gpt(?:[-_.]?(?:\d|image))|chatgpt(?:$|[-_.])|o(?:1|3|4)(?:$|[-_.])|claude(?:$|[-_.])|qwen(?:$|[-_.]|\d)|glm(?:$|[-_.]|\d)|deepseek(?:$|[-_.])|kimi(?:$|[-_.])|moonshot(?:$|[-_.])|gemini(?:$|[-_.]|\d)|llama(?:$|[-_.]|\d)|mistral(?:$|[-_.])|grok(?:$|[-_.]|\d)|dall-e(?:$|[-_.])|sora(?:$|[-_.]|\d)|veo(?:$|[-_.]|\d)|kling(?:$|[-_.]))',
      caseSensitive: false,
    ).hasMatch(leaf);
  }

  static String? _canonicalModel(String? value) {
    if (value == null || value.isEmpty) return null;
    final compact = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return compact == 'gpt56sol' ? 'gpt-5.6-sol' : value;
  }

  static String _cleanUrl(String value) =>
      value.replaceFirst(RegExp(r'''[\]\[(){}、,，。.!！?？:：]+$'''), '');

  static String? _validatedUrl(String? value) {
    if (value == null) return null;
    final cleaned = _cleanUrl(value);
    return _validHttpUrl(cleaned) ? cleaned : null;
  }

  static bool _validHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static bool _containsAny(String value, List<String> needles) =>
      needles.any(value.contains);
}
