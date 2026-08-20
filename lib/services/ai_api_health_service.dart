import 'dart:async';

import 'package:flutter/material.dart';

import 'ai_chat_store.dart';
import 'ai_chat_service.dart';
import 'ai_design_service.dart';
import 'app_error.dart';
import 'app_settings.dart';

enum AiApiHealthState { checking, healthy, unconfigured, unhealthy }

enum AiSelectedModelHealthState { idle, checking, healthy, unhealthy }

class AiApiHealthService extends ChangeNotifier {
  AiApiHealthService._();

  static final instance = AiApiHealthService._();

  AiApiHealthState _state = AiApiHealthState.checking;
  AppErrorInfo? _error;
  AiBalanceInfo? _balance;
  DateTime? _checkedAt;
  Timer? _settingsDebounce;
  Future<void>? _checking;
  bool _initialized = false;
  AiSelectedModelHealthState _selectedModelState =
      AiSelectedModelHealthState.idle;
  String? _selectedModel;
  String? _selectedModelMessage;
  DateTime? _selectedModelCheckedAt;
  var _selectedModelCheckSerial = 0;

  AiApiHealthState get state => _state;
  AppErrorInfo? get error => _error;
  AiBalanceInfo? get balance => _balance;
  DateTime? get checkedAt => _checkedAt;
  bool get isAvailable => _state == AiApiHealthState.healthy;
  AiSelectedModelHealthState get selectedModelState => _selectedModelState;
  String? get selectedModel => _selectedModel;
  String? get selectedModelMessage => _selectedModelMessage;
  DateTime? get selectedModelCheckedAt => _selectedModelCheckedAt;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await AppSettings.instance.initialize();
    AppSettings.instance.addListener(_settingsChanged);
    Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(check(silent: true)),
    );
    await check();
  }

  void _settingsChanged() {
    _settingsDebounce?.cancel();
    _settingsDebounce = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(check()),
    );
  }

  Future<void> checkSelectedModelCapabilities({
    required String model,
    AiChatService? chatService,
    Future<void> Function(String model)? imageProbe,
  }) async {
    final selected = AppSettings.normalizeAiModelId(model);
    final serial = ++_selectedModelCheckSerial;
    _selectedModel = selected;
    _selectedModelState = AiSelectedModelHealthState.checking;
    _selectedModelMessage = null;
    _selectedModelCheckedAt = null;
    notifyListeners();

    Object? chatError;
    Object? imageError;
    final chatWatch = Stopwatch()..start();
    final imageWatch = Stopwatch();
    try {
      await (chatService ?? const AiChatService())
          .send(
            model: selected,
            messages: [
              AiChatMessage(
                id: 'model_health_${DateTime.now().microsecondsSinceEpoch}',
                role: 'user',
                content: '连接检测：只回复 OK',
                createdAt: DateTime.now(),
              ),
            ],
          )
          .timeout(const Duration(seconds: 90));
    } on Object catch (error) {
      chatError = error;
    }
    imageWatch.start();
    try {
      if (imageProbe != null) {
        await imageProbe(selected).timeout(const Duration(minutes: 3));
      } else {
        await AiDesignService.instance
            .generateImage(
              prompt: '模型连接检测：一颗红色拼豆，白色背景，极简像素图',
              size: '1024x1024',
              model: selected,
            )
            .timeout(const Duration(minutes: 3));
      }
    } on Object catch (error) {
      imageError = error;
    }
    imageWatch.stop();
    if (serial != _selectedModelCheckSerial) return;

    _selectedModelCheckedAt = DateTime.now();
    if (chatError == null && imageError == null) {
      _selectedModelState = AiSelectedModelHealthState.healthy;
      _selectedModelMessage = null;
    } else {
      _selectedModelState = AiSelectedModelHealthState.unhealthy;
      final chatDetail = chatError == null
          ? '可用（${_durationText(chatWatch.elapsed)}）'
          : AppErrorClassifier.classify(
              chatError,
              operation: 'AI 对话模型后台检测',
            ).displayText;
      final imageDetail = imageError == null
          ? '可用（${_durationText(imageWatch.elapsed)}）'
          : AppErrorClassifier.classify(
              imageError,
              operation: 'AI 图片模型后台检测',
            ).displayText;
      _selectedModelMessage =
          '模型 $selected 后台检测未全部通过\n'
          'AI 对话模型：$chatDetail\n'
          'AI 图片模型：$imageDetail';
    }
    notifyListeners();
  }

  static String _durationText(Duration duration) {
    if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds} 毫秒';
    }
    return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} 秒';
  }

  Future<void> check({bool silent = false}) =>
      _checking ??= _check(silent: silent).whenComplete(() => _checking = null);

  Future<void> _check({required bool silent}) async {
    final settings = AppSettings.instance;
    final configured =
        settings.aiProxyBaseUrl.trim().isNotEmpty ||
        (settings.aiProviderBaseUrl.trim().isNotEmpty &&
            settings.aiProviderKey.trim().isNotEmpty);
    if (!configured) {
      _state = AiApiHealthState.unconfigured;
      _error = AppErrorClassifier.classify(
        StateError('尚未配置 API 地址和密钥'),
        operation: 'AI 服务',
      );
      _balance = null;
      _checkedAt = DateTime.now();
      notifyListeners();
      return;
    }
    if (!silent) {
      _state = AiApiHealthState.checking;
      notifyListeners();
    }
    try {
      await const AiChatService().loadCatalog();
      _state = AiApiHealthState.healthy;
      _error = null;
      _checkedAt = DateTime.now();
      notifyListeners();
      try {
        _balance = await const AiChatService().loadBalance();
      } on Object {
        _balance = const AiBalanceInfo(available: false);
      }
      notifyListeners();
    } on Object catch (error) {
      _state = AiApiHealthState.unhealthy;
      _error = AppErrorClassifier.classify(error, operation: 'AI 服务检测');
      _balance = null;
      _checkedAt = DateTime.now();
      notifyListeners();
    }
  }
}

class AiApiStatusBanner extends StatefulWidget {
  const AiApiStatusBanner({
    super.key,
    required this.onOpenSettings,
    this.compact = false,
  });

  final VoidCallback onOpenSettings;
  final bool compact;

  @override
  State<AiApiStatusBanner> createState() => _AiApiStatusBannerState();
}

class _AiApiStatusBannerState extends State<AiApiStatusBanner> {
  String? _dismissedSignature;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: AiApiHealthService.instance,
    builder: (context, _) {
      final health = AiApiHealthService.instance;
      final selectedModelFailed =
          health.selectedModelState == AiSelectedModelHealthState.unhealthy;
      if (health.state == AiApiHealthState.healthy && !selectedModelFailed) {
        return const SizedBox.shrink();
      }
      final checking =
          !selectedModelFailed && health.state == AiApiHealthState.checking;
      final text = selectedModelFailed
          ? health.selectedModelMessage ?? '当前选择的 AI 模型不可用'
          : checking
          ? '正在实时检测 AI API…'
          : health.error?.displayText ?? 'AI API 当前不可用';
      final signature = selectedModelFailed
          ? 'selected|${health.selectedModel}|$text|${health.selectedModelCheckedAt}'
          : '${health.state.name}|$text|${health.checkedAt}';
      if (_dismissedSignature == signature) return const SizedBox.shrink();
      return Material(
        color: checking ? const Color(0xFFFFF2CC) : const Color(0xFFFFDAD6),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: widget.compact ? 7 : 10,
          ),
          child: Row(
            children: [
              Icon(
                checking ? Icons.sync_rounded : Icons.error_outline_rounded,
                color: checking
                    ? const Color(0xFF7A5900)
                    : const Color(0xFFBA1A1A),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  text,
                  maxLines: widget.compact ? 4 : 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: widget.onOpenSettings,
                child: const Text('去配置'),
              ),
              TextButton(
                key: const ValueKey('dismissAiApiStatusBanner'),
                onPressed: () =>
                    setState(() => _dismissedSignature = signature),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
