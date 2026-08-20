import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_settings_store.dart';
import 'click_sound_service.dart';

enum AiProviderProtocol {
  auto('自动检测（优先中转兼容）'),
  openAiCompatible('OpenAI 兼容协议'),
  anthropic('Anthropic Messages'),
  gemini('Google Gemini generateContent');

  const AiProviderProtocol(this.label);
  final String label;
}

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();
  static const defaultAiProviderBaseUrl = 'https://ciyuan.fast/v1';
  static const _legacyAiProviderHost = 'api.ciyuan.fast';
  static const _accentKey = 'appearance_accent_rgb';
  static const _accentFormatKey = 'appearance_accent_format_version';
  static const _soundKey = 'appearance_click_sound';
  static const _clickSoundIdKey = 'appearance_click_sound_id';
  static const _boardLabelsKey = 'custom_board_tool_labels';
  static const _aiProxyKey = 'ai_proxy_base_url';
  static const _aiProviderBaseUrlKey = 'ai_provider_base_url';
  static const _aiProviderApiKey = 'ai_provider_api_key';
  static const _collectionBaseUrlKey = 'collection_original_base_url';
  static const _localeKey = 'application_locale';
  static const _aiChatModelKey = 'ai_provider_chat_model';
  static const _aiImageModelKey = 'ai_provider_image_model';
  static const _aiVideoModelKey = 'ai_provider_video_model';
  static const _aiMemoryEnabledKey = 'ai_chat_memory_enabled';
  static const _aiProviderProtocolKey = 'ai_provider_protocol';

  Color _accent = const Color(0xFFE96354);
  bool _soundEnabled = true;
  String _clickSoundId = ClickSoundService.defaultSoundId;
  bool _boardToolLabels = true;
  String _aiProxyBaseUrl = '';
  String _aiProviderBaseUrl = defaultAiProviderBaseUrl;
  String _aiProviderKey = '';
  String _collectionBaseUrl = defaultAiProviderBaseUrl;
  Locale _locale = const Locale('zh', 'CN');
  String _aiChatModel = 'gpt-5.6-sol';
  String _aiImageModel = 'gpt-5.6-sol';
  String _aiVideoModel = 'gpt-5.6-sol';
  bool _aiMemoryEnabled = true;
  AiProviderProtocol _aiProviderProtocol = AiProviderProtocol.auto;
  Future<void>? _initializing;
  Timer? _accentSaveTimer;
  var _chatModelSaveSerial = 0;
  var _imageModelSaveSerial = 0;
  var _videoModelSaveSerial = 0;

  Color get accent => _accent;
  bool get soundEnabled => _soundEnabled;
  String get clickSoundId => _clickSoundId;
  bool get boardToolLabels => _boardToolLabels;
  String get aiProxyBaseUrl => _aiProxyBaseUrl;
  String get aiProviderBaseUrl => _aiProviderBaseUrl;
  String get aiProviderKey => _aiProviderKey;
  bool get hasAiProviderKey => _aiProviderKey.isNotEmpty;
  String get collectionBaseUrl => _collectionBaseUrl;
  Locale get locale => _locale;
  String get aiChatModel => _aiChatModel;
  String get aiImageModel => _aiImageModel;
  String get aiVideoModel => _aiVideoModel;
  bool get aiMemoryEnabled => _aiMemoryEnabled;
  AiProviderProtocol get aiProviderProtocol => _aiProviderProtocol;

  Future<void> initialize() => _initializing ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rgb = prefs.getInt(_accentKey);
      if (rgb != null) {
        // Versions before 2.3 treated Color.r/g/b as 0-255 channels. Values
        // saved by that bug are effectively black, so migrate them back to
        // the original coral accent instead of keeping an unreadable theme.
        final red = (rgb >> 16) & 0xFF;
        final green = (rgb >> 8) & 0xFF;
        final blue = rgb & 0xFF;
        final isLegacy = (prefs.getInt(_accentFormatKey) ?? 1) < 2;
        final shouldMigrate = isLegacy && red <= 1 && green <= 1 && blue <= 1;
        _accent = shouldMigrate
            ? const Color(0xFFE96354)
            : Color(0xFF000000 | rgb);
        if (shouldMigrate) {
          await prefs.setInt(_accentKey, 0xE96354);
          await prefs.setInt(_accentFormatKey, 2);
        }
      }
      _soundEnabled = prefs.getBool(_soundKey) ?? true;
      final storedSoundId = prefs.getString(_clickSoundIdKey) ?? '';
      _clickSoundId = ClickSoundService.supports(storedSoundId)
          ? storedSoundId
          : ClickSoundService.defaultSoundId;
      _boardToolLabels = prefs.getBool(_boardLabelsKey) ?? true;
      _aiProxyBaseUrl = prefs.getString(_aiProxyKey) ?? '';
      final storedProviderBase = prefs.getString(_aiProviderBaseUrlKey);
      _aiProviderBaseUrl = normalizeAiProviderBaseUrl(
        storedProviderBase ?? defaultAiProviderBaseUrl,
      );
      if (_aiProviderBaseUrl != storedProviderBase) {
        await prefs.setString(_aiProviderBaseUrlKey, _aiProviderBaseUrl);
      }
      try {
        _aiProviderKey =
            await const SecureSettingsStore().read(_aiProviderApiKey) ?? '';
      } on Object catch (error) {
        debugPrint('Secure API key storage is unavailable: $error');
      }
      if (_aiProxyBaseUrl.toLowerCase().startsWith('sk-') &&
          _aiProviderKey.isEmpty) {
        _aiProviderKey = _aiProxyBaseUrl;
        _aiProxyBaseUrl = '';
        await const SecureSettingsStore().write(
          _aiProviderApiKey,
          _aiProviderKey,
        );
        await prefs.setString(_aiProxyKey, '');
      }
      final storedCollectionBase = prefs.getString(_collectionBaseUrlKey);
      _collectionBaseUrl = normalizeAiProviderBaseUrl(
        storedCollectionBase ?? _aiProviderBaseUrl,
      );
      if (_collectionBaseUrl != storedCollectionBase) {
        await prefs.setString(_collectionBaseUrlKey, _collectionBaseUrl);
      }
      _locale = _parseLocale(prefs.getString(_localeKey));
      _aiChatModel = normalizeAiModelId(
        prefs.getString(_aiChatModelKey) ?? 'gpt-5.6-sol',
      );
      // The relay treats the selected model as one routing group. Keep all AI
      // capability settings synchronized, including upgrades from builds that
      // briefly stored image and video selections independently.
      _aiImageModel = _aiChatModel;
      _aiVideoModel = _aiChatModel;
      await Future.wait([
        prefs.setString(_aiChatModelKey, _aiChatModel),
        prefs.setString(_aiImageModelKey, _aiChatModel),
        prefs.setString(_aiVideoModelKey, _aiChatModel),
      ]);
      _aiMemoryEnabled = prefs.getBool(_aiMemoryEnabledKey) ?? true;
      _aiProviderProtocol = AiProviderProtocol.values.firstWhere(
        (value) => value.name == prefs.getString(_aiProviderProtocolKey),
        orElse: () => AiProviderProtocol.auto,
      );
      notifyListeners();
    } on Object catch (error) {
      // Defaults remain usable if a platform settings plugin is unavailable.
      debugPrint('Unable to load app settings: $error');
    }
  }

  Future<void> setAccent(Color value) async {
    final argb = value.toARGB32();
    _accent = Color.fromARGB(
      255,
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
    );
    notifyListeners();
    _accentSaveTimer?.cancel();
    _accentSaveTimer = Timer(const Duration(milliseconds: 180), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_accentKey, _accent.toARGB32() & 0xFFFFFF);
        await prefs.setInt(_accentFormatKey, 2);
      } on Object catch (error) {
        debugPrint('Unable to save app accent: $error');
      }
    });
  }

  Future<void> resetAccent() => setAccent(const Color(0xFFE96354));

  Future<void> setSoundEnabled(bool value) async {
    _soundEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundKey, value);
  }

  Future<void> setClickSoundId(String value) async {
    _clickSoundId = ClickSoundService.supports(value)
        ? value
        : ClickSoundService.defaultSoundId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clickSoundIdKey, _clickSoundId);
  }

  Future<void> setBoardToolLabels(bool value) async {
    _boardToolLabels = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_boardLabelsKey, value);
  }

  Future<void> setAiProxyBaseUrl(String value) async {
    _aiProxyBaseUrl = value.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aiProxyKey, _aiProxyBaseUrl);
  }

  Future<void> setAiProviderBaseUrl(String value) async {
    _aiProviderBaseUrl = normalizeAiProviderBaseUrl(value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aiProviderBaseUrlKey, _aiProviderBaseUrl);
  }

  Future<void> setAiProviderAndCollectionBaseUrl(String value) async {
    final normalized = normalizeAiProviderBaseUrl(value);
    _aiProviderBaseUrl = normalized;
    _collectionBaseUrl = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_aiProviderBaseUrlKey, normalized),
      prefs.setString(_collectionBaseUrlKey, normalized),
    ]);
  }

  Future<void> setAiProviderKey(String value) async {
    _aiProviderKey = value.trim();
    notifyListeners();
    const storage = SecureSettingsStore();
    if (_aiProviderKey.isEmpty) {
      await storage.delete(_aiProviderApiKey);
    } else {
      await storage.write(_aiProviderApiKey, _aiProviderKey);
    }
  }

  Future<void> setCollectionBaseUrl(String value) async {
    _collectionBaseUrl = value.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_collectionBaseUrlKey, _collectionBaseUrl);
  }

  Future<void> setLocale(Locale value) async {
    _locale = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _localeKey,
      value.countryCode == null
          ? value.languageCode
          : '${value.languageCode}_${value.countryCode}',
    );
  }

  Future<void> setAiChatModel(String value) async {
    await setAiModels(value);
  }

  Future<void> setAiImageModel(String value) async {
    await setAiModels(value);
  }

  Future<void> setAiVideoModel(String value) async {
    await setAiModels(value);
  }

  /// Saves the selected relay routing group for every AI capability. The
  /// backend may internally route media requests to a capability-specific
  /// model, but the user's three visible model settings stay synchronized.
  Future<void> setAiModels(String value) async {
    final normalized = normalizeAiModelId(value);
    final chatSerial = ++_chatModelSaveSerial;
    final imageSerial = ++_imageModelSaveSerial;
    final videoSerial = ++_videoModelSaveSerial;
    _aiChatModel = normalized;
    _aiImageModel = normalized;
    _aiVideoModel = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (chatSerial != _chatModelSaveSerial ||
        imageSerial != _imageModelSaveSerial ||
        videoSerial != _videoModelSaveSerial) {
      return;
    }
    await Future.wait([
      prefs.setString(_aiChatModelKey, normalized),
      prefs.setString(_aiImageModelKey, normalized),
      prefs.setString(_aiVideoModelKey, normalized),
    ]);
  }

  Future<void> setAiMemoryEnabled(bool value) async {
    _aiMemoryEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_aiMemoryEnabledKey, value);
  }

  Future<void> setAiProviderProtocol(AiProviderProtocol value) async {
    _aiProviderProtocol = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aiProviderProtocolKey, value.name);
  }

  static Locale _parseLocale(String? value) {
    if (value == null || value.isEmpty) return const Locale('zh', 'CN');
    final parts = value.replaceAll('-', '_').split('_');
    return Locale(parts.first, parts.length > 1 ? parts[1] : null);
  }

  static String normalizeAiProviderBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return trimmed;
    final host = uri.host.toLowerCase();
    if (host == _legacyAiProviderHost) {
      return defaultAiProviderBaseUrl;
    }
    if (host == 'ciyuan.fast' && (uri.path.isEmpty || uri.path == '/')) {
      return defaultAiProviderBaseUrl;
    }
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }

  static String normalizeAiModelId(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'gpt-5.6-sol';
    final compact = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return compact == 'gpt56sol' ? 'gpt-5.6-sol' : trimmed;
  }
}
