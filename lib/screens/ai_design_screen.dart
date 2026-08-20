import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/ai_design_history.dart';
import '../services/ai_api_health_service.dart';
import '../services/ai_design_styles.dart';
import '../services/ai_design_task_center.dart';
import '../services/app_notice_center.dart';
import '../services/app_settings.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';
import 'ai_design_history_screen.dart';
import 'ai_design_task_center_screen.dart';
import 'editor_screen.dart';
import 'api_settings_screen.dart';

class AiDesignScreen extends StatefulWidget {
  const AiDesignScreen({
    super.key,
    this.initialImage,
    this.replicationMode = false,
    this.initialRequest,
    this.taskCenter,
  });

  final Uint8List? initialImage;
  final bool replicationMode;
  final String? initialRequest;
  final AiDesignTaskCenter? taskCenter;

  static const defaultAdditionalRequest =
      '生成的图片以拼豆风格为主，要在图片中展示拼豆的色号以及拼豆所需要的豆子数量，'
      '以及用到的款式，并且每个小格子是5*5的范围，画板是50*50的大小';

  @override
  State<AiDesignScreen> createState() => _AiDesignScreenState();
}

class _AiDesignScreenState extends State<AiDesignScreen> {
  final _requestController = TextEditingController();
  final _picker = ImagePicker();
  final _history = const AiDesignHistoryStore();
  late final AiDesignTaskCenter _taskCenter;
  var _selectedStyleId = AiBeadDesignStyles.all.first.id;
  Uint8List? _sourceImage;
  Uint8List? _generatedImage;
  var _loading = false;
  var _historyCount = 0;
  String? _foregroundTaskId;
  String? _handledTaskId;
  var _leaveDialogOpen = false;

  AiBeadDesignStyle get _style => AiBeadDesignStyles.byId(_selectedStyleId);

  @override
  void initState() {
    super.initState();
    _taskCenter = widget.taskCenter ?? AiDesignTaskCenter.instance;
    _sourceImage = widget.initialImage;
    _requestController.text = widget.initialRequest?.trim().isNotEmpty == true
        ? widget.initialRequest!.trim()
        : AiDesignScreen.defaultAdditionalRequest;
    _taskCenter.addListener(_onTaskCenterChanged);
    _reloadHistoryCount();
  }

  @override
  void dispose() {
    _taskCenter.removeListener(_onTaskCenterChanged);
    _requestController.dispose();
    super.dispose();
  }

  AiDesignTask? get _foregroundTask => _taskCenter.taskById(_foregroundTaskId);

  bool get _hasForegroundGeneration =>
      _foregroundTask?.isActive == true &&
      _foregroundTask?.backgrounded == false;

  void _onTaskCenterChanged() {
    if (!mounted) return;
    final task = _foregroundTask;
    if (task == null) {
      setState(() => _loading = false);
      return;
    }
    if (task.backgrounded) {
      setState(() {
        _foregroundTaskId = null;
        _loading = false;
      });
      _taskCenter.remove(task.id);
      return;
    }
    if (task.status == AiDesignTaskStatus.succeeded &&
        _handledTaskId != task.id) {
      _handledTaskId = task.id;
      setState(() {
        _generatedImage = task.result?.bytes;
        _selectedStyleId = task.styleId;
        _foregroundTaskId = null;
        _loading = false;
      });
      _taskCenter.remove(task.id);
      _reloadHistoryCount();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('${task.styleTitle}生成成功，已自动保存到制图记录')),
        );
      });
      return;
    }
    if ((task.status == AiDesignTaskStatus.failed ||
            task.status == AiDesignTaskStatus.cancelled) &&
        _handledTaskId != task.id) {
      _handledTaskId = task.id;
      setState(() {
        _foregroundTaskId = null;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(
            content: Text(
              task.error == null ? 'AI 制图任务已取消' : 'AI 制图失败：${task.error}',
            ),
          ),
        );
      });
      return;
    }
    setState(() => _loading = task.isActive);
  }

  Future<void> _reloadHistoryCount() async {
    final entries = await _history.load();
    if (mounted) setState(() => _historyCount = entries.length);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _sourceImage = Uint8List.fromList(bytes);
        _generatedImage = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('无法读取图片：$error')),
      );
    }
  }

  Future<void> _chooseImageSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  '上传自己的图片',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text('原图只用于本次 AI 风格转换'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍照上传'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (source != null) await _pickImage(source);
  }

  Future<void> _generate() async {
    final source = _sourceImage;
    if (source == null) {
      AppNoticeCenter.instance.showSnackBar(
        const SnackBar(content: Text('请先上传自己的图片')),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final choice = await _showGenerationNotice();
    if (choice == null || !mounted) return;
    final style = _style;
    final additional = _requestController.text.trim();
    final prompt = widget.replicationMode
        ? '请对参考图进行高保真一比一像素复刻。严格保持原图的画布比例、构图、主体位置、'
              '轮廓、像素块、颜色关系和所有已有元素，不添加新元素，不改变主体身份。'
              '在保持原图一致的前提下应用“${style.title}”的清晰像素表现。'
              '用户指定修改：$additional'
        : style.buildPrompt(additional);
    final id = _taskCenter.enqueue(
      styleId: style.id,
      styleTitle: style.title,
      displayPrompt: additional.isEmpty ? '${style.title}照片转换' : additional,
      apiPrompt: prompt,
      sourceImage: source,
      model: AppSettings.instance.aiImageModel,
      autoRetry: choice.autoRetry,
      backgrounded: choice.background,
    );
    if (choice.background) {
      AppNoticeCenter.instance.showSnackBar(
        const SnackBar(content: Text('任务已放到右上角任务中心，可继续使用其他功能')),
      );
    } else {
      setState(() {
        _foregroundTaskId = id;
        _handledTaskId = null;
        _loading = true;
      });
    }
  }

  Future<_GenerationChoice?> _showGenerationNotice() async {
    var autoRetry = false;
    return showDialog<_GenerationChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.tips_and_updates_outlined),
          title: const Text('温馨提示'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '为保证您的图片质量，生图时间可能较长，预计需要5-10分钟~\n'
                '您可将任务放置后台进行等待！期间请勿退出本程序哦~\n'
                '如AI生图失败请尝试多生成几次呢~如果还是不行请检查API设置哟。',
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: autoRetry,
                title: const Text('如果生成失败，自动重新生成直到成功'),
                onChanged: (value) =>
                    setDialogState(() => autoRetry = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(
                context,
                _GenerationChoice(background: true, autoRetry: autoRetry),
              ),
              icon: const Icon(Icons.move_to_inbox_outlined),
              label: const Text('放到任务中心'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _GenerationChoice(background: false, autoRetry: autoRetry),
              ),
              child: const Text('当前页等待'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openHistory() async {
    final entry = await Navigator.of(context).push<AiDesignHistoryEntry>(
      MaterialPageRoute(builder: (_) => const AiDesignHistoryScreen()),
    );
    await _reloadHistoryCount();
    if (entry?.imagePath == null || !mounted) return;
    final file = File(entry!.imagePath!);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _generatedImage = bytes;
      if (entry.styleId != null) _selectedStyleId = entry.styleId!;
    });
  }

  Future<void> _openTaskCenter() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AiDesignTaskCenterScreen(center: _taskCenter),
      ),
    );
    await _reloadHistoryCount();
  }

  Future<void> _cropSourceImage() async {
    final bytes = _sourceImage;
    if (bytes == null || _loading) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => ImageCropScreen(imageBytes: bytes, aspectRatio: 1),
      ),
    );
    if (cropped == null || !mounted) return;
    setState(() {
      _sourceImage = cropped;
      _generatedImage = null;
    });
  }

  void _moveForegroundToCenter() {
    final id = _foregroundTaskId;
    if (id == null) return;
    _taskCenter.moveToCenter(id);
    AppNoticeCenter.instance.showSnackBar(
      const SnackBar(content: Text('任务已移到任务中心，现在可以切换风格或离开本页')),
    );
  }

  Future<void> _protectLeaving() async {
    if (!_hasForegroundGeneration || _leaveDialogOpen) return;
    _leaveDialogOpen = true;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('图片仍在生成'),
        content: const Text('当前任务还没有放到任务中心。直接退出会取消本次任务，以免误操作，建议先放到任务中心继续后台生成。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'stay'),
            child: const Text('继续等待'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('取消任务并退出'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'background'),
            child: const Text('放到任务中心并退出'),
          ),
        ],
      ),
    );
    _leaveDialogOpen = false;
    if (!mounted || action == null || action == 'stay') return;
    final id = _foregroundTaskId;
    if (id != null) {
      if (action == 'background') {
        _taskCenter.moveToCenter(id);
      } else {
        _taskCenter.cancel(id);
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _saveGenerated() async {
    final bytes = _generatedImage;
    if (bytes == null) return;
    try {
      await ExportService().saveImageBytes(
        bytes,
        'AI拼豆图_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          const SnackBar(content: Text('图片已保存到“图片/拼豆AI”')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('保存图片失败：$error')),
        );
      }
    }
  }

  Future<void> _convertToBead() async {
    final bytes = _generatedImage;
    if (bytes == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          imageBytes: bytes,
          sourceName: 'AI_${_style.title}.png',
        ),
      ),
    );
  }

  void _openPreview() {
    final bytes = _generatedImage;
    if (bytes == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text('${_style.title}预览'),
          ),
          body: InteractiveViewer(
            minScale: 0.25,
            maxScale: 12,
            child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_hasForegroundGeneration,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _protectLeaving();
    },
    child: Scaffold(
      backgroundColor: const Color(0xFFF7F5F1),
      appBar: AppBar(
        title: Text(
          widget.replicationMode ? 'AI 一比一复刻与修改' : 'AI 拼豆图纸',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            key: const ValueKey('aiDesignTaskCenterButton'),
            onPressed: _openTaskCenter,
            tooltip: '生图任务中心',
            icon: Badge(
              isLabelVisible: _taskCenter.activeBackgroundCount > 0,
              label: Text('${_taskCenter.activeBackgroundCount}'),
              child: const Icon(Icons.task_outlined),
            ),
          ),
          TextButton.icon(
            key: const ValueKey('aiDesignHistoryButton'),
            onPressed: _openHistory,
            icon: const Icon(Icons.history_rounded),
            label: Text('记录 $_historyCount'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          AiApiStatusBanner(
            onOpenSettings: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ApiSettingsScreen()),
            ),
          ),
          const SizedBox(height: 10),
          if (widget.replicationMode) ...[
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5F3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.content_copy_rounded, color: AppColors.teal),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '高保真复刻模式已开启：AI 会尽量保持原构图和像素细节；可在补充要求中说明要修改的部分。',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF161616),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PINDOU PRO',
                        style: TextStyle(
                          color: Color(0xFFFFD998),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'AI 拼豆图纸',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 29,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '选择画风，再拍照或从相册上传',
                        style: TextStyle(color: Color(0xFFBEBEBE)),
                      ),
                      SizedBox(height: 15),
                      Wrap(
                        spacing: 7,
                        children: [
                          _DarkBadge(text: '4 种风格'),
                          _DarkBadge(text: '自动保存记录'),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFF292929),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.grid_4x4_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5DED3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '选择风格',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${AiBeadDesignStyles.all.length} 个模式',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  '不同风格会使用独立提示词和生成参数',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.77,
                  ),
                  itemCount: AiBeadDesignStyles.all.length,
                  itemBuilder: (context, index) {
                    final style = AiBeadDesignStyles.all[index];
                    return _StyleCard(
                      style: style,
                      selected: style.id == _selectedStyleId,
                      onTap: _hasForegroundGeneration
                          ? null
                          : () => setState(() => _selectedStyleId = style.id),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '上传自己的图片',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '当前选择：${_style.title} · ${_style.description}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                InkWell(
                  key: const ValueKey('aiDesignUploadImage'),
                  onTap: _loading ? null : _chooseImageSource,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 210,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3EF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _sourceImage == null
                            ? const Color(0xFFD5D0C8)
                            : AppColors.teal,
                        width: _sourceImage == null ? 1 : 2,
                      ),
                    ),
                    child: _sourceImage == null
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 46,
                              ),
                              SizedBox(height: 8),
                              Text(
                                '点击拍照或从相册上传',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '支持人物、情侣、宠物及全身照',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              _sourceImage!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                            ),
                          ),
                  ),
                ),
                if (_sourceImage != null) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      TextButton.icon(
                        onPressed: _loading ? null : _chooseImageSource,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('更换图片'),
                      ),
                      TextButton.icon(
                        key: const ValueKey('aiDesignCropImage'),
                        onPressed: _loading ? null : _cropSourceImage,
                        icon: const Icon(Icons.crop_rounded),
                        label: const Text('裁剪/缩放'),
                      ),
                      TextButton.icon(
                        onPressed: _loading
                            ? null
                            : () => setState(() {
                                _sourceImage = null;
                                _generatedImage = null;
                              }),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('移除'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: _requestController,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: '补充要求（可选）',
                    hintText: '例如：保留两个人，背景简化为浅色，突出婚礼服装',
                    prefixIcon: Icon(Icons.tune_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey('aiDesignGenerateButton'),
                  onPressed: _loading ? null : _generate,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF171717),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                  ),
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(_loading ? '正在生成 ${_style.title}' : '立即制作'),
                ),
                if (_hasForegroundGeneration) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('aiDesignMoveToTaskCenter'),
                    onPressed: _moveForegroundToCenter,
                    icon: const Icon(Icons.move_to_inbox_outlined),
                    label: const Text('放到任务中心并继续后台生成'),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _foregroundTask?.status == AiDesignTaskStatus.waitingToRetry
                        ? '本次生成失败，已按设置等待自动重试。移到任务中心后可继续操作本页。'
                        : '当前任务未放到任务中心，生成期间风格已锁定，离开页面前会再次确认。',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_generatedImage != null) ...[
            const SizedBox(height: 18),
            _GeneratedResult(
              bytes: _generatedImage!,
              styleTitle: _style.title,
              onPreview: _openPreview,
              onSave: _saveGenerated,
              onConvert: _convertToBead,
            ),
          ],
        ],
      ),
    ),
  );
}

class _GenerationChoice {
  const _GenerationChoice({required this.background, required this.autoRetry});

  final bool background;
  final bool autoRetry;
}

class _DarkBadge extends StatelessWidget {
  const _DarkBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFF303030),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final AiBeadDesignStyle style;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: ValueKey('aiDesignStyle_${style.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F6F3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF171717) : Colors.transparent,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(10),
                    ),
                    child: Image.asset(style.exampleAsset, fit: BoxFit.cover),
                  ),
                  if (selected)
                    const Positioned(
                      right: 7,
                      top: 7,
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: Color(0xFF171717),
                        child: Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      style.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF202020),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      style.tag,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GeneratedResult extends StatelessWidget {
  const _GeneratedResult({
    required this.bytes,
    required this.styleTitle,
    required this.onPreview,
    required this.onSave,
    required this.onConvert,
  });

  final Uint8List bytes;
  final String styleTitle;
  final VoidCallback onPreview;
  final Future<void> Function() onSave;
  final Future<void> Function() onConvert;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$styleTitle · 生成结果',
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onDoubleTap: onPreview,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 320,
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: onPreview,
              tooltip: '全屏预览',
              icon: const Icon(Icons.fullscreen_rounded),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onSave(),
                icon: const Icon(Icons.download_rounded),
                label: const Text('保存图片'),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => onConvert(),
                icon: const Icon(Icons.grid_on_rounded),
                label: const Text('转拼豆图'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
