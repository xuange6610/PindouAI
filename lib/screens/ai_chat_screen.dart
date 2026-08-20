import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../services/ai_attachment_reader.dart';
import '../services/ai_api_health_service.dart';
import '../services/ai_chat_service.dart';
import '../services/ai_chat_store.dart';
import '../services/ai_design_service.dart';
import '../services/ai_design_history.dart';
import '../services/ai_generated_artifact.dart';
import '../services/ai_model_profile.dart';
import '../services/ai_usage_store.dart';
import '../services/app_settings.dart';
import '../services/app_error.dart';
import '../services/app_notice_center.dart';
import '../services/export_service.dart';
import '../services/project_repository.dart';
import '../theme/app_theme.dart';
import 'api_settings_screen.dart';
import 'ai_usage_screen.dart';

enum _ChatHistoryFilter {
  all('全部', Icons.forum_outlined),
  images('图片', Icons.image_outlined),
  files('文件', Icons.description_outlined),
  videos('视频', Icons.movie_outlined),
  audio('音频', Icons.audio_file_outlined);

  const _ChatHistoryFilter(this.label, this.icon);

  final String label;
  final IconData icon;
}

String _formatChatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _conversationTimingSummary(AiChatConversation conversation) {
  AiChatMessage? latestQuestion;
  AiChatMessage? latestAnswer;
  for (final message in conversation.messages) {
    if (message.role == 'user') latestQuestion = message;
    if (message.role == 'assistant') latestAnswer = message;
  }
  final values = <String>[
    if (latestQuestion != null)
      '提问 ${_formatChatDateTime(latestQuestion.createdAt)}',
    if (latestAnswer != null)
      '答复 ${_formatChatDateTime(latestAnswer.createdAt)}',
  ];
  return values.isEmpty ? '暂无提问或答复时间' : values.join(' · ');
}

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({
    super.key,
    this.service,
    this.requestTimeout = const Duration(minutes: 3),
    this.onProjectsChanged,
  });

  final AiChatService? service;
  final Duration requestTimeout;
  final Future<void> Function()? onProjectsChanged;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with WidgetsBindingObserver {
  final _store = AiChatStore();
  late final AiChatService _gateway;
  final _usageStore = const AiUsageStore();
  final _exporter = ExportService();
  final _aiImageHistory = const AiDesignHistoryStore();
  final _projects = ProjectRepository();
  final _picker = ImagePicker();
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final _captureKey = GlobalKey();
  var _conversations = <AiChatConversation>[];
  AiChatConversation? _current;
  AiChatAttachment? _pendingAttachment;
  var _models = <String>[];
  var _imageModels = <String>[];
  var _videoModels = <String>[];
  String? _modelError;
  var _loadingModels = true;
  var _sendStarting = false;
  var _sending = false;
  var _imageMode = false;
  var _videoMode = false;
  var _refreshingCatalog = false;
  String? _backendActiveModel;
  String? _recommendedChatModel;
  String? _recommendedImageModel;
  String? _recommendedVideoModel;
  String? _chatRecommendationReason;
  String? _imageRecommendationReason;
  String? _videoRecommendationReason;
  String? _modelSyncMessage;
  Timer? _modelScanTimer;
  Timer? _settingsRefreshTimer;
  Timer? _elapsedTimer;
  AiChatCancelToken? _cancelToken;
  AiUsageStats _usage = const AiUsageStats();
  String _deviceIp = '检测中…';
  var _currentElapsedMs = 0;
  var _operationSerial = 0;
  String _streamingText = '';
  String _streamingReasoning = '';
  final _selectedConversationIds = <String>{};
  final _selectedMessageIds = <String>{};
  final _savingProjectPaths = <String>{};
  var _historySelecting = false;
  var _historyFilter = _ChatHistoryFilter.all;
  var _scrollRequestSerial = 0;

  List<String> get _selectableModels => _videoMode
      ? _videoModels
      : _imageMode
      ? _imageModels
      : _models;

  String? get _recommendedModel => _videoMode
      ? _recommendedVideoModel
      : _imageMode
      ? _recommendedImageModel
      : _recommendedChatModel;

  String? get _recommendationReason => _videoMode
      ? _videoRecommendationReason
      : _imageMode
      ? _imageRecommendationReason
      : _chatRecommendationReason;

  List<AiChatConversation> get _filteredConversations => _conversations
      .where((conversation) => _matchesHistoryFilter(conversation))
      .toList(growable: false);

  bool _matchesHistoryFilter(AiChatConversation conversation) {
    if (_historyFilter == _ChatHistoryFilter.all) return true;
    final attachments = conversation.messages
        .map((message) => message.attachment)
        .whereType<AiChatAttachment>();
    return switch (_historyFilter) {
      _ChatHistoryFilter.all => true,
      _ChatHistoryFilter.images => attachments.any((value) => value.isImage),
      _ChatHistoryFilter.videos => attachments.any((value) => value.isVideo),
      _ChatHistoryFilter.audio => attachments.any((value) => value.isAudio),
      _ChatHistoryFilter.files => attachments.any(
        (value) => !value.isImage && !value.isVideo && !value.isAudio,
      ),
    };
  }

  @override
  void initState() {
    super.initState();
    _gateway = widget.service ?? const AiChatService();
    WidgetsBinding.instance.addObserver(this);
    AppSettings.instance.addListener(_settingsChanged);
    _modelScanTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_loadModels(silent: true));
    });
    unawaited(_initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppSettings.instance.removeListener(_settingsChanged);
    _modelScanTimer?.cancel();
    _settingsRefreshTimer?.cancel();
    _elapsedTimer?.cancel();
    _cancelToken?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadModels(silent: true));
    }
  }

  @override
  void didChangeMetrics() {
    if (_sending) _scrollToBottom(immediate: true);
  }

  void _settingsChanged() {
    _settingsRefreshTimer?.cancel();
    _settingsRefreshTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_loadModels(silent: true));
    });
  }

  Future<void> _initialize() async {
    final conversations = await _store.load();
    if (!mounted) return;
    setState(() {
      _conversations = conversations;
      _current = conversations.firstOrNull;
    });
    unawaited(_loadSupplementalStats());
    await _loadModels();
  }

  Future<void> _loadSupplementalStats() async {
    final values = await Future.wait<Object>([
      _usageStore.load(),
      _readDeviceIp(),
    ]);
    if (!mounted) return;
    setState(() {
      _usage = values[0] as AiUsageStats;
      _deviceIp = values[1] as String;
    });
  }

  Future<String> _readDeviceIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final candidates = <({String address, int score})>[];
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        for (final address in interface.addresses) {
          final value = address.address;
          if (address.isLoopback ||
              value.isEmpty ||
              value.startsWith('169.254.')) {
            continue;
          }
          var score = 0;
          if (name.contains('wlan') || name.contains('wifi')) score += 50;
          if (name.contains('eth')) score += 40;
          if (name.contains('rmnet') || name.contains('mobile')) score += 30;
          if (value.startsWith('192.168.')) score += 20;
          if (value.startsWith('10.')) score += 15;
          if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(value)) {
            score += 15;
          }
          if (name.contains('virtual') ||
              name.contains('vmnet') ||
              name.contains('docker') ||
              name.contains('loopback')) {
            score -= 100;
          }
          candidates.add((address: value, score: score));
        }
      }
      candidates.sort((a, b) => b.score.compareTo(a.score));
      if (candidates.isNotEmpty) return candidates.first.address;
    } on Object {
      // Some platforms do not expose interface information to applications.
    }
    return '不可用';
  }

  Future<void> _loadModels({bool silent = false}) async {
    if (_refreshingCatalog) return;
    _refreshingCatalog = true;
    if (mounted && !silent) {
      setState(() {
        _loadingModels = true;
        _modelError = null;
      });
    }
    try {
      final catalog = await _gateway.loadCatalog();
      if (!mounted) return;
      final canonicalCatalogModels = catalog.models
          .map(AppSettings.normalizeAiModelId)
          .toSet()
          .toList(growable: false);
      final chatModels = canonicalCatalogModels
          .where(_isLikelyChatModel)
          .toList();
      final models = chatModels.isEmpty ? canonicalCatalogModels : chatModels;
      final chatRecommendation = recommendAiModel(
        models,
        localUsage: _usage.modelSummaries,
      );
      final settings = AppSettings.instance;
      final configured = settings.aiChatModel.trim();
      final active = catalog.activeModel;
      final selected = models.contains(configured)
          ? configured
          : chatRecommendation?.model ??
                (active != null && models.contains(active)
                    ? active
                    : models.firstOrNull ?? configured);
      if (selected.isNotEmpty && selected != configured) {
        await settings.setAiModels(selected);
      }
      var updatedConversation = _current;
      if (updatedConversation != null &&
          selected.isNotEmpty &&
          updatedConversation.model != selected) {
        updatedConversation = updatedConversation.copyWith(
          model: selected,
          updatedAt: DateTime.now(),
        );
        await _store.save(updatedConversation);
      }
      if (!mounted) return;
      setState(() {
        _models = models;
        _imageModels = _withSelectedModel(canonicalCatalogModels, selected);
        _videoModels = _withSelectedModel(canonicalCatalogModels, selected);
        _backendActiveModel = active;
        _recommendedChatModel = chatRecommendation?.model;
        _recommendedImageModel = chatRecommendation?.model ?? selected;
        _recommendedVideoModel = chatRecommendation?.model ?? selected;
        _chatRecommendationReason = chatRecommendation?.reason;
        _imageRecommendationReason = '当前中转模型目录的综合推荐；仅在原选择已失效时自动切换';
        _videoRecommendationReason = '当前中转模型目录的综合推荐；仅在原选择已失效时自动切换';
        if (updatedConversation != null) {
          _replaceConversation(updatedConversation);
        }
        _loadingModels = false;
        _modelError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      final info = AppErrorClassifier.classify(error, operation: '模型检测');
      final configured = AppSettings.instance.aiChatModel.trim();
      setState(() {
        _models = configured.isEmpty ? [] : [configured];
        final image = AppSettings.instance.aiImageModel.trim();
        final video = AppSettings.instance.aiVideoModel.trim();
        _imageModels = image.isEmpty ? [] : [image];
        _videoModels = video.isEmpty ? [] : [video];
        _modelError = info.displayText;
        _loadingModels = false;
      });
      if (!silent) {
        AppNoticeCenter.instance.showError(
          error,
          operation: '模型检测',
          openApiSettings: _openApiSettings,
        );
      }
    } finally {
      _refreshingCatalog = false;
    }
  }

  String get _selectedModel {
    if (_videoMode) {
      final configured = AppSettings.instance.aiVideoModel.trim();
      return configured.isNotEmpty
          ? configured
          : _videoModels.firstOrNull ?? '';
    }
    if (_imageMode) {
      final configured = AppSettings.instance.aiImageModel.trim();
      return configured.isNotEmpty
          ? configured
          : _imageModels.firstOrNull ?? '';
    }
    final configured = AppSettings.instance.aiChatModel.trim();
    if (configured.isNotEmpty &&
        (_models.isEmpty || _models.contains(configured))) {
      return configured;
    }
    final conversationModel = _current?.model.trim() ?? '';
    if (conversationModel.isNotEmpty && _models.contains(conversationModel)) {
      return conversationModel;
    }
    return _models.firstOrNull ?? '';
  }

  static bool _isLikelyChatModel(String model) {
    final value = model.toLowerCase();
    return !value.contains('embedding') &&
        !value.contains('image') &&
        !value.contains('dall-e') &&
        !isLikelyVideoGenerationModel(model) &&
        !value.contains('whisper') &&
        !value.contains('tts') &&
        !value.contains('moderation');
  }

  static List<String> _withSelectedModel(List<String> models, String selected) {
    final result = [...models];
    if (selected.isNotEmpty && !result.contains(selected)) {
      result.insert(0, selected);
    }
    return result;
  }

  void _newConversation() {
    setState(() {
      _current = null;
      _selectedMessageIds.clear();
      _pendingAttachment = null;
      _composer.clear();
    });
  }

  Future<void> _clearCurrentConversation() async {
    final current = _current;
    if (current == null || current.messages.isEmpty || _sending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空当前聊天？'),
        content: Text('将永久删除“${current.title}”中的全部消息和本地附件，聊天标题会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('一键清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final empty = current.copyWith(
      messages: const [],
      updatedAt: DateTime.now(),
    );
    await _store.delete(current.id);
    await _store.save(empty);
    if (!mounted) return;
    setState(() {
      _replaceConversation(empty);
      _selectedMessageIds.clear();
    });
    AppNoticeCenter.instance.show('当前聊天已清空', kind: AppNoticeKind.success);
  }

  Future<bool> _confirmDeleteMessage(AiChatMessage message) async {
    if (_sending) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除这条消息？'),
            content: const Text('消息及其本地附件将永久删除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteMessages(Set<String> ids) async {
    final current = _current;
    if (current == null || ids.isEmpty || _sending) return;
    final updated = current.copyWith(
      updatedAt: DateTime.now(),
      messages: current.messages
          .where((message) => !ids.contains(message.id))
          .toList(),
    );
    await _store.save(updated);
    if (!mounted) return;
    setState(() {
      _replaceConversation(updated);
      _selectedMessageIds.removeAll(ids);
    });
  }

  void _dismissMessage(String id) {
    final current = _current;
    if (current == null) return;
    final updated = current.copyWith(
      updatedAt: DateTime.now(),
      messages: current.messages.where((message) => message.id != id).toList(),
    );
    setState(() {
      _replaceConversation(updated);
      _selectedMessageIds.remove(id);
    });
    unawaited(_store.save(updated));
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量删除消息？'),
        content: Text('选中的 ${_selectedMessageIds.length} 条消息将永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteMessages({..._selectedMessageIds});
  }

  void _toggleMessageSelection(String id) {
    setState(() {
      if (!_selectedMessageIds.add(id)) _selectedMessageIds.remove(id);
    });
  }

  Future<void> _deleteSelectedConversations() async {
    if (_selectedConversationIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量删除聊天？'),
        content: Text('选中的 ${_selectedConversationIds.length} 个聊天及附件将永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('批量删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ids = {..._selectedConversationIds};
    await _store.deleteMany(ids);
    if (!mounted) return;
    setState(() {
      _conversations.removeWhere((value) => ids.contains(value.id));
      if (ids.contains(_current?.id)) _current = _conversations.firstOrNull;
      _selectedConversationIds.clear();
      _historySelecting = false;
    });
  }

  Future<void> _exportConversationBackup({bool selectedOnly = false}) async {
    try {
      await _store.shareBackup(
        conversationIds: selectedOnly ? _selectedConversationIds : null,
      );
    } on Object catch (error) {
      AppNoticeCenter.instance.showError(error, operation: '导出聊天备份');
    }
  }

  Future<void> _importConversationBackup() async {
    try {
      final imported = await _store.pickAndImportBackup();
      if (imported == null) return;
      final conversations = await _store.load();
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _current ??= conversations.firstOrNull;
      });
      AppNoticeCenter.instance.show(
        '已导入 $imported 个聊天',
        kind: AppNoticeKind.success,
      );
    } on Object catch (error) {
      AppNoticeCenter.instance.showError(error, operation: '导入聊天备份');
    }
  }

  Future<void> _selectModel() async {
    if (_selectableModels.isEmpty) {
      await _loadModels();
      return;
    }
    final availableModels = [..._selectableModels];
    final controller = TextEditingController();
    var query = '';
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = availableModels
              .where(
                (model) => model.toLowerCase().contains(query.toLowerCase()),
              )
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '搜索网关可用模型',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) =>
                          setSheetState(() => query = value.trim()),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final model = filtered[index];
                        final selected = model == _selectedModel;
                        return ListTile(
                          leading: Icon(
                            selected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                          ),
                          title: Row(
                            children: [
                              Expanded(child: Text(model)),
                              if (model == _recommendedModel)
                                const _RecommendedBadge(),
                            ],
                          ),
                          subtitle: model == _recommendedModel
                              ? Text(
                                  _recommendationReason ?? '当前综合推荐',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          selected: selected,
                          onTap: () => Navigator.pop(context, model),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    // The modal future resolves while its reverse transition can still paint
    // the search field. Dispose after that transition instead of invalidating
    // the controller during the final frame.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 400)).then((_) {
        controller.dispose();
      }),
    );
    if (selected == null) return;
    await AppSettings.instance.setAiModels(selected);
    final current = _current;
    if (current != null) {
      final updated = current.copyWith(
        model: selected,
        updatedAt: DateTime.now(),
      );
      await _store.save(updated);
      if (mounted) setState(() => _replaceConversation(updated));
    } else if (mounted) {
      setState(() {});
    }
    AppNoticeCenter.instance.show(
      '已切换为 $selected，对话、图片和视频模型已同步',
      kind: AppNoticeKind.success,
    );
    unawaited(
      AiApiHealthService.instance.checkSelectedModelCapabilities(
        model: selected,
        chatService: _gateway,
      ),
    );
  }

  void _openApiSettings() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const ApiSettingsScreen()));
  }

  Future<void> _pickAttachment() async {
    try {
      final selected = await openFile();
      if (selected == null) return;
      final attachment = await _store.importAttachment(selected);
      if (mounted) setState(() => _pendingAttachment = attachment);
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('无法添加附件：$error')),
      );
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final selected = await _picker.pickImage(
        source: source,
        imageQuality: 100,
        requestFullMetadata: false,
      );
      if (selected == null) return;
      final attachment = await _store.importAttachment(selected);
      if (mounted) setState(() => _pendingAttachment = attachment);
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('无法添加图片：$error')),
      );
    }
  }

  Future<void> _chooseMediaMode() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: const Text('AI 对话'),
              trailing: !_imageMode && !_videoMode
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(context, 'chat'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('AI 图片'),
              subtitle: Text('使用独立图片模型：${AppSettings.instance.aiImageModel}'),
              trailing: _imageMode ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.movie_creation_outlined),
              title: const Text('AI 视频'),
              subtitle: Text('使用独立视频模型：${AppSettings.instance.aiVideoModel}'),
              trailing: _videoMode ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _imageMode = selected == 'image';
      _videoMode = selected == 'video';
    });
  }

  void _stopCurrentRequest() {
    if (!_sending) return;
    _operationSerial++;
    _cancelToken?.cancel();
    _cancelToken = null;
    _elapsedTimer?.cancel();
    setState(() => _sending = false);
    AppNoticeCenter.instance.showSnackBar(
      const SnackBar(content: Text('已强制停止本次对话和思考')),
    );
  }

  Future<List<AiChatMessage>> _requestMessages(
    AiChatConversation conversation,
  ) async {
    if (!AppSettings.instance.aiMemoryEnabled) {
      return [conversation.messages.last];
    }
    final otherMessages =
        _conversations
            .where((value) => value.id != conversation.id)
            .expand((value) => value.messages)
            .where(
              (message) =>
                  (message.role == 'user' || message.role == 'assistant') &&
                  message.content.trim().isNotEmpty,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final recent = otherMessages.length <= 40
        ? otherMessages
        : otherMessages.sublist(otherMessages.length - 40);
    final memoryText = recent
        .map(
          (message) =>
              '${message.role == 'user' ? '用户' : 'AI'}：${message.content}',
        )
        .join('\n');
    final limitedMemory = memoryText.length <= 50000
        ? memoryText
        : memoryText.substring(memoryText.length - 50000);
    return [
      if (limitedMemory.isNotEmpty)
        AiChatMessage(
          id: 'local_memory',
          role: 'system',
          content: '以下是用户允许保存于本机的历史对话记忆。仅在与当前问题有关时使用：\n$limitedMemory',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        ),
      ...conversation.messages,
    ];
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    final attachment = _pendingAttachment;
    await _submitRequest(text, attachment);
  }

  String _requestModeFor(AiChatMessage message) {
    if (message.requestMode case final String mode
        when mode == 'chat' || mode == 'image' || mode == 'video') {
      return mode;
    }
    final messages = _current?.messages ?? const <AiChatMessage>[];
    final index = messages.indexWhere((value) => value.id == message.id);
    if (index >= 0) {
      for (var next = index + 1; next < messages.length; next++) {
        final following = messages[next];
        if (following.role == 'user') break;
        final attachment = following.attachment;
        if (attachment?.isVideo == true) return 'video';
        if (attachment?.isImage == true) return 'image';
      }
    }
    return 'chat';
  }

  Future<void> _resendMessage(AiChatMessage message) async {
    if (_sending || _sendStarting || message.role != 'user') return;
    final attachment = message.attachment;
    if (attachment != null && !await File(attachment.path).exists()) {
      AppNoticeCenter.instance.show(
        '原问题的附件已不存在，无法完整重新发送。请重新选择附件后再试。',
        kind: AppNoticeKind.error,
      );
      return;
    }
    final mode = _requestModeFor(message);
    if (mounted) {
      setState(() {
        _imageMode = mode == 'image';
        _videoMode = mode == 'video';
      });
    }
    await _submitRequest(
      message.content,
      attachment,
      requestMode: mode,
      requestedModel: message.model,
      clearComposer: false,
    );
  }

  Future<void> _submitRequest(
    String text,
    AiChatAttachment? attachment, {
    String? requestMode,
    String? requestedModel,
    bool clearComposer = true,
  }) async {
    if (_sending || _sendStarting || (text.isEmpty && attachment == null)) {
      return;
    }
    _sendStarting = true;
    if (mounted) setState(() {});
    try {
      await _sendOnce(
        text,
        attachment,
        requestMode: requestMode,
        requestedModel: requestedModel,
        clearComposer: clearComposer,
      );
    } finally {
      _sendStarting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _sendOnce(
    String text,
    AiChatAttachment? attachment, {
    String? requestMode,
    String? requestedModel,
    required bool clearComposer,
  }) async {
    await _loadModels(silent: true);
    if (!mounted) return;
    final mode = switch (requestMode) {
      'image' => 'image',
      'video' => 'video',
      'chat' => 'chat',
      _ =>
        _imageMode
            ? 'image'
            : _videoMode
            ? 'video'
            : 'chat',
    };
    final originalModel = requestedModel?.trim() ?? '';
    final model = originalModel.isEmpty ? _selectedModel : originalModel;
    if (model.isEmpty) {
      AppNoticeCenter.instance.show(
        '没有可用模型，请先配置并检测 API。',
        kind: AppNoticeKind.error,
        actionLabel: '配置 API',
        onAction: _openApiSettings,
      );
      return;
    }
    var conversation = _current;
    final now = DateTime.now();
    conversation ??= AiChatConversation(
      id: now.microsecondsSinceEpoch.toString(),
      title: _titleFor(text, attachment?.name),
      model: AppSettings.instance.aiChatModel,
      createdAt: now,
      updatedAt: now,
      messages: const [],
    );
    final userMessage = AiChatMessage(
      id: '${now.microsecondsSinceEpoch}_user',
      role: 'user',
      content: text.isEmpty ? '请分析这个附件' : text,
      createdAt: now,
      attachment: attachment,
      model: model,
      requestMode: mode,
    );
    conversation = conversation.copyWith(
      model: mode == 'chat' ? model : conversation.model,
      updatedAt: now,
      messages: [...conversation.messages, userMessage],
    );
    await _store.save(conversation);
    if (!mounted) return;
    setState(() {
      _replaceConversation(conversation!);
      if (clearComposer) {
        _composer.clear();
        _pendingAttachment = null;
      }
      _sending = true;
      _currentElapsedMs = 0;
      _streamingText = '';
      _streamingReasoning = '';
    });
    _scrollToBottom(immediate: true);
    final stopwatch = Stopwatch()..start();
    final operation = ++_operationSerial;
    final cancelToken = AiChatCancelToken();
    _cancelToken = cancelToken;
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _sending && operation == _operationSerial) {
        setState(() => _currentElapsedMs = stopwatch.elapsedMilliseconds);
      }
    });
    try {
      AiChatMessage assistant;
      var inputTokens = 0;
      var outputTokens = 0;
      var totalTokens = 0;
      late String actualModel;
      if (mode == 'image') {
        if (attachment != null && !attachment.isImage) {
          throw const FormatException('AI 画图模式只支持图片参考附件');
        }
        final result = await AiDesignService.instance.generateImage(
          prompt: userMessage.content,
          imageBytes: attachment == null
              ? null
              : await File(attachment.path).readAsBytes(),
          model: model,
        );
        if (operation != _operationSerial || !mounted) return;
        final generatedId = DateTime.now().microsecondsSinceEpoch.toString();
        final generated = await _store.saveAttachmentBytes(
          result.bytes,
          name: 'AI生成_$generatedId.png',
          mimeType: 'image/png',
        );
        try {
          await _aiImageHistory.saveImage(
            AiDesignHistoryEntry(
              id: 'chat_$generatedId',
              prompt: userMessage.content,
              content: '通过 AI 聊天生成的图片',
              model: result.model,
              createdAt: DateTime.now(),
              styleId: 'ai_chat',
            ),
            result.bytes,
          );
        } on Object catch (error) {
          // The chat image remains usable even if the secondary gallery index
          // cannot be updated on a damaged or full storage device.
          debugPrint('Unable to add AI chat image to history: $error');
        }
        assistant = AiChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}_assistant',
          role: 'assistant',
          content: '图片已生成，可打开预览或继续作为参考图对话。',
          createdAt: DateTime.now(),
          attachment: generated,
          model: result.model,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
        actualModel = result.model;
        if (actualModel != model) {
          if (!_imageModels.contains(actualModel)) {
            _imageModels.add(actualModel);
          }
          _modelSyncMessage = '中转后台实际返回模型 $actualModel；已保留你选择的模型 $model。';
        }
      } else if (mode == 'video') {
        if (attachment != null && !attachment.isImage) {
          throw const FormatException('AI 视频模式只支持图片参考附件');
        }
        final result = await AiDesignService.instance.generateVideo(
          prompt: userMessage.content,
          imageBytes: attachment == null
              ? null
              : await File(attachment.path).readAsBytes(),
          model: model,
        );
        if (operation != _operationSerial || !mounted) return;
        final generated = await _store.saveAttachmentBytes(
          result.bytes,
          name:
              'AI视频_${DateTime.now().millisecondsSinceEpoch}.${result.extension}',
          mimeType: result.mimeType,
        );
        assistant = AiChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}_assistant',
          role: 'assistant',
          content: '视频已生成，可打开播放预览或下载保存。',
          createdAt: DateTime.now(),
          attachment: generated,
          model: result.model,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
        actualModel = result.model;
        if (actualModel != model) {
          if (!_videoModels.contains(actualModel)) {
            _videoModels.add(actualModel);
          }
          _modelSyncMessage = '中转后台实际返回模型 $actualModel；已保留你选择的模型 $model。';
        }
      } else {
        final reply = await _gateway
            .send(
              model: model,
              messages: await _requestMessages(conversation),
              cancelToken: cancelToken,
              onDelta: (delta) {
                if (!mounted || operation != _operationSerial) return;
                setState(() => _streamingText += delta);
                _scrollToBottom();
              },
              onReasoningDelta: (delta) {
                if (!mounted || operation != _operationSerial) return;
                setState(() => _streamingReasoning += delta);
                _scrollToBottom();
              },
            )
            .timeout(
              widget.requestTimeout,
              onTimeout: () {
                cancelToken.cancel();
                throw const AiChatTimeoutException();
              },
            );
        if (operation != _operationSerial || !mounted) return;
        actualModel = reply.model.trim().isEmpty ? model : reply.model.trim();
        inputTokens = reply.inputTokens;
        outputTokens = reply.outputTokens;
        totalTokens = reply.totalTokens;
        if (actualModel != model) {
          if (!_models.contains(actualModel)) _models.add(actualModel);
          _backendActiveModel = actualModel;
          _modelSyncMessage = '中转后台实际返回 $actualModel；已保留你选择的模型 $model。';
        }
        assistant = AiChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}_assistant',
          role: 'assistant',
          content: reply.content,
          createdAt: DateTime.now(),
          model: actualModel,
          reasoning: reply.reasoning,
          elapsedMs: stopwatch.elapsedMilliseconds,
          inputTokens: inputTokens,
          outputTokens: outputTokens,
          totalTokens: totalTokens,
        );
        if (mounted) setState(() {});
        // Keep the user's requested model as the conversation selection. The
        // provider may return an internal routing alias, but that alias must
        // not change the next request or the visible model selector.
        conversation = conversation.copyWith(model: model);
      }
      conversation = conversation.copyWith(
        updatedAt: DateTime.now(),
        messages: [...conversation.messages, assistant],
      );
      await _store.save(conversation);
      final usage = await _usageStore.record(
        model: actualModel,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: totalTokens,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      if (mounted && operation == _operationSerial) {
        setState(() {
          _usage = usage;
          _currentElapsedMs = stopwatch.elapsedMilliseconds;
          _replaceConversation(conversation!);
        });
      }
    } on AiChatCancelledException {
      // User-requested stops are already acknowledged by _stopCurrentRequest.
    } on AiChatTimeoutException catch (error) {
      if (!mounted || operation != _operationSerial) return;
      unawaited(
        _usageStore
            .recordFailure(
              model: model,
              elapsedMs: stopwatch.elapsedMilliseconds,
              operation: mode == 'image'
                  ? 'AI 生图'
                  : mode == 'video'
                  ? 'AI 视频'
                  : 'AI 聊天',
              errorCategory: AppErrorCategory.timeout.label,
            )
            .then((usage) {
              if (mounted) setState(() => _usage = usage);
            }),
      );
      final retry = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.timer_off_outlined),
          title: const Text('AI 响应超时'),
          content: Text('$error\n\n是否使用刚才的原问题重新发起提问？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('暂不重试'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('重新提问'),
            ),
          ],
        ),
      );
      if (retry == true && mounted) {
        final timedOutConversation = conversation!;
        final remaining = timedOutConversation.messages
            .where((message) => message.id != userMessage.id)
            .toList();
        conversation = timedOutConversation.copyWith(
          updatedAt: DateTime.now(),
          messages: remaining,
        );
        await _store.save(conversation);
        if (!mounted) return;
        setState(() {
          _replaceConversation(conversation!);
          _imageMode = mode == 'image';
          _videoMode = mode == 'video';
        });
        unawaited(
          Future<void>.delayed(
            Duration.zero,
            () => _submitRequest(
              text,
              attachment,
              requestMode: mode,
              requestedModel: model,
              clearComposer: false,
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted && operation == _operationSerial) {
        final info = AppNoticeCenter.instance.showError(
          error,
          operation: mode == 'image'
              ? 'AI 生图'
              : mode == 'video'
              ? 'AI 视频'
              : 'AI 对话',
          openApiSettings: _openApiSettings,
        );
        _usage = await _usageStore.recordFailure(
          model: model,
          elapsedMs: stopwatch.elapsedMilliseconds,
          operation: mode == 'image'
              ? 'AI 生图'
              : mode == 'video'
              ? 'AI 视频'
              : 'AI 聊天',
          errorCategory: info.category.label,
        );
        if (mounted) setState(() {});
      }
    } finally {
      stopwatch.stop();
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
      _elapsedTimer?.cancel();
      if (mounted && operation == _operationSerial) {
        setState(() {
          _currentElapsedMs = stopwatch.elapsedMilliseconds;
          _sending = false;
          _streamingText = '';
          _streamingReasoning = '';
        });
      }
      _scrollToBottom();
    }
  }

  void _replaceConversation(AiChatConversation conversation) {
    _current = conversation;
    _conversations.removeWhere((value) => value.id == conversation.id);
    _conversations.insert(0, conversation);
  }

  Future<void> _deleteConversation(AiChatConversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除聊天？'),
        content: Text('“${conversation.title}”及其本地附件将永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(conversation.id);
    if (!mounted) return;
    setState(() {
      _conversations.removeWhere((value) => value.id == conversation.id);
      if (_current?.id == conversation.id) {
        _current = _conversations.firstOrNull;
      }
    });
  }

  Future<void> _editConversationNote(AiChatConversation conversation) async {
    final controller = TextEditingController(text: conversation.note);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('备注聊天历史'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(hintText: '例如：客户方案、代码修改'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    final updated = conversation.copyWith(
      note: value,
      updatedAt: DateTime.now(),
    );
    await _store.save(updated);
    if (!mounted) return;
    setState(() => _replaceConversation(updated));
  }

  Future<void> _chooseShare() async {
    if (_current == null) {
      AppNoticeCenter.instance.showSnackBar(
        const SnackBar(content: Text('当前没有可分享的聊天')),
      );
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.screenshot_monitor_outlined),
              title: const Text('分享当前界面截图'),
              onTap: () => Navigator.pop(context, 'screen'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('分享完整聊天记录'),
              subtitle: const Text('导出为可复制的 Markdown 文件'),
              onTap: () => Navigator.pop(context, 'record'),
            ),
          ],
        ),
      ),
    );
    if (action == 'screen') await _shareScreen();
    if (action == 'record') await _shareRecord();
  }

  Future<void> _shareScreen() async {
    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('当前界面尚未完成绘制');
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('无法生成界面截图');
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}AI聊天界面_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'AI 聊天界面'),
      );
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('分享界面失败：$error')),
      );
    }
  }

  Future<void> _shareRecord() async {
    final conversation = _current;
    if (conversation == null) return;
    final buffer = StringBuffer()
      ..writeln(
        '# ${conversation.note.isEmpty ? conversation.title : conversation.note}',
      )
      ..writeln()
      ..writeln('- 模型：${conversation.model}')
      ..writeln('- 导出时间：${DateTime.now().toLocal()}')
      ..writeln();
    for (final message in conversation.messages) {
      buffer
        ..writeln(
          message.role == 'user'
              ? '## 我（提问时间：${_formatChatDateTime(message.createdAt)}）'
              : '## AI（模型答复时间：${_formatChatDateTime(message.createdAt)}）',
        )
        ..writeln()
        ..writeln(message.content)
        ..writeln();
      if (message.attachment != null) {
        buffer.writeln('附件：${message.attachment!.name}\n');
      }
    }
    try {
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}AI聊天记录_${DateTime.now().millisecondsSinceEpoch}.md',
      );
      await file.writeAsString(buffer.toString(), flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: conversation.title),
      );
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('分享聊天记录失败：$error')),
      );
    }
  }

  Future<void> _previewAttachment(AiChatAttachment attachment) async {
    if (attachment.isImage) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _ImageAttachmentPreview(
            attachment: attachment,
            onSave: () => _saveAttachment(attachment),
          ),
        ),
      );
      return;
    }
    if (attachment.isVideo) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _VideoAttachmentPreview(
            attachment: attachment,
            onSave: () => _saveAttachment(attachment),
          ),
        ),
      );
      return;
    }
    String? content;
    Object? failure;
    try {
      content = await AiAttachmentReader.extractText(attachment);
    } on Object catch (error) {
      failure = error;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _TextAttachmentPreview(
          name: attachment.name,
          content:
              content ??
              (failure == null
                  ? '此二进制文件不支持直接显示，但仍可下载保存并交给支持该格式的模型处理。'
                  : '附件解析失败：$failure'),
          onSave: () => _saveAttachment(attachment),
        ),
      ),
    );
  }

  Future<void> _saveAttachment(AiChatAttachment attachment) async {
    try {
      final bytes = await File(attachment.path).readAsBytes();
      final path = attachment.isImage
          ? await _exporter.saveImageBytes(bytes, attachment.name)
          : await _exporter.saveDocumentBytes(
              bytes,
              attachment.name,
              mimeType: attachment.mimeType,
            );
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('已保存：$path')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    }
  }

  Future<void> _saveGeneratedImageProject(
    AiChatAttachment attachment, {
    required bool favorite,
  }) async {
    if (!attachment.isImage || _savingProjectPaths.contains(attachment.path)) {
      return;
    }
    setState(() => _savingProjectPaths.add(attachment.path));
    final sourceName = 'AI聊天/${attachment.name}';
    try {
      final summaries = await _projects.loadSummaries();
      var projectId = summaries
          .where((summary) => summary.sourceName == sourceName)
          .firstOrNull
          ?.id;
      if (projectId == null) {
        final bytes = await File(attachment.path).readAsBytes();
        final pattern = await _projects.savePhotoProject(
          bytes,
          title: attachment.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          sourceName: sourceName,
        );
        projectId = pattern.id;
      }
      if (favorite) await _projects.setFavorite(projectId, true);
      await widget.onProjectsChanged?.call();
      if (!mounted) return;
      AppNoticeCenter.instance.show(
        favorite ? 'AI 原图已直接保存到“我的作品”，并加入“我的收藏”。' : 'AI 原图已直接保存到“我的作品”。',
        kind: AppNoticeKind.success,
      );
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showError(
        error,
        operation: favorite ? '保存并收藏 AI 图片' : '保存 AI 图片到我的作品',
      );
    } finally {
      if (mounted) {
        setState(() => _savingProjectPaths.remove(attachment.path));
      }
    }
  }

  Future<void> _previewArtifact(AiGeneratedArtifact artifact) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _TextAttachmentPreview(
          name: artifact.name,
          content: artifact.content,
          onSave: () => _saveArtifact(artifact),
        ),
      ),
    );
  }

  Future<void> _saveArtifact(AiGeneratedArtifact artifact) async {
    try {
      final path = await _exporter.saveDocumentBytesAs(
        artifact.bytes,
        artifact.name,
        mimeType: _artifactMime(artifact.name),
      );
      if (path == null || !mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('生成文件已保存：$path')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('保存生成文件失败：$error')),
      );
    }
  }

  static String _artifactMime(String name) {
    final value = name.toLowerCase();
    if (value.endsWith('.html') || value.endsWith('.htm')) return 'text/html';
    if (value.endsWith('.css')) return 'text/css';
    if (value.endsWith('.js')) return 'text/javascript';
    if (value.endsWith('.json')) return 'application/json';
    if (value.endsWith('.xml')) return 'application/xml';
    if (value.endsWith('.csv')) return 'text/csv';
    return 'text/plain';
  }

  void _scrollToBottom({bool immediate = false}) {
    final request = ++_scrollRequestSerial;
    void move({bool settle = false}) {
      if (!mounted || request != _scrollRequestSerial || !_scroll.hasClients) {
        return;
      }
      final bottom = _scroll.position.maxScrollExtent;
      if (immediate || settle) {
        _scroll.jumpTo(bottom);
      } else {
        unawaited(
          _scroll
              .animateTo(
                bottom,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
              )
              .catchError((_) {}),
        );
      }
    }

    void afterFrame(int remaining) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        move(settle: true);
        if (remaining > 0) afterFrame(remaining - 1);
      });
    }

    // Move immediately to the current extent as well. This is important when
    // the user was reading old history near the top: the following frames can
    // then track the newly laid-out message/keyboard extent from the bottom.
    move();
    afterFrame(3);
  }

  @override
  Widget build(BuildContext context) {
    final messages = _current?.messages ?? const <AiChatMessage>[];
    final runtimeProfile = runtimeProfileForModel(_selectedModel);
    final requestBusy = _sending || _sendStarting;
    return RepaintBoundary(
      key: _captureKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _selectedMessageIds.isEmpty
                ? 'AI 聊天'
                : '已选 ${_selectedMessageIds.length} 条消息',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            if (_selectedMessageIds.isNotEmpty) ...[
              IconButton(
                onPressed: _deleteSelectedMessages,
                tooltip: '批量删除消息',
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              IconButton(
                onPressed: () => setState(_selectedMessageIds.clear),
                tooltip: '退出选择',
                icon: const Icon(Icons.close_rounded),
              ),
            ] else ...[
              IconButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const AiUsageScreen()),
                ),
                tooltip: '余额与消耗统计',
                icon: const Icon(Icons.query_stats_rounded),
              ),
              IconButton(
                onPressed: messages.isEmpty || requestBusy
                    ? null
                    : _clearCurrentConversation,
                tooltip: '一键清空当前聊天',
                icon: const Icon(Icons.cleaning_services_outlined),
              ),
              Builder(
                builder: (context) => IconButton(
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: '聊天历史',
                  icon: const Icon(Icons.history_rounded),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多聊天操作',
                onSelected: (value) async {
                  switch (value) {
                    case 'share':
                      await _chooseShare();
                    case 'memory':
                      await AppSettings.instance.setAiMemoryEnabled(
                        !AppSettings.instance.aiMemoryEnabled,
                      );
                      if (mounted) setState(() {});
                    case 'new':
                      _newConversation();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.ios_share_rounded),
                      title: Text('分享界面或聊天记录'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'memory',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        AppSettings.instance.aiMemoryEnabled
                            ? Icons.psychology_rounded
                            : Icons.psychology_outlined,
                        color: AppSettings.instance.aiMemoryEnabled
                            ? AppColors.teal
                            : null,
                      ),
                      title: Text(
                        AppSettings.instance.aiMemoryEnabled
                            ? '关闭聊天记忆'
                            : '开启聊天记忆',
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'new',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.add_comment_outlined),
                      title: Text('新聊天'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        endDrawer: Drawer(
          child: SafeArea(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: Text(
                    _historySelecting
                        ? '已选择 ${_selectedConversationIds.length} 个聊天'
                        : '聊天历史',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  trailing: IconButton(
                    onPressed: () => setState(() {
                      _historySelecting = !_historySelecting;
                      if (!_historySelecting) _selectedConversationIds.clear();
                    }),
                    tooltip: _historySelecting ? '退出批量管理' : '批量管理',
                    icon: Icon(
                      _historySelecting
                          ? Icons.close_rounded
                          : Icons.checklist_rounded,
                    ),
                  ),
                ),
                const Divider(height: 1),
                SizedBox(
                  height: 52,
                  child: SingleChildScrollView(
                    key: const ValueKey('chatHistoryFilterScroll'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final filter in _ChatHistoryFilter.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: ChoiceChip(
                              key: ValueKey('chatHistoryFilter_${filter.name}'),
                              avatar: Icon(filter.icon, size: 17),
                              label: Text(filter.label),
                              selected: _historyFilter == filter,
                              onSelected: (_) => setState(() {
                                _historyFilter = filter;
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _importConversationBackup,
                        tooltip: '导入聊天备份',
                        icon: const Icon(Icons.file_download_outlined),
                      ),
                      IconButton(
                        onPressed: () => _exportConversationBackup(
                          selectedOnly: _historySelecting,
                        ),
                        tooltip: _historySelecting ? '导出选中聊天' : '导出全部聊天',
                        icon: const Icon(Icons.file_upload_outlined),
                      ),
                      if (_historySelecting) ...[
                        IconButton(
                          onPressed: () => setState(() {
                            final visible = _filteredConversations;
                            final allSelected =
                                visible.isNotEmpty &&
                                visible.every(
                                  (value) => _selectedConversationIds.contains(
                                    value.id,
                                  ),
                                );
                            if (allSelected) {
                              _selectedConversationIds.removeAll(
                                visible.map((value) => value.id),
                              );
                            } else {
                              _selectedConversationIds.addAll(
                                visible.map((value) => value.id),
                              );
                            }
                          }),
                          tooltip: '全选/取消全选',
                          icon: const Icon(Icons.select_all_rounded),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _selectedConversationIds.isEmpty
                              ? null
                              : _deleteSelectedConversations,
                          tooltip: '批量删除聊天',
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _conversations.isEmpty
                      ? const Center(child: Text('还没有聊天记录'))
                      : _filteredConversations.isEmpty
                      ? Center(child: Text('没有${_historyFilter.label}历史'))
                      : ListView.builder(
                          itemCount: _filteredConversations.length,
                          itemBuilder: (context, index) {
                            final conversation = _filteredConversations[index];
                            return ListTile(
                              selected: conversation.id == _current?.id,
                              leading: _historySelecting
                                  ? Checkbox(
                                      value: _selectedConversationIds.contains(
                                        conversation.id,
                                      ),
                                      onChanged: (_) => setState(() {
                                        if (!_selectedConversationIds.add(
                                          conversation.id,
                                        )) {
                                          _selectedConversationIds.remove(
                                            conversation.id,
                                          );
                                        }
                                      }),
                                    )
                                  : null,
                              title: Text(
                                conversation.note.isEmpty
                                    ? conversation.title
                                    : conversation.note,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${conversation.note.isEmpty ? conversation.model : '${conversation.title} · ${conversation.model}'}\n'
                                '${_conversationTimingSummary(conversation)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                if (_historySelecting) {
                                  setState(() {
                                    if (!_selectedConversationIds.add(
                                      conversation.id,
                                    )) {
                                      _selectedConversationIds.remove(
                                        conversation.id,
                                      );
                                    }
                                  });
                                  return;
                                }
                                setState(() => _current = conversation);
                                Navigator.pop(context);
                                _scrollToBottom();
                              },
                              onLongPress: () => setState(() {
                                _historySelecting = true;
                                _selectedConversationIds.add(conversation.id);
                              }),
                              trailing: _historySelecting
                                  ? null
                                  : PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'note') {
                                          _editConversationNote(conversation);
                                        } else if (value == 'delete') {
                                          _deleteConversation(conversation);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'note',
                                          child: Text('备注 / 重命名'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('删除聊天'),
                                        ),
                                      ],
                                    ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            AiApiStatusBanner(onOpenSettings: _openApiSettings, compact: true),
            const _ChatBalanceStrip(),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: InkWell(
                key: const ValueKey('aiChatModelSelector'),
                onTap: _loadingModels ? null : _selectModel,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hub_outlined, color: AppColors.teal),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _loadingModels ? '正在检测模型…' : _selectedModel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (!_loadingModels &&
                                    _selectedModel == _recommendedModel) ...[
                                  const SizedBox(width: 7),
                                  const _RecommendedBadge(),
                                ],
                              ],
                            ),
                            Text(
                              _modelError == null
                                  ? _backendActiveModel == null
                                        ? '${runtimeProfile.label} · 已检测 ${_models.length} 个模型'
                                        : '${runtimeProfile.label} · 后台活动模型 $_backendActiveModel'
                                  : '模型检测失败，点击重试',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: _modelError == null
                                    ? AppColors.muted
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _loadingModels ? null : _loadModels,
                        tooltip: '重新检测模型',
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      const Icon(Icons.expand_more_rounded),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            _ChatStatsBar(
              ip: _deviceIp,
              model: _selectedModel,
              requestCount: _usage.requestCount,
              totalTokens: _usage.totalTokens,
              elapsedMs: _sending ? _currentElapsedMs : _usage.totalElapsedMs,
              isCurrentElapsed: _sending,
            ),
            const Divider(height: 1),
            if (_modelSyncMessage != null)
              MaterialBanner(
                content: Text(_modelSyncMessage!),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _modelSyncMessage = null),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            if (_imageMode)
              MaterialBanner(
                backgroundColor: const Color(0xFFFFF0E7),
                leading: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.coral,
                ),
                content: const Text(
                  '当前为 AI 画图模式：发送后会生成图片，不会返回普通文字回答。',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _imageMode = false),
                    child: const Text('退出画图'),
                  ),
                ],
              ),
            if (_videoMode)
              MaterialBanner(
                backgroundColor: const Color(0xFFEAF3FF),
                leading: const Icon(
                  Icons.movie_creation_outlined,
                  color: AppColors.teal,
                ),
                content: const Text(
                  '当前为 AI 视频模式：会把当前模型提交给中转的视频生成端点。',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _videoMode = false),
                    child: const Text('退出视频'),
                  ),
                ],
              ),
            Expanded(
              child: messages.isEmpty
                  ? const _EmptyChat()
                  : ListView.builder(
                      key: const ValueKey('aiChatMessageList'),
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                      itemCount: messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == messages.length) {
                          if (_streamingText.isNotEmpty ||
                              _streamingReasoning.isNotEmpty) {
                            return _StreamingReplyBubble(
                              content: _streamingText,
                              reasoning: _streamingReasoning,
                              elapsed: _duration(_currentElapsedMs),
                            );
                          }
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Text(
                                    '正在思考 · ${_duration(_currentElapsedMs)}',
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        final message = messages[index];
                        return Dismissible(
                          key: ValueKey('chatMessage_${message.id}'),
                          direction: requestBusy
                              ? DismissDirection.none
                              : DismissDirection.horizontal,
                          confirmDismiss: (_) => _confirmDeleteMessage(message),
                          onDismissed: (_) => _dismissMessage(message.id),
                          background: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            alignment: Alignment.centerLeft,
                            color: const Color(0xFFB3261E),
                            child: const Icon(
                              Icons.delete_rounded,
                              color: Colors.white,
                            ),
                          ),
                          secondaryBackground: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            alignment: Alignment.centerRight,
                            color: const Color(0xFFB3261E),
                            child: const Icon(
                              Icons.delete_rounded,
                              color: Colors.white,
                            ),
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPress: () =>
                                _toggleMessageSelection(message.id),
                            onTap: _selectedMessageIds.isEmpty
                                ? null
                                : () => _toggleMessageSelection(message.id),
                            child: _MessageBubble(
                              message: message,
                              selected: _selectedMessageIds.contains(
                                message.id,
                              ),
                              onPreviewAttachment: _previewAttachment,
                              onSaveAttachment: _saveAttachment,
                              onResend: message.role == 'user' && !requestBusy
                                  ? () => _resendMessage(message)
                                  : null,
                              onSaveImageToWorks: (attachment) =>
                                  _saveGeneratedImageProject(
                                    attachment,
                                    favorite: false,
                                  ),
                              onFavoriteImage: (attachment) =>
                                  _saveGeneratedImageProject(
                                    attachment,
                                    favorite: true,
                                  ),
                              savingImageProject:
                                  message.attachment != null &&
                                  _savingProjectPaths.contains(
                                    message.attachment!.path,
                                  ),
                              onPreviewArtifact: _previewArtifact,
                              onSaveArtifact: _saveArtifact,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Material(
              elevation: 4,
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_pendingAttachment != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: InputChip(
                            avatar: Icon(
                              _pendingAttachment!.isImage
                                  ? Icons.image_outlined
                                  : _pendingAttachment!.isVideo
                                  ? Icons.movie_outlined
                                  : Icons.description_outlined,
                              size: 18,
                            ),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 230),
                              child: Text(
                                _pendingAttachment!.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onDeleted: () =>
                                setState(() => _pendingAttachment = null),
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            onPressed: requestBusy ? null : _pickAttachment,
                            tooltip: '上传附件',
                            icon: const Icon(Icons.attach_file_rounded),
                          ),
                          IconButton(
                            onPressed: requestBusy
                                ? null
                                : () => _pickImage(ImageSource.gallery),
                            tooltip: '打开相册',
                            icon: const Icon(Icons.photo_library_outlined),
                          ),
                          IconButton(
                            onPressed: requestBusy
                                ? null
                                : () => _pickImage(ImageSource.camera),
                            tooltip: '拍照',
                            icon: const Icon(Icons.photo_camera_outlined),
                          ),
                          IconButton(
                            onPressed: requestBusy ? null : _chooseMediaMode,
                            tooltip: '切换 AI 对话、图片或视频模式',
                            color: _imageMode || _videoMode
                                ? AppColors.coral
                                : null,
                            icon: Icon(
                              _videoMode
                                  ? Icons.movie_creation_rounded
                                  : _imageMode
                                  ? Icons.auto_awesome_rounded
                                  : Icons.image_outlined,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _composer,
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                hintText: _videoMode
                                    ? '描述要生成的视频'
                                    : _imageMode
                                    ? '描述要生成的图片'
                                    : '发送消息',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _sending
                              ? IconButton.filled(
                                  onPressed: _stopCurrentRequest,
                                  tooltip: '强制停止',
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  icon: const Icon(Icons.stop_rounded),
                                )
                              : IconButton.filled(
                                  onPressed: _sendStarting ? null : _send,
                                  tooltip: _videoMode
                                      ? '生成视频'
                                      : _imageMode
                                      ? '生成图片'
                                      : '发送',
                                  icon: Icon(
                                    _videoMode
                                        ? Icons.movie_creation_rounded
                                        : _imageMode
                                        ? Icons.auto_awesome_rounded
                                        : Icons.arrow_upward_rounded,
                                  ),
                                ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _duration(int milliseconds) {
    final seconds = milliseconds / 1000;
    return seconds < 60
        ? '${seconds.toStringAsFixed(1)} 秒'
        : '${(seconds / 60).toStringAsFixed(1)} 分钟';
  }

  static String _titleFor(String text, String? attachmentName) {
    final source = text.trim().isEmpty ? attachmentName ?? '新聊天' : text.trim();
    return source.length <= 24 ? source : '${source.substring(0, 24)}…';
  }
}

class _StreamingReplyBubble extends StatelessWidget {
  const _StreamingReplyBubble({
    required this.content,
    required this.reasoning,
    required this.elapsed,
  });

  final String content;
  final String reasoning;
  final String elapsed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.84,
      ),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 7),
              Text(
                'AI 正在实时回答 · $elapsed',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (reasoning.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '模型返回的思考摘要（实时）',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  SelectableText(reasoning),
                ],
              ),
            ),
          if (content.isNotEmpty) SelectableText(content),
        ],
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.selected,
    required this.onPreviewAttachment,
    required this.onSaveAttachment,
    required this.onResend,
    required this.onSaveImageToWorks,
    required this.onFavoriteImage,
    required this.savingImageProject,
    required this.onPreviewArtifact,
    required this.onSaveArtifact,
  });

  final AiChatMessage message;
  final bool selected;
  final Future<void> Function(AiChatAttachment attachment) onPreviewAttachment;
  final Future<void> Function(AiChatAttachment attachment) onSaveAttachment;
  final Future<void> Function()? onResend;
  final Future<void> Function(AiChatAttachment attachment) onSaveImageToWorks;
  final Future<void> Function(AiChatAttachment attachment) onFavoriteImage;
  final bool savingImageProject;
  final Future<void> Function(AiGeneratedArtifact artifact) onPreviewArtifact;
  final Future<void> Function(AiGeneratedArtifact artifact) onSaveArtifact;

  @override
  Widget build(BuildContext context) {
    final user = message.role == 'user';
    final attachment = message.attachment;
    final artifacts = user
        ? const <AiGeneratedArtifact>[]
        : AiGeneratedArtifactParser.all(message.content);
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: user
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user
                  ? '提问时间：${_formatChatDateTime(message.createdAt)}'
                  : '模型答复时间：${_formatChatDateTime(message.createdAt)}',
              key: ValueKey('chatMessageTime_${message.id}'),
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            if (attachment != null) ...[
              if (attachment.isImage)
                GestureDetector(
                  onTap: () => onPreviewAttachment(attachment),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(attachment.path),
                      width: 260,
                      height: 180,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 80,
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                  ),
                )
              else
                InkWell(
                  onTap: () => onPreviewAttachment(attachment),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          attachment.isVideo
                              ? Icons.movie_outlined
                              : Icons.description_outlined,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            attachment.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  TextButton.icon(
                    onPressed: () => onPreviewAttachment(attachment),
                    icon: const Icon(Icons.fullscreen_rounded, size: 18),
                    label: const Text('预览'),
                  ),
                  TextButton.icon(
                    onPressed: () => onSaveAttachment(attachment),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('下载'),
                  ),
                  if (!user && attachment.isImage)
                    TextButton.icon(
                      key: ValueKey('saveAiImageToWorks_${message.id}'),
                      onPressed: savingImageProject
                          ? null
                          : () => onSaveImageToWorks(attachment),
                      icon: savingImageProject
                          ? const SizedBox.square(
                              dimension: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.collections_bookmark_outlined,
                              size: 18,
                            ),
                      label: const Text('我的作品'),
                    ),
                  if (!user && attachment.isImage)
                    TextButton.icon(
                      key: ValueKey('favoriteAiImage_${message.id}'),
                      onPressed: savingImageProject
                          ? null
                          : () => onFavoriteImage(attachment),
                      icon: const Icon(Icons.favorite_border_rounded, size: 18),
                      label: const Text('收藏'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            SelectableText(message.content),
            if (!user && message.reasoning.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                dense: true,
                leading: const Icon(Icons.psychology_alt_outlined, size: 20),
                title: const Text(
                  '查看模型返回的思考摘要',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(message.reasoning),
                  ),
                ],
              ),
            ],
            if (artifacts.isNotEmpty) ...[
              const SizedBox(height: 9),
              for (final artifact in artifacts)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: .5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.data_object_rounded),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          artifact.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        onPressed: () => onPreviewArtifact(artifact),
                        tooltip: '全屏预览',
                        icon: const Icon(Icons.fullscreen_rounded),
                      ),
                      IconButton(
                        onPressed: () => onSaveArtifact(artifact),
                        tooltip: '下载生成文件',
                        icon: const Icon(Icons.download_rounded),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: message.content),
                    );
                    if (!context.mounted) return;
                    AppNoticeCenter.instance.showSnackBar(
                      const SnackBar(content: Text('文本已复制')),
                    );
                  },
                  tooltip: user ? '复制我的问题' : '复制 AI 回答',
                  icon: const Icon(Icons.copy_rounded, size: 17),
                ),
                Text(
                  user ? '复制问题' : '复制回答',
                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                ),
                if (user) ...[
                  const SizedBox(width: 6),
                  TextButton.icon(
                    key: ValueKey('resendChatMessage_${message.id}'),
                    onPressed: onResend,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                    ),
                    icon: const Icon(Icons.replay_rounded, size: 17),
                    label: const Text('重新发送'),
                  ),
                ],
              ],
            ),
            if (!user && message.model?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 7),
              Text(
                [
                  '实际模型：${message.model}',
                  if (message.elapsedMs > 0)
                    '用时 ${(message.elapsedMs / 1000).toStringAsFixed(1)} 秒',
                  if (message.totalTokens > 0)
                    'Token ${message.totalTokens}（输入 ${message.inputTokens} / 输出 ${message.outputTokens}）',
                ].join(' · '),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFFE53935),
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Text(
      '推荐',
      style: TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _ChatBalanceStrip extends StatelessWidget {
  const _ChatBalanceStrip();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: AiApiHealthService.instance,
    builder: (context, _) {
      final health = AiApiHealthService.instance;
      final balance = health.balance;
      return Material(
        color: const Color(0xFFF7FBF9),
        child: InkWell(
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const AiUsageScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 17,
                  color: AppColors.teal,
                ),
                const SizedBox(width: 7),
                const Text(
                  'API 余额',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    health.state == AiApiHealthState.checking
                        ? '检测中…'
                        : balance?.displayText ?? '暂不可用',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                const Text(
                  '查看详细统计',
                  style: TextStyle(fontSize: 11, color: AppColors.teal),
                ),
                const Icon(Icons.chevron_right_rounded, size: 17),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ChatStatsBar extends StatelessWidget {
  const _ChatStatsBar({
    required this.ip,
    required this.model,
    required this.requestCount,
    required this.totalTokens,
    required this.elapsedMs,
    required this.isCurrentElapsed,
  });

  final String ip;
  final String model;
  final int requestCount;
  final int totalTokens;
  final int elapsedMs;
  final bool isCurrentElapsed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      children: [
        _chip(Icons.router_outlined, '本机 IP', ip),
        _chip(Icons.smart_toy_outlined, '请求模型', model),
        _chip(Icons.repeat_rounded, '请求次数', '$requestCount'),
        _chip(Icons.data_usage_rounded, '累计 Token', '$totalTokens'),
        _chip(
          Icons.timer_outlined,
          isCurrentElapsed ? '本次思考' : '累计用时',
          '${(elapsedMs / 1000).toStringAsFixed(1)} 秒',
        ),
      ],
    ),
  );

  Widget _chip(IconData icon, String label, String value) => Container(
    margin: const EdgeInsets.only(right: 7),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F6F8),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      children: [
        Icon(icon, size: 15, color: AppColors.teal),
        const SizedBox(width: 5),
        Text('$label：$value', style: const TextStyle(fontSize: 10)),
      ],
    ),
  );
}

class _ImageAttachmentPreview extends StatelessWidget {
  const _ImageAttachmentPreview({
    required this.attachment,
    required this.onSave,
  });

  final AiChatAttachment attachment;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(attachment.name),
      actions: [
        IconButton(
          onPressed: onSave,
          tooltip: '下载保存',
          icon: const Icon(Icons.download_rounded),
        ),
      ],
    ),
    body: InteractiveViewer(
      minScale: 0.1,
      maxScale: 16,
      boundaryMargin: const EdgeInsets.all(80),
      child: Center(
        child: Image.file(
          File(attachment.path),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image_outlined,
            color: Colors.white,
            size: 64,
          ),
        ),
      ),
    ),
  );
}

class _VideoAttachmentPreview extends StatefulWidget {
  const _VideoAttachmentPreview({
    required this.attachment,
    required this.onSave,
  });

  final AiChatAttachment attachment;
  final Future<void> Function() onSave;

  @override
  State<_VideoAttachmentPreview> createState() =>
      _VideoAttachmentPreviewState();
}

class _VideoAttachmentPreviewState extends State<_VideoAttachmentPreview> {
  late final VideoPlayerController _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.attachment.path));
    _controller
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object error) {
          if (mounted) setState(() => _error = error);
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(widget.attachment.name),
      actions: [
        IconButton(
          onPressed: widget.onSave,
          tooltip: '下载保存',
          icon: const Icon(Icons.download_rounded),
        ),
      ],
    ),
    body: Center(
      child: _error != null
          ? Text('视频无法播放：$_error', style: const TextStyle(color: Colors.white))
          : !_controller.value.isInitialized
          ? const CircularProgressIndicator()
          : AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
    ),
    floatingActionButton: _controller.value.isInitialized
        ? FloatingActionButton(
            onPressed: () {
              setState(() {
                _controller.value.isPlaying
                    ? _controller.pause()
                    : _controller.play();
              });
            },
            child: Icon(
              _controller.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
          )
        : null,
  );
}

class _TextAttachmentPreview extends StatelessWidget {
  const _TextAttachmentPreview({
    required this.name,
    required this.content,
    required this.onSave,
  });

  final String name;
  final String content;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(name),
      actions: [
        IconButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: content)),
          tooltip: '复制全部',
          icon: const Icon(Icons.copy_all_rounded),
        ),
        IconButton(
          onPressed: onSave,
          tooltip: '下载保存',
          icon: const Icon(Icons.download_rounded),
        ),
      ],
    ),
    body: InteractiveViewer(
      minScale: .6,
      maxScale: 4,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width,
          child: SelectableText(
            content,
            style: const TextStyle(fontFamily: 'monospace', height: 1.5),
          ),
        ),
      ),
    ),
  );
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 52, color: AppColors.teal),
          SizedBox(height: 12),
          Text(
            '开始 AI 聊天',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 6),
          Text('可上传图片或文件，也可切换到画图模式', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    ),
  );
}
