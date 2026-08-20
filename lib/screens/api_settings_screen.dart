import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_design_service.dart';
import '../services/ai_api_health_service.dart';
import '../services/ai_chat_service.dart';
import '../services/api_clipboard_import.dart';
import '../services/api_profile_store.dart';
import '../services/ai_model_profile.dart';
import '../services/app_error.dart';
import '../services/app_notice_center.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import 'api_management_screen.dart';

const _apiClipboardExample = '''APP 服务端地址：https://app.example.com
API 密钥：sk-请替换为你的密钥
API 中转地址：https://gateway.example.com/v1
原图库服务地址：https://library.example.com/v1
模型：gpt-5.6-sol
协议：openAiCompatible''';

class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  static bool _suppressAutomaticClipboardOfferForSession = false;

  late final TextEditingController _appServerController;
  late final TextEditingController _providerController;
  late final TextEditingController _keyController;
  late final TextEditingController _chatModelController;
  late final TextEditingController _imageModelController;
  late final TextEditingController _videoModelController;
  late final TextEditingController _collectionController;
  var _obscureKey = true;
  var _obscureCollection = true;
  var _testingChat = false;
  var _testingImage = false;
  var _testingVideo = false;
  var _testingAll = false;
  var _allTestProgress = 0.0;
  var _allTestElapsedSeconds = 0;
  String? _allTestPhase;
  Timer? _allTestTimer;
  String? _chatTestMessage;
  String? _imageTestMessage;
  String? _videoTestMessage;
  bool? _chatTestSucceeded;
  bool? _imageTestSucceeded;
  bool? _videoTestSucceeded;
  var _clipboardOfferChecked = false;
  var _clipboardDialogOpen = false;

  @override
  void initState() {
    super.initState();
    final settings = AppSettings.instance;
    _appServerController = TextEditingController(text: settings.aiProxyBaseUrl);
    _providerController = TextEditingController(
      text: settings.aiProviderBaseUrl,
    );
    _keyController = TextEditingController(text: settings.aiProviderKey);
    _chatModelController = TextEditingController(text: settings.aiChatModel);
    _imageModelController = TextEditingController(text: settings.aiImageModel);
    _videoModelController = TextEditingController(text: settings.aiVideoModel);
    _collectionController = TextEditingController(
      text: settings.collectionBaseUrl,
    );
    settings.addListener(_settingsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_offerClipboardImport());
    });
  }

  @override
  void dispose() {
    _allTestTimer?.cancel();
    AppSettings.instance.removeListener(_settingsChanged);
    _appServerController.dispose();
    _providerController.dispose();
    _keyController.dispose();
    _chatModelController.dispose();
    _imageModelController.dispose();
    _videoModelController.dispose();
    _collectionController.dispose();
    super.dispose();
  }

  void _settingsChanged() {
    final settings = AppSettings.instance;
    _replaceText(_appServerController, settings.aiProxyBaseUrl);
    _replaceText(_providerController, settings.aiProviderBaseUrl);
    _replaceText(_keyController, settings.aiProviderKey);
    _replaceText(_collectionController, settings.collectionBaseUrl);
    final model = settings.aiChatModel;
    for (final controller in [
      _chatModelController,
      _imageModelController,
      _videoModelController,
    ]) {
      _replaceModelText(controller, model);
    }
  }

  Future<void> _openApiManager() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ApiManagementScreen()),
    );
    if (!mounted) return;
    _settingsChanged();
    setState(() {});
  }

  void _providerChanged(String value) {
    final normalized = AppSettings.normalizeAiProviderBaseUrl(value);
    if (_providerController.text != normalized) {
      _providerController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    if (_collectionController.text != normalized) {
      _collectionController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    unawaited(AppSettings.instance.setAiProviderAndCollectionBaseUrl(value));
  }

  void _modelChanged(String value) {
    for (final controller in [
      _chatModelController,
      _imageModelController,
      _videoModelController,
    ]) {
      _replaceModelText(controller, value);
    }
    unawaited(AppSettings.instance.setAiModels(value));
  }

  Future<String?> _clipboardText() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    } on Object {
      return null;
    }
  }

  Future<void> _offerClipboardImport() async {
    if (_clipboardOfferChecked ||
        _suppressAutomaticClipboardOfferForSession ||
        !mounted) {
      return;
    }
    _clipboardOfferChecked = true;
    final source = await _clipboardText();
    if (source == null || source.isEmpty || !mounted) return;
    final data = ApiClipboardImportParser.parse(source);
    if (!data.canOfferAutomatically || !_clipboardChangesAnything(data)) {
      return;
    }
    await _confirmClipboardImport(data, automatic: true);
  }

  Future<void> _importClipboard() async {
    final source = await _clipboardText();
    if (!mounted) return;
    if (source == null || source.isEmpty) {
      AppNoticeCenter.instance.show(
        '剪贴板中没有可导入的文字。',
        kind: AppNoticeKind.warning,
      );
      return;
    }
    final data = ApiClipboardImportParser.parse(source);
    if (!data.hasValues) {
      AppNoticeCenter.instance.show(
        '没有识别到 API 密钥、HTTP/HTTPS 地址或模型配置。',
        kind: AppNoticeKind.warning,
      );
      return;
    }
    await _confirmClipboardImport(data, automatic: false);
  }

  bool _clipboardChangesAnything(ApiClipboardImportData data) {
    final provider = data.providerBaseUrl == null
        ? null
        : AppSettings.normalizeAiProviderBaseUrl(data.providerBaseUrl!);
    final collection = data.collectionBaseUrl == null
        ? provider
        : AppSettings.normalizeAiProviderBaseUrl(data.collectionBaseUrl!);
    return (data.appServerBaseUrl != null &&
            data.appServerBaseUrl != _appServerController.text.trim()) ||
        (data.apiKey != null && data.apiKey != _keyController.text.trim()) ||
        (provider != null && provider != _providerController.text.trim()) ||
        (collection != null &&
            collection != _collectionController.text.trim()) ||
        (data.model != null &&
            AppSettings.normalizeAiModelId(data.model!) !=
                _chatModelController.text.trim()) ||
        (data.protocol != null &&
            data.protocol != AppSettings.instance.aiProviderProtocol);
  }

  Future<void> _confirmClipboardImport(
    ApiClipboardImportData data, {
    required bool automatic,
  }) async {
    if (_clipboardDialogOpen || !mounted) return;
    _clipboardDialogOpen = true;
    final provider = data.providerBaseUrl;
    final collection = data.collectionBaseUrl ?? provider;
    final importedModel = data.model?.trim();
    final currentModel = AppSettings.instance.aiChatModel.trim();
    final model = AppSettings.normalizeAiModelId(
      importedModel?.isNotEmpty == true
          ? importedModel!
          : currentModel.isNotEmpty
          ? currentModel
          : _chatModelController.text,
    );
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.content_paste_go_rounded),
        title: Text(automatic ? '检测到剪贴板 API 配置' : '导入剪贴板 API 配置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('确认后只覆盖下列已识别字段，未识别字段保持不变：'),
              const SizedBox(height: 10),
              if (data.profileName != null)
                _ImportValue(label: '配置名称', value: data.profileName!),
              if (data.appServerBaseUrl != null)
                _ImportValue(label: 'APP 服务端', value: data.appServerBaseUrl!),
              if (data.apiKey != null)
                _ImportValue(label: 'API 密钥', value: _maskedKey(data.apiKey!)),
              if (provider != null)
                _ImportValue(label: 'API 中转地址', value: provider),
              if (collection != null)
                _ImportValue(label: '原图库服务地址', value: collection),
              _ImportValue(label: '三个 AI 模型', value: model),
              if (data.protocol != null)
                _ImportValue(label: 'API 协议', value: data.protocol!.label),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: const Text('保持当前配置'),
          ),
          if (automatic)
            TextButton(
              key: const ValueKey('suppressClipboardApiOfferForSession'),
              onPressed: () => Navigator.pop(context, 'suppress'),
              child: const Text('本次不再提示'),
            ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, 'apply'),
            icon: const Icon(Icons.check_rounded),
            label: const Text('确认覆盖'),
          ),
        ],
      ),
    );
    _clipboardDialogOpen = false;
    if (decision == 'suppress') {
      _suppressAutomaticClipboardOfferForSession = true;
      return;
    }
    if (decision != 'apply' || !mounted) return;
    await _applyClipboardImport(data, model: model);
  }

  Future<void> _applyClipboardImport(
    ApiClipboardImportData data, {
    required String model,
  }) async {
    final settings = AppSettings.instance;
    final provider = data.providerBaseUrl == null
        ? null
        : AppSettings.normalizeAiProviderBaseUrl(data.providerBaseUrl!);
    final collectionSource = data.collectionBaseUrl ?? provider;
    final collection = collectionSource == null
        ? null
        : AppSettings.normalizeAiProviderBaseUrl(collectionSource);
    if (data.appServerBaseUrl != null) {
      await settings.setAiProxyBaseUrl(data.appServerBaseUrl!);
    }
    if (provider != null) {
      await settings.setAiProviderAndCollectionBaseUrl(provider);
    }
    if (collection != null && collection != provider) {
      await settings.setCollectionBaseUrl(collection);
    }
    if (data.apiKey != null) await settings.setAiProviderKey(data.apiKey!);
    await settings.setAiModels(model);
    if (data.protocol != null) {
      await settings.setAiProviderProtocol(data.protocol!);
    }
    if (!mounted) return;
    setState(() {
      if (data.appServerBaseUrl != null) {
        _replaceText(_appServerController, data.appServerBaseUrl!);
      }
      if (provider != null) _replaceText(_providerController, provider);
      if (collection != null) _replaceText(_collectionController, collection);
      if (data.apiKey != null) _replaceText(_keyController, data.apiKey!);
      for (final controller in [
        _chatModelController,
        _imageModelController,
        _videoModelController,
      ]) {
        _replaceText(controller, model);
      }
    });
    AppNoticeCenter.instance.show(
      '剪贴板完整 API 配置已导入，模型已统一为 $model。',
      kind: AppNoticeKind.success,
    );
  }

  Future<void> _pasteKey() async {
    final source = await _clipboardText();
    if (!mounted) return;
    final value = source == null
        ? null
        : ApiClipboardImportParser.apiKey(source);
    final fallback = source?.contains(RegExp(r'\s')) == false ? source : null;
    final key = value ?? fallback;
    if (key == null || key.isEmpty) {
      AppNoticeCenter.instance.show(
        '剪贴板中没有识别到 API 密钥。',
        kind: AppNoticeKind.warning,
      );
      return;
    }
    _replaceText(_keyController, key);
    await AppSettings.instance.setAiProviderKey(key);
  }

  Future<void> _pasteUrl({required bool collection}) async {
    final source = await _clipboardText();
    if (!mounted) return;
    final data = ApiClipboardImportParser.parse(source ?? '');
    final value = collection
        ? data.collectionBaseUrl ?? data.providerBaseUrl
        : data.providerBaseUrl ??
              ApiClipboardImportParser.firstHttpUrl(source ?? '');
    if (value == null) {
      AppNoticeCenter.instance.show(
        '剪贴板中没有识别到 HTTP/HTTPS 地址。',
        kind: AppNoticeKind.warning,
      );
      return;
    }
    final normalized = AppSettings.normalizeAiProviderBaseUrl(value);
    if (collection) {
      _replaceText(_collectionController, normalized);
      await AppSettings.instance.setCollectionBaseUrl(normalized);
    } else {
      _replaceText(_providerController, normalized);
      _replaceText(_collectionController, normalized);
      await AppSettings.instance.setAiProviderAndCollectionBaseUrl(normalized);
    }
  }

  Future<void> _saveCurrentConfiguration() async {
    final settings = AppSettings.instance;
    await settings.setAiProxyBaseUrl(_appServerController.text);
    await settings.setAiProviderAndCollectionBaseUrl(_providerController.text);
    await settings.setCollectionBaseUrl(_collectionController.text);
    await settings.setAiProviderKey(_keyController.text);
    await settings.setAiModels(_chatModelController.text);
  }

  Future<void> _copyCurrentConfiguration() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveCurrentConfiguration();
    final store = ApiProfileStore.instance;
    final profile = store.currentAsProfile(name: '当前 API 配置');
    await Clipboard.setData(ClipboardData(text: store.shareText(profile)));
    if (!mounted) return;
    AppNoticeCenter.instance.show(
      '当前完整 API 配置已复制到剪贴板，可直接分享并由对方一键识别导入。内容包含 API 密钥，请仅分享给可信的人。',
      kind: AppNoticeKind.success,
    );
  }

  static String _maskedKey(String value) {
    if (value.length <= 8) return '••••••••';
    return '${value.substring(0, 4)}••••${value.substring(value.length - 4)}';
  }

  void _replaceText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _testChat() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _testingChat = true;
      _chatTestMessage = null;
      _chatTestSucceeded = null;
    });
    final stopwatch = Stopwatch()..start();
    try {
      await _saveCurrentConfiguration();
      final result = await AiDesignService.instance.generate(
        prompt: '只回复：连接成功',
        model: AppSettings.instance.aiChatModel,
      );
      if (!mounted) return;
      setState(() {
        _chatTestSucceeded = true;
        _chatTestMessage =
            'AI 对话模型连接成功 · ${result.model} · 耗时 ${_elapsed(stopwatch)}';
      });
      unawaited(AiApiHealthService.instance.check());
    } on Object catch (error) {
      if (!mounted) return;
      final info = AppNoticeCenter.instance.showError(
        error,
        operation: 'AI 连接测试',
      );
      setState(() {
        _chatTestSucceeded = false;
        _chatTestMessage = '${info.displayText}\n耗时 ${_elapsed(stopwatch)}';
      });
    } finally {
      if (mounted) setState(() => _testingChat = false);
    }
  }

  Future<void> _testImage() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _testingImage = true;
      _imageTestMessage = null;
      _imageTestSucceeded = null;
    });
    final stopwatch = Stopwatch()..start();
    try {
      await _saveCurrentConfiguration();
      final result = await AiDesignService.instance.generateImage(
        prompt: '一颗红色拼豆的极简像素图，白色背景',
        size: '1024x1024',
        model: AppSettings.instance.aiImageModel,
      );
      if (!mounted) return;
      setState(() {
        _imageTestSucceeded = true;
        _imageTestMessage =
            'AI 图片模型连接成功 · ${result.model} · 1024×1024 · 耗时 ${_elapsed(stopwatch)}';
      });
      unawaited(AiApiHealthService.instance.check());
    } on Object catch (error) {
      if (!mounted) return;
      final info = AppErrorClassifier.classify(error, operation: '图片模型测试');
      AppNoticeCenter.instance.showError(error, operation: '图片模型测试');
      setState(() {
        _imageTestSucceeded = false;
        _imageTestMessage = '${info.displayText}\n耗时 ${_elapsed(stopwatch)}';
      });
    } finally {
      if (mounted) setState(() => _testingImage = false);
    }
  }

  Future<void> _testVideo() => _runVideoTest(requireConfirmation: true);

  Future<void> _runVideoTest({required bool requireConfirmation}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (requireConfirmation) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('测试视频模型？'),
          content: const Text('这会真实调用当前视频模型并可能产生费用。视频生成通常需要数分钟，请保持程序运行。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开始测试'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _testingVideo = true;
      _videoTestMessage = null;
      _videoTestSucceeded = null;
    });
    final stopwatch = Stopwatch()..start();
    try {
      await _saveCurrentConfiguration();
      final capabilityIssue = await _knownVideoCapabilityIssue();
      if (capabilityIssue != null) {
        if (!mounted) return;
        setState(() {
          _videoTestSucceeded = false;
          _videoTestMessage = capabilityIssue;
        });
        return;
      }
      final result = await AiDesignService.instance.generateVideo(
        prompt: '一颗红色拼豆在白色背景上缓慢旋转，镜头稳定',
        durationSeconds: 5,
        model: AppSettings.instance.aiVideoModel,
      );
      if (!mounted) return;
      setState(() {
        _videoTestSucceeded = true;
        _videoTestMessage =
            'AI 视频模型连接成功 · ${result.model} · 1280×720 / 5 秒 · 耗时 ${_elapsed(stopwatch)}';
      });
      unawaited(AiApiHealthService.instance.check());
    } on Object catch (error) {
      if (!mounted) return;
      final info = AppErrorClassifier.classify(error, operation: '视频模型测试');
      AppNoticeCenter.instance.showError(error, operation: '视频模型测试');
      setState(() {
        _videoTestSucceeded = false;
        _videoTestMessage = '${info.displayText}\n耗时 ${_elapsed(stopwatch)}';
      });
    } finally {
      if (mounted) setState(() => _testingVideo = false);
    }
  }

  Future<void> _testAllModels() async {
    if (_testingAll || _testingChat || _testingImage || _testingVideo) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.fact_check_outlined),
        title: const Text('一键检测全部 AI 模型？'),
        content: const Text(
          '将依次真实调用 AI 对话、图片和视频模型。图片与视频可能产生费用，视频检测可能持续数分钟；检测期间请保持程序运行。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('开始检测'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _allTestTimer?.cancel();
    setState(() {
      _testingAll = true;
      _allTestProgress = 0.03;
      _allTestElapsedSeconds = 0;
      _allTestPhase = '正在保存并校验当前 API 参数';
      _chatTestMessage = null;
      _imageTestMessage = null;
      _videoTestMessage = null;
      _chatTestSucceeded = null;
      _imageTestSucceeded = null;
      _videoTestSucceeded = null;
    });
    _allTestTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _testingAll) {
        setState(() => _allTestElapsedSeconds++);
      }
    });
    try {
      await _saveCurrentConfiguration();
      if (!mounted) return;
      setState(() {
        _allTestProgress = 0.08;
        _allTestPhase = '1/3 正在真实调用 AI 对话模型';
      });
      await _testChat();
      if (!mounted) return;
      setState(() {
        _allTestProgress = 0.36;
        _allTestPhase = '2/3 正在生成最小测试图片';
      });
      await _testImage();
      if (!mounted) return;
      setState(() {
        _allTestProgress = 0.69;
        _allTestPhase = '3/3 正在生成 5 秒测试视频';
      });
      await _runVideoTest(requireConfirmation: false);
      if (!mounted) return;
      final successCount = [
        _chatTestSucceeded,
        _imageTestSucceeded,
        _videoTestSucceeded,
      ].where((value) => value == true).length;
      setState(() {
        _allTestProgress = 1;
        _allTestPhase = '检测完成：3 项中 $successCount 项可用';
      });
    } finally {
      _allTestTimer?.cancel();
      _allTestTimer = null;
      if (mounted) setState(() => _testingAll = false);
    }
  }

  static String _elapsed(Stopwatch stopwatch) {
    final milliseconds = stopwatch.elapsedMilliseconds;
    if (milliseconds < 1000) return '$milliseconds 毫秒';
    return '${(milliseconds / 1000).toStringAsFixed(1)} 秒';
  }

  Future<String?> _knownVideoCapabilityIssue() async {
    final settings = AppSettings.instance;
    if (settings.aiProxyBaseUrl.trim().isNotEmpty) return null;
    final providerUri = Uri.tryParse(settings.aiProviderBaseUrl.trim());
    if (providerUri?.host.toLowerCase() != 'ciyuan.fast') return null;
    try {
      final catalog = await const AiChatService().loadCatalog();
      final videoModels = catalog.models
          .where(isLikelyVideoGenerationModel)
          .toList();
      if (videoModels.isNotEmpty ||
          isLikelyVideoGenerationModel(settings.aiVideoModel)) {
        return null;
      }
      return '视频模型不可用：API 中转连接正常，但该账户的 /models 目录没有返回任何视频生成模型。\n'
          '词元当前公开目录只提供文本和图片模型；请使用已开通 Sora、Veo、可灵等视频模型及视频端点的中转。';
    } on Object {
      // If model discovery itself is unavailable, keep the real endpoint test
      // as the authoritative compatibility check.
      return null;
    }
  }

  void _replaceModelText(TextEditingController controller, String model) =>
      _replaceText(controller, AppSettings.normalizeAiModelId(model));

  Future<void> _showClipboardExamples() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('剪贴板配置示例与教程'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('复制下面任一格式，再打开 API 设置或点击“一键导入”，软件会先展示识别结果，只有确认后才覆盖。'),
                const SizedBox(height: 12),
                const Text(
                  '可识别内容',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                const Text(
                  '• API 密钥：API Key、API 密钥、密钥、Token、令牌\n'
                  '• 中转地址：Base URL、BASE_URL、API URL、Endpoint、中转地址\n'
                  '• 原图库地址：原图库、图库地址、Collection、Library、Original\n'
                  '• 模型：Model、模型，以及常见的完整模型 ID\n'
                  '• 分隔符：中文/英文冒号、等号；也支持密钥、网址和模型各占一行',
                ),
                const SizedBox(height: 14),
                const Text(
                  '样板一：中文标签（推荐）',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                const SelectableText(_apiClipboardExample),
                const SizedBox(height: 14),
                const Text(
                  '样板二：环境变量格式',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                const SelectableText(
                  'API_KEY=sk-your-key\n'
                  'BASE_URL=https://gateway.example.com/v1\n'
                  'COLLECTION_URL=https://library.example.com/v1\n'
                  'MODEL=qwen-max',
                ),
                const SizedBox(height: 14),
                const Text(
                  '样板三：无标签独立行',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                const SelectableText(
                  'sk-your-key\n'
                  'https://gateway.example.com/v1\n'
                  'gpt-5.6-sol',
                ),
                const SizedBox(height: 12),
                const Text(
                  '提示：模型必须使用接口返回的完整 ID。若剪贴板没有模型，软件会保留当前模型或按账户目录选择推荐模型。',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('copyApiClipboardExampleButton'),
            onPressed: () async {
              await Clipboard.setData(
                const ClipboardData(text: _apiClipboardExample),
              );
              if (!dialogContext.mounted) return;
              AppNoticeCenter.instance.showSnackBar(
                const SnackBar(content: Text('完整示例已复制到剪贴板')),
              );
            },
            icon: const Icon(Icons.copy_all_rounded),
            label: const Text('复制完整示例'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('API 设置'),
      actions: [
        TextButton.icon(
          key: const ValueKey('openApiManagementButton'),
          onPressed: _openApiManager,
          icon: const Icon(Icons.dns_rounded),
          label: const Text('管理'),
        ),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const ApiTutorialScreen()),
          ),
          icon: const Icon(Icons.help_outline_rounded),
          label: const Text('使用教程'),
        ),
      ],
    ),
    body: ListView(
      cacheExtent: 10000,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Card(
          color: const Color(0xFFF1F8FF),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '一键导入 API 配置',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('apiClipboardExampleButton'),
                      onPressed: _showClipboardExamples,
                      icon: const Icon(Icons.help_outline_rounded, size: 18),
                      label: const Text('剪贴板复制示例'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '可同时识别 API 密钥、中转地址、原图库地址和模型；导入前会显示确认对话框。',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const ValueKey('importApiClipboardButton'),
                  onPressed: _importClipboard,
                  icon: const Icon(Icons.content_paste_go_rounded),
                  label: const Text('识别并粘贴剪贴板配置'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('copyCurrentApiConfigurationButton'),
                  onPressed: _copyCurrentConfiguration,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('一键复制当前完整配置用于分享'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _SectionTitle(
          icon: Icons.dns_outlined,
          title: '服务地址',
          subtitle: 'API 中转地址修改后，原图库服务地址会立即同步',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _appServerController,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'APP 服务端地址（可选）',
            hintText: '自建后端地址；留空时可直连中转 API',
            prefixIcon: Icon(Icons.cloud_outlined),
          ),
          onChanged: (value) =>
              unawaited(AppSettings.instance.setAiProxyBaseUrl(value)),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('apiProviderBaseUrlField'),
          controller: _providerController,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'API 中转地址',
            hintText: '兼容 OpenAI 的完整 /v1 地址',
            prefixIcon: const Icon(Icons.route_outlined),
            suffixIcon: IconButton(
              key: const ValueKey('pasteApiProviderUrlButton'),
              onPressed: () => _pasteUrl(collection: false),
              tooltip: '一键粘贴中转地址',
              icon: const Icon(Icons.content_paste_rounded),
            ),
          ),
          onChanged: _providerChanged,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<AiProviderProtocol>(
          key: ValueKey(
            'apiProtocol_${AppSettings.instance.aiProviderProtocol.name}',
          ),
          initialValue: AppSettings.instance.aiProviderProtocol,
          decoration: const InputDecoration(
            labelText: 'API 协议',
            prefixIcon: Icon(Icons.account_tree_outlined),
            helperText: '普通中转请选择自动或 OpenAI 兼容；官方直连接口再选厂商协议',
          ),
          items: [
            for (final protocol in AiProviderProtocol.values)
              DropdownMenuItem(value: protocol, child: Text(protocol.label)),
          ],
          onChanged: (value) {
            if (value != null) {
              unawaited(AppSettings.instance.setAiProviderProtocol(value));
            }
          },
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('collectionBaseUrlField'),
          controller: _collectionController,
          keyboardType: TextInputType.url,
          obscureText: _obscureCollection,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: '原图库服务地址',
            hintText: '随 API 中转地址同步，也可在此单独修改',
            prefixIcon: const Icon(Icons.high_quality_outlined),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const ValueKey('pasteCollectionUrlButton'),
                  onPressed: () => _pasteUrl(collection: true),
                  tooltip: '一键粘贴原图库地址',
                  icon: const Icon(Icons.content_paste_rounded),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _obscureCollection = !_obscureCollection),
                  tooltip: _obscureCollection ? '显示原图库地址' : '隐藏原图库地址',
                  icon: Icon(
                    _obscureCollection
                        ? Icons.visibility_outlined
                        : Icons.visibility_off,
                  ),
                ),
              ],
            ),
          ),
          onChanged: (value) =>
              unawaited(AppSettings.instance.setCollectionBaseUrl(value)),
        ),
        const SizedBox(height: 24),
        const _SectionTitle(
          icon: Icons.key_rounded,
          title: '密钥与模型',
          subtitle: '密钥仅保存在本机安全存储中，不会写入安装包',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _keyController,
          obscureText: _obscureKey,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'API 密钥',
            hintText: '填写中转服务提供的密钥',
            prefixIcon: const Icon(Icons.password_rounded),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const ValueKey('pasteApiKeyButton'),
                  onPressed: _pasteKey,
                  tooltip: '一键粘贴 API 密钥',
                  icon: const Icon(Icons.content_paste_rounded),
                ),
                IconButton(
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  tooltip: _obscureKey ? '显示密钥' : '隐藏密钥',
                  icon: Icon(
                    _obscureKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off,
                  ),
                ),
              ],
            ),
          ),
          onChanged: (value) =>
              unawaited(AppSettings.instance.setAiProviderKey(value)),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('apiChatModelField'),
          controller: _chatModelController,
          decoration: const InputDecoration(
            labelText: 'AI 对话模型',
            hintText: '例如 gpt-5.6-sol',
            prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
            helperText: '修改任意一个模型后，对话、图片和视频模型会同步',
          ),
          onChanged: _modelChanged,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('apiImageModelField'),
          controller: _imageModelController,
          decoration: const InputDecoration(
            labelText: 'AI 图片模型',
            hintText: '与当前选择模型同步',
            prefixIcon: Icon(Icons.image_outlined),
          ),
          onChanged: _modelChanged,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('apiVideoModelField'),
          controller: _videoModelController,
          decoration: const InputDecoration(
            labelText: 'AI 视频模型',
            hintText: '与当前选择模型同步',
            prefixIcon: Icon(Icons.movie_creation_outlined),
          ),
          onChanged: _modelChanged,
        ),
        const SizedBox(height: 24),
        const _SectionTitle(
          icon: Icons.network_check_rounded,
          title: '连接测试',
          subtitle: '测试结果会保留显示在本页面',
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('testAllAiModelsButton'),
            onPressed:
                _testingAll || _testingChat || _testingImage || _testingVideo
                ? null
                : _testAllModels,
            icon: _testingAll
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined),
            label: const Text('一键检测对话、图片、视频模型'),
          ),
        ),
        if (_allTestPhase != null) ...[
          const SizedBox(height: 10),
          _AllModelTestProgress(
            progress: _allTestProgress,
            phase: _allTestPhase!,
            elapsedSeconds: _allTestElapsedSeconds,
            providerBaseUrl: _providerController.text.trim(),
            protocol: AppSettings.instance.aiProviderProtocol.label,
            chatModel: _chatModelController.text.trim(),
            imageModel: _imageModelController.text.trim(),
            videoModel: _videoModelController.text.trim(),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _testingAll || _testingChat ? null : _testChat,
                icon: _testingChat
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chat_outlined),
                label: const Text('测试 AI 连接'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _testingAll || _testingImage ? null : _testImage,
                icon: _testingImage
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_search_rounded),
                label: const Text('测试图片模型'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: _testingAll || _testingVideo ? null : _testVideo,
            icon: _testingVideo
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.video_settings_outlined),
            label: const Text('测试视频模型（会产生真实调用）'),
          ),
        ),
        if (_chatTestMessage != null) ...[
          const SizedBox(height: 10),
          _TestResult(
            succeeded: _chatTestSucceeded == true,
            message: _chatTestMessage!,
          ),
        ],
        if (_imageTestMessage != null) ...[
          const SizedBox(height: 10),
          _TestResult(
            succeeded: _imageTestSucceeded == true,
            message: _imageTestMessage!,
          ),
        ],
        if (_videoTestMessage != null) ...[
          const SizedBox(height: 10),
          _TestResult(
            succeeded: _videoTestSucceeded == true,
            message: _videoTestMessage!,
          ),
        ],
      ],
    ),
  );
}

class ApiTutorialScreen extends StatelessWidget {
  const ApiTutorialScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('API 设置详细教程')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
      children: const [
        _TutorialStep(
          number: '1',
          title: '准备中转地址和密钥',
          text:
              '从你有权使用的服务商后台复制 API Base URL 和 API Key。中转通常形如 https://域名/v1；不要填写聊天网页地址、登录页或只填写 sk- 密钥到地址栏。',
        ),
        _TutorialStep(
          number: '2',
          title: '选择协议',
          text:
              '大多数中转选择“自动检测”或“OpenAI 兼容协议”。只有直接连接 Anthropic 官方 Messages API 或 Google Gemini generateContent 时，才选择对应厂商协议。模型名称可以是供应商返回的任意完整 ID。',
        ),
        _TutorialStep(
          number: '3',
          title: '选择并同步模型',
          text:
              '修改对话、图片或视频任意一个模型输入框，三个配置都会立即同步为同一个完整模型 ID。进入 AI 聊天后，软件会读取 /models 列表；当前模型仍在目录中时会保留，不在目录中时会自动切换为该 API 的综合推荐模型。',
        ),
        _TutorialStep(
          number: '4',
          title: '运行连接测试',
          text:
              '先测试 AI 对话，再测试图片。视频测试会产生真实费用且可能等待数分钟，因此会先二次确认。401/403 是密钥或权限问题，404 通常是地址路径或模型 ID 不对，429 是限流/余额，5xx 是中转或上游服务异常，证书/DNS/连接拒绝属于网络问题。',
        ),
        _TutorialStep(
          number: '5',
          title: '图片和视频能力说明',
          text:
              '模型名称本身不等于具备生图/视频接口。中转必须实现 OpenAI Images/Responses image_generation 或可配置的通用视频生成端点；封闭平台需要服务商提供合法授权的兼容中转。',
        ),
        SizedBox(height: 18),
        Text(
          '图文填写示例',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 10),
        _ApiFormExample(),
      ],
    ),
  );
}

class _TutorialStep extends StatelessWidget {
  const _TutorialStep({
    required this.number,
    required this.title,
    required this.text,
  });
  final String number;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(child: Text(number)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(text, style: const TextStyle(height: 1.55)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ApiFormExample extends StatelessWidget {
  const _ApiFormExample();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F5F1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.line),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '示例画面（请替换成你自己的真实信息）',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 12),
        _ExampleField(
          label: 'API 中转地址',
          value: 'https://api.example.com/v1',
          color: Color(0xFF2E6DA4),
        ),
        _ExampleArrow(text: '完整地址，通常以 /v1 结尾'),
        _ExampleField(
          label: 'API 协议',
          value: '自动检测（优先中转兼容）',
          color: AppColors.teal,
        ),
        _ExampleArrow(text: '普通中转选这一项'),
        _ExampleField(
          label: 'API 密钥',
          value: 'sk-••••••••••••••••',
          color: Color(0xFFE96354),
        ),
        _ExampleArrow(text: '只保存在本机安全存储'),
        _ExampleField(
          label: 'AI 对话 / 图片 / 视频模型',
          value: '服务商返回的完整模型 ID',
          color: Color(0xFF7B4DA8),
        ),
      ],
    ),
  );
}

class _ExampleField extends StatelessWidget {
  const _ExampleField({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: color, width: 2),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(value),
      ],
    ),
  );
}

class _ExampleArrow extends StatelessWidget {
  const _ExampleArrow({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        const Icon(Icons.arrow_downward_rounded, size: 17),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

class _ImportValue extends StatelessWidget {
  const _ImportValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            '$label：',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ],
  );
}

class _AllModelTestProgress extends StatelessWidget {
  const _AllModelTestProgress({
    required this.progress,
    required this.phase,
    required this.elapsedSeconds,
    required this.providerBaseUrl,
    required this.protocol,
    required this.chatModel,
    required this.imageModel,
    required this.videoModel,
  });

  final double progress;
  final String phase;
  final int elapsedSeconds;
  final String providerBaseUrl;
  final String protocol;
  final String chatModel;
  final String imageModel;
  final String videoModel;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: '$phase，进度 ${(progress * 100).round()}%',
    child: Container(
      key: const ValueKey('allAiModelsTestProgress'),
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8FF),
        border: Border.all(color: const Color(0xFFB7D8F5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_heart_outlined, color: AppColors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  phase,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text('${(progress * 100).round()}% · ${elapsedSeconds}s'),
            ],
          ),
          const SizedBox(height: 9),
          LinearProgressIndicator(value: progress.clamp(0, 1)),
          const SizedBox(height: 10),
          SelectableText(
            '中转地址：${providerBaseUrl.isEmpty ? "未填写（使用 APP 服务端）" : providerBaseUrl}\n'
            '协议：$protocol\n'
            'AI 对话模型：$chatModel\n'
            'AI 图片模型：$imageModel（1024×1024）\n'
            'AI 视频模型：$videoModel（1280×720，5 秒）',
            style: const TextStyle(fontSize: 12, height: 1.45),
          ),
        ],
      ),
    ),
  );
}

class _TestResult extends StatelessWidget {
  const _TestResult({required this.succeeded, required this.message});

  final bool succeeded;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = succeeded ? const Color(0xFF1F7A4C) : const Color(0xFFB3261E);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('apiConnectionTestResult'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              succeeded ? Icons.check_circle_rounded : Icons.error_rounded,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                message,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
