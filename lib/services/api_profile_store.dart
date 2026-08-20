import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'secure_settings_store.dart';

class ApiProfile {
  const ApiProfile({
    required this.id,
    required this.name,
    required this.providerBaseUrl,
    required this.apiKey,
    required this.collectionBaseUrl,
    required this.model,
    required this.protocol,
    required this.updatedAt,
    this.appServerBaseUrl = '',
  });

  final String id;
  final String name;
  final String appServerBaseUrl;
  final String providerBaseUrl;
  final String apiKey;
  final String collectionBaseUrl;
  final String model;
  final AiProviderProtocol protocol;
  final DateTime updatedAt;

  ApiProfile copyWith({
    String? id,
    String? name,
    String? appServerBaseUrl,
    String? providerBaseUrl,
    String? apiKey,
    String? collectionBaseUrl,
    String? model,
    AiProviderProtocol? protocol,
    DateTime? updatedAt,
  }) => ApiProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    appServerBaseUrl: appServerBaseUrl ?? this.appServerBaseUrl,
    providerBaseUrl: providerBaseUrl ?? this.providerBaseUrl,
    apiKey: apiKey ?? this.apiKey,
    collectionBaseUrl: collectionBaseUrl ?? this.collectionBaseUrl,
    model: model ?? this.model,
    protocol: protocol ?? this.protocol,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson({required bool includeApiKey}) => {
    'id': id,
    'name': name,
    'appServerBaseUrl': appServerBaseUrl,
    'providerBaseUrl': providerBaseUrl,
    if (includeApiKey) 'apiKey': apiKey,
    'collectionBaseUrl': collectionBaseUrl,
    'model': model,
    'chatModel': model,
    'imageModel': model,
    'videoModel': model,
    'protocol': protocol.name,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ApiProfile.fromJson(Map<String, dynamic> json, {String apiKey = ''}) {
    final provider = AppSettings.normalizeAiProviderBaseUrl(
      json['providerBaseUrl'] as String? ?? json['baseUrl'] as String? ?? '',
    );
    final collection = AppSettings.normalizeAiProviderBaseUrl(
      json['collectionBaseUrl'] as String? ?? provider,
    );
    final protocolName = json['protocol'] as String? ?? '';
    return ApiProfile(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '导入的 API').trim(),
      appServerBaseUrl: (json['appServerBaseUrl'] as String? ?? '').trim(),
      providerBaseUrl: provider,
      apiKey: (json['apiKey'] as String? ?? apiKey).trim(),
      collectionBaseUrl: collection,
      model: AppSettings.normalizeAiModelId(
        json['chatModel'] as String? ??
            json['model'] as String? ??
            json['imageModel'] as String? ??
            json['videoModel'] as String? ??
            'gpt-5.6-sol',
      ),
      protocol: AiProviderProtocol.values.firstWhere(
        (value) => value.name == protocolName,
        orElse: () => AiProviderProtocol.auto,
      ),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ApiProfileStore extends ChangeNotifier {
  ApiProfileStore({
    AppSettings? settings,
    SecureSettingsStore secureStore = const SecureSettingsStore(),
  }) : _settings = settings ?? AppSettings.instance,
       _secureStore = secureStore;

  static final instance = ApiProfileStore();
  static const _profilesKey = 'api_profile_metadata_v1';
  static const _activeProfileKey = 'api_profile_active_id_v1';
  static const _securePrefix = 'api_profile_secret_v1_';
  static const bundleSchema = 'bead-ai-api-profiles';

  final AppSettings _settings;
  final SecureSettingsStore _secureStore;
  final List<ApiProfile> _profiles = [];
  Future<void>? _initializing;
  String? _activeProfileId;

  List<ApiProfile> get profiles => List.unmodifiable(_profiles);
  String? get activeProfileId => _activeProfileId;

  Future<void> initialize() => _initializing ??= _load();

  Future<void> _load() async {
    await _settings.initialize();
    final prefs = await SharedPreferences.getInstance();
    _activeProfileId = prefs.getString(_activeProfileKey);
    _profiles.clear();
    final source = prefs.getString(_profilesKey);
    if (source != null && source.isNotEmpty) {
      try {
        final list = jsonDecode(source) as List;
        for (final raw in list) {
          final metadata = (raw as Map).cast<String, dynamic>();
          final id = (metadata['id'] as String? ?? '').trim();
          if (id.isEmpty) continue;
          String key = '';
          try {
            key = await _secureStore.read('$_securePrefix$id') ?? '';
          } on Object catch (error) {
            debugPrint('Unable to read API profile secret $id: $error');
          }
          _profiles.add(ApiProfile.fromJson(metadata, apiKey: key));
        }
      } on Object catch (error) {
        debugPrint('Unable to load API profiles: $error');
      }
    }
    if (!_profiles.any((profile) => profile.id == _activeProfileId)) {
      _activeProfileId = null;
      await prefs.remove(_activeProfileKey);
    }
    _sort();
    notifyListeners();
  }

  ApiProfile currentAsProfile({String name = '当前 API 配置'}) => ApiProfile(
    id: _newId(),
    name: name.trim().isEmpty ? '当前 API 配置' : name.trim(),
    appServerBaseUrl: _settings.aiProxyBaseUrl,
    providerBaseUrl: _settings.aiProviderBaseUrl,
    apiKey: _settings.aiProviderKey,
    collectionBaseUrl: _settings.collectionBaseUrl,
    model: _settings.aiChatModel,
    protocol: _settings.aiProviderProtocol,
    updatedAt: DateTime.now(),
  );

  Future<ApiProfile> saveCurrent({required String name}) async {
    final profile = currentAsProfile(name: name);
    return save(profile);
  }

  Future<ApiProfile> save(ApiProfile profile) async {
    await initialize();
    final normalized = profile.copyWith(
      id: profile.id.trim().isEmpty ? _newId() : profile.id.trim(),
      name: profile.name.trim().isEmpty ? '未命名 API' : profile.name.trim(),
      appServerBaseUrl: profile.appServerBaseUrl.trim(),
      providerBaseUrl: AppSettings.normalizeAiProviderBaseUrl(
        profile.providerBaseUrl,
      ),
      apiKey: profile.apiKey.trim(),
      collectionBaseUrl: AppSettings.normalizeAiProviderBaseUrl(
        profile.collectionBaseUrl.trim().isEmpty
            ? profile.providerBaseUrl
            : profile.collectionBaseUrl,
      ),
      model: AppSettings.normalizeAiModelId(profile.model),
      updatedAt: DateTime.now(),
    );
    if (normalized.providerBaseUrl.isEmpty &&
        normalized.appServerBaseUrl.isEmpty) {
      throw const FormatException('APP 服务端地址和 API 中转地址不能同时为空');
    }
    if (normalized.apiKey.isEmpty && normalized.appServerBaseUrl.isEmpty) {
      throw const FormatException('直连中转 API 时必须填写 API 密钥');
    }
    await _writeSecret(normalized.id, normalized.apiKey);
    final index = _profiles.indexWhere((value) => value.id == normalized.id);
    if (index < 0) {
      _profiles.add(normalized);
    } else {
      _profiles[index] = normalized;
    }
    _sort();
    await _persistMetadata();
    notifyListeners();
    return normalized;
  }

  Future<void> activate(ApiProfile profile) async {
    await initialize();
    final saved = _profiles
        .where((value) => value.id == profile.id)
        .firstOrNull;
    if (saved == null) throw StateError('这个 API 配置已不存在');
    await _settings.setAiProxyBaseUrl(saved.appServerBaseUrl);
    await _settings.setAiProviderAndCollectionBaseUrl(saved.providerBaseUrl);
    await _settings.setCollectionBaseUrl(saved.collectionBaseUrl);
    await _settings.setAiProviderKey(saved.apiKey);
    await _settings.setAiModels(saved.model);
    await _settings.setAiProviderProtocol(saved.protocol);
    _activeProfileId = saved.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProfileKey, saved.id);
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await initialize();
    if (!_profiles.any((value) => value.id == id)) return;
    _profiles.removeWhere((value) => value.id == id);
    try {
      await _secureStore.delete('$_securePrefix$id');
    } on Object catch (error) {
      debugPrint('Unable to delete API profile secret $id: $error');
    }
    if (_activeProfileId == id) _activeProfileId = null;
    final prefs = await SharedPreferences.getInstance();
    if (_activeProfileId == null) await prefs.remove(_activeProfileKey);
    await _persistMetadata();
    notifyListeners();
  }

  Uint8List exportBundle({Iterable<String>? ids}) {
    final selected = ids?.toSet();
    final values = selected == null
        ? _profiles
        : _profiles.where((profile) => selected.contains(profile.id)).toList();
    final payload = _bundlePayload(values);
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
  }

  String shareText(ApiProfile profile) =>
      const JsonEncoder.withIndent('  ').convert(_bundlePayload([profile]));

  Map<String, Object?> _bundlePayload(Iterable<ApiProfile> values) => {
    'schema': bundleSchema,
    'version': 2,
    'type': 'shareable-api-configuration',
    'exportedAt': DateTime.now().toIso8601String(),
    'profiles': [
      for (final profile in values) profile.toJson(includeApiKey: true),
    ],
  };

  Future<int> importBundle(Uint8List bytes) async {
    await initialize();
    if (bytes.isEmpty) throw const FormatException('导入文件为空');
    final decoded = jsonDecode(utf8.decode(bytes));
    final List<dynamic> rawProfiles;
    if (decoded is Map && decoded['profiles'] is List) {
      final schema = decoded['schema'];
      if (schema != null && schema != bundleSchema) {
        throw const FormatException('不是拼豆 AI 的 API 配置文件');
      }
      rawProfiles = decoded['profiles'] as List;
    } else if (decoded is List) {
      rawProfiles = decoded;
    } else if (decoded is Map) {
      rawProfiles = [decoded];
    } else {
      throw const FormatException('API 配置文件格式无效');
    }
    var imported = 0;
    for (final raw in rawProfiles) {
      if (raw is! Map) continue;
      final parsed = ApiProfile.fromJson(raw.cast<String, dynamic>());
      final profile = parsed.copyWith(
        id: _newId(suffix: imported),
        name: _uniqueName(parsed.name),
      );
      await save(profile);
      imported++;
    }
    if (imported == 0) throw const FormatException('文件中没有有效的 API 配置');
    return imported;
  }

  Future<void> _writeSecret(String id, String value) async {
    if (value.isEmpty) {
      await _secureStore.delete('$_securePrefix$id');
    } else {
      await _secureStore.write('$_securePrefix$id', value);
    }
  }

  Future<void> _persistMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesKey,
      jsonEncode(
        _profiles
            .map((profile) => profile.toJson(includeApiKey: false))
            .toList(),
      ),
    );
  }

  String _uniqueName(String requested) {
    final base = requested.trim().isEmpty ? '导入的 API' : requested.trim();
    final names = _profiles.map((profile) => profile.name).toSet();
    if (!names.contains(base)) return base;
    var index = 2;
    while (names.contains('$base ($index)')) {
      index++;
    }
    return '$base ($index)';
  }

  String _newId({int suffix = 0}) =>
      '${DateTime.now().microsecondsSinceEpoch}_${_profiles.length}_$suffix';

  void _sort() => _profiles.sort(
    (left, right) => right.updatedAt.compareTo(left.updatedAt),
  );
}
