import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/bead_palettes.dart';
import '../models/bead_palette.dart';
import '../models/bead_pattern.dart';
import '../services/app_notice_center.dart';
import '../services/pattern_processor.dart';
import '../services/project_repository.dart';
import '../services/processing_center.dart';
import '../theme/app_theme.dart';
import 'manual_cutout_screen.dart';
import 'result_screen.dart';

class EditorImageInput {
  const EditorImageInput({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

class _EditorSettingsSnapshot {
  const _EditorSettingsSnapshot({
    required this.width,
    required this.height,
    required this.customSize,
    required this.maxColors,
    required this.portraitMode,
    required this.smoothing,
    required this.removeBackground,
    required this.template,
    required this.generateAlternatives,
    required this.variantCount,
    required this.paletteId,
  });

  final int width;
  final int height;
  final bool customSize;
  final int maxColors;
  final bool portraitMode;
  final bool smoothing;
  final bool removeBackground;
  final PatternTemplate template;
  final bool generateAlternatives;
  final int variantCount;
  final BeadPaletteId paletteId;
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.imageBytes,
    required this.sourceName,
    this.initialOptions,
    this.overwriteProjectId,
    this.batchImages = const [],
  });

  final Uint8List imageBytes;
  final String sourceName;
  final ProcessingOptions? initialOptions;
  final String? overwriteProjectId;
  final List<EditorImageInput> batchImages;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  var _width = 50;
  var _height = 50;
  var _customSize = false;
  var _maxColors = BeadPalettes.defaultPalette.colors.length;
  var _paletteId = BeadPaletteId.mard291;
  var _portraitMode = true;
  var _smoothing = false;
  var _removeBackground = false;
  var _template = PatternTemplate.none;
  var _overwriteExisting = false;
  var _submitting = false;
  var _generateAlternatives = false;
  var _variantCount = 3;
  late Uint8List _imageBytes;
  late List<EditorImageInput> _inputs;
  late List<_EditorSettingsSnapshot> _batchSettings;
  final _batchPageController = PageController();
  var _sameBatchParameters = true;
  var _activeBatchIndex = 0;

  @override
  void initState() {
    super.initState();
    _imageBytes = widget.imageBytes;
    final options = widget.initialOptions;
    if (options != null) {
      _width = options.width;
      _height = options.outputHeight;
      _customSize = _width != _height || !boardSizePresets.contains(_width);
      _maxColors = options.maxColors;
      _paletteId = options.paletteId;
      _maxColors = _maxColors.clamp(
        8,
        BeadPalettes.byId(_paletteId).colors.length,
      );
      _portraitMode = options.portraitMode;
      _smoothing = options.smoothing;
      _removeBackground = options.removeBackground;
      _template = options.template;
    }
    _inputs = [
      EditorImageInput(bytes: widget.imageBytes, name: widget.sourceName),
      ...widget.batchImages,
    ];
    _batchSettings = List<_EditorSettingsSnapshot>.generate(
      _inputs.length,
      (_) => _captureSettings(),
    );
  }

  @override
  void dispose() {
    _batchPageController.dispose();
    super.dispose();
  }

  _EditorSettingsSnapshot _captureSettings() => _EditorSettingsSnapshot(
    width: _width,
    height: _height,
    customSize: _customSize,
    maxColors: _maxColors,
    portraitMode: _portraitMode,
    smoothing: _smoothing,
    removeBackground: _removeBackground,
    template: _template,
    generateAlternatives: _generateAlternatives,
    variantCount: _variantCount,
    paletteId: _paletteId,
  );

  void _storeActiveBatchState() {
    _inputs[_activeBatchIndex] = EditorImageInput(
      bytes: _imageBytes,
      name: _inputs[_activeBatchIndex].name,
    );
    _batchSettings[_activeBatchIndex] = _captureSettings();
  }

  void _loadBatchState(int index) {
    final settings = _batchSettings[index];
    _activeBatchIndex = index;
    _imageBytes = _inputs[index].bytes;
    _width = settings.width;
    _height = settings.height;
    _customSize = settings.customSize;
    _maxColors = settings.maxColors;
    _portraitMode = settings.portraitMode;
    _smoothing = settings.smoothing;
    _removeBackground = settings.removeBackground;
    _template = settings.template;
    _generateAlternatives = settings.generateAlternatives;
    _variantCount = settings.variantCount;
    _paletteId = settings.paletteId;
  }

  void _switchBatchPage(int index) {
    _storeActiveBatchState();
    setState(() => _loadBatchState(index));
  }

  void _setSameBatchParameters(bool value) {
    _storeActiveBatchState();
    final common = _captureSettings();
    setState(() {
      _sameBatchParameters = value;
      _batchSettings = List.generate(_inputs.length, (_) => common);
      _loadBatchState(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_batchPageController.hasClients) _batchPageController.jumpToPage(0);
    });
  }

  Future<void> _generate() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      _storeActiveBatchState();
      final inputs = _inputs;
      String? firstTaskId;
      final commonSettings = _captureSettings();
      for (var imageIndex = 0; imageIndex < inputs.length; imageIndex++) {
        final input = inputs[imageIndex];
        final settings = _sameBatchParameters
            ? commonSettings
            : _batchSettings[imageIndex];
        final variants = settings.generateAlternatives
            ? settings.variantCount
            : 1;
        for (var variant = 0; variant < variants; variant++) {
          final task = await ProcessingCenter.instance.enqueue(
            imageBytes: input.bytes,
            originalImageBytes: input.bytes,
            sourceName: input.name,
            replaceProjectId:
                inputs.length == 1 && variants == 1 && _overwriteExisting
                ? widget.overwriteProjectId
                : null,
            options: ProcessingOptions(
              size: settings.width,
              height: settings.height,
              maxColors: settings.maxColors,
              portraitMode: settings.portraitMode,
              smoothing: settings.smoothing,
              removeBackground: settings.removeBackground,
              template: settings.template,
              variantSeed: variant == 0
                  ? 0
                  : DateTime.now().microsecondsSinceEpoch +
                        imageIndex * 97 +
                        variant,
              paletteId: settings.paletteId,
            ),
          );
          firstTaskId ??= task.id;
        }
      }
      if (mounted) Navigator.pop(context, firstTaskId);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('无法加入处理队列：$error')),
      );
    }
  }

  Future<void> _openCropper() async {
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageCropScreen(
          imageBytes: _imageBytes,
          aspectRatio: _width / _height,
        ),
      ),
    );
    if (cropped != null && mounted) setState(() => _imageBytes = cropped);
  }

  Future<void> _openManualCutout() async {
    final result = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ManualCutoutScreen(
          imageBytes: _imageBytes,
          sourceName: _inputs[_activeBatchIndex].name,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _imageBytes = result;
        _removeBackground = false;
      });
    }
  }

  Future<void> _showCustomSizeDialog() async {
    final widthController = TextEditingController(text: '$_width');
    final heightController = TextEditingController(text: '$_height');
    String? errorText;
    final size = await showDialog<({int width, int height})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('自定义画板尺寸'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '宽和高均可设置为 10–300 格。非正方形画板会按对应比例裁切图片。',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: widthController,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '画板宽度（格）',
                    prefixIcon: Icon(Icons.swap_horiz_rounded),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Center(
                    child: Text(
                      '×',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                TextField(
                  controller: heightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '画板高度（格）',
                    prefixIcon: Icon(Icons.swap_vert_rounded),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorText!,
                    style: const TextStyle(
                      color: AppColors.coralDark,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final width = int.tryParse(widthController.text.trim());
                final height = int.tryParse(heightController.text.trim());
                if (width == null ||
                    height == null ||
                    width < 10 ||
                    width > 300 ||
                    height < 10 ||
                    height > 300) {
                  setDialogState(() => errorText = '请输入 10–300 之间的整数');
                  return;
                }
                Navigator.pop(context, (width: width, height: height));
              },
              child: const Text('应用尺寸'),
            ),
          ],
        ),
      ),
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        widthController.dispose();
        heightController.dispose();
      }),
    );
    if (size == null || !mounted) return;
    setState(() {
      _width = size.width;
      _height = size.height;
      _customSize = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '调整作品',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                BeadPalettes.byId(_paletteId).specification,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.teal,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                children: [
                  if (_inputs.length > 1) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              '批量图片参数方式',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 9),
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: true,
                                  icon: Icon(Icons.copy_all_rounded),
                                  label: Text('全部同一参数'),
                                ),
                                ButtonSegment(
                                  value: false,
                                  icon: Icon(Icons.tune_rounded),
                                  label: Text('逐张设置'),
                                ),
                              ],
                              selected: {_sameBatchParameters},
                              onSelectionChanged: (values) =>
                                  _setSameBatchParameters(values.first),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              _sameBatchParameters
                                  ? '${_inputs.length} 张图片共用当前界面的全部参数。'
                                  : '左右滑动图片，为每一张分别设置尺寸、颜色、抠图和模板。',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                            if (!_sameBatchParameters) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 118,
                                child: PageView.builder(
                                  controller: _batchPageController,
                                  itemCount: _inputs.length,
                                  onPageChanged: _switchBatchPage,
                                  itemBuilder: (context, index) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          ColoredBox(
                                            color: const Color(0xFFF2EEEA),
                                            child: Image.memory(
                                              _inputs[index].bytes,
                                              fit: BoxFit.contain,
                                              filterQuality: FilterQuality.high,
                                            ),
                                          ),
                                          Positioned(
                                            left: 7,
                                            right: 7,
                                            bottom: 6,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                child: Text(
                                                  '${index + 1}/${_inputs.length} · ${_inputs[index].name}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: AspectRatio(
                      aspectRatio: (_width / _height).clamp(0.72, 1.45),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            _imageBytes,
                            fit: BoxFit.contain,
                            cacheWidth: 1600,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 48,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _inputs.length > 1 && !_sameBatchParameters
                                    ? '${_activeBatchIndex + 1}/${_inputs.length} · $_width:$_height 参数预览'
                                    : '$_width:$_height 画板比例预览',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const Positioned(
                            right: 12,
                            bottom: 12,
                            child: CircleAvatar(
                              radius: 17,
                              backgroundColor: Colors.black54,
                              child: Icon(
                                Icons.open_with_rounded,
                                color: Colors.white,
                                size: 19,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: _openCropper,
                    icon: const Icon(Icons.crop_free_rounded),
                    label: const Text('移动 / 缩放 / 截取生成区域'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _openManualCutout,
                    icon: const Icon(Icons.content_cut_rounded),
                    label: const Text('手动抠图并保存透明图片'),
                  ),
                  const SizedBox(height: 22),
                  _ControlHeader(
                    title: '画板尺寸',
                    helper: '约 ${_width * _height} 颗豆',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: [
                      for (final value in boardSizePresets)
                        ChoiceChip(
                          label: Text('$value × $value'),
                          selected:
                              !_customSize &&
                              _width == value &&
                              _height == value,
                          labelStyle: TextStyle(
                            color:
                                !_customSize &&
                                    _width == value &&
                                    _height == value
                                ? AppColors.coralDark
                                : AppColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                          checkmarkColor: AppColors.coralDark,
                          onSelected: (_) => setState(() {
                            _width = value;
                            _height = value;
                            _customSize = false;
                          }),
                        ),
                      ChoiceChip(
                        avatar: const Icon(Icons.tune_rounded, size: 18),
                        label: Text(
                          _customSize ? '$_width × $_height' : '自定义尺寸',
                        ),
                        selected: _customSize,
                        labelStyle: TextStyle(
                          color: _customSize
                              ? AppColors.coralDark
                              : AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                        checkmarkColor: AppColors.coralDark,
                        onSelected: (_) => _showCustomSizeDialog(),
                      ),
                    ],
                  ),
                  if (_width >= 100 || _height >= 100) ...[
                    const SizedBox(height: 9),
                    const Text(
                      '大画板会产生更多图纸分页，处理与导出时间也更长。',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _ControlHeader(
                    title: '色号方案',
                    helper: _paletteId == BeadPaletteId.mard291
                        ? '当前默认'
                        : '已选择',
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<BeadPaletteId>(
                    key: ValueKey(_paletteId),
                    initialValue: _paletteId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.palette_outlined),
                      labelText: '生成时使用的品牌色卡',
                    ),
                    items: [
                      for (final palette in BeadPalettes.all)
                        DropdownMenuItem(
                          value: palette.id,
                          child: Text(
                            palette.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _paletteId = value;
                        _maxColors = _maxColors.clamp(
                          8,
                          BeadPalettes.byId(value).colors.length,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 7),
                  Text(
                    BeadPalettes.byId(_paletteId).description,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _ControlHeader(title: '颜色数量', helper: '最多 $_maxColors 色'),
                  Slider(
                    value: _maxColors.toDouble(),
                    min: 8,
                    max: BeadPalettes.byId(_paletteId).colors.length.toDouble(),
                    divisions: BeadPalettes.byId(_paletteId).colors.length - 8,
                    label: '$_maxColors 色',
                    onChanged: (value) =>
                        setState(() => _maxColors = value.round()),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        '更简洁',
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                      Text(
                        '更细腻',
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _removeBackground,
                          onChanged: (value) =>
                              setState(() => _removeBackground = value),
                          secondary: const _SettingIcon(
                            icon: Icons.auto_fix_normal_rounded,
                            color: AppColors.teal,
                          ),
                          title: const Text(
                            'AI 智能抠图',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: const Text('本机识别主体，背景区域不生成拼豆'),
                        ),
                        const Divider(height: 1, indent: 72),
                        SwitchListTile(
                          value: _portraitMode,
                          onChanged: (value) =>
                              setState(() => _portraitMode = value),
                          secondary: const _SettingIcon(
                            icon: Icons.face_retouching_natural,
                            color: AppColors.coral,
                          ),
                          title: const Text(
                            '人像肤色保护',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: const Text('轻度保护肤色层次，不再强制限制单一色系'),
                        ),
                        const Divider(height: 1, indent: 72),
                        SwitchListTile(
                          value: _smoothing,
                          onChanged: (value) =>
                              setState(() => _smoothing = value),
                          secondary: const _SettingIcon(
                            icon: Icons.auto_fix_high_rounded,
                            color: AppColors.teal,
                          ),
                          title: const Text(
                            '智能去除孤点',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: const Text('平滑噪点，同时保留主要轮廓'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    color: _generateAlternatives
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _generateAlternatives,
                          onChanged: (value) =>
                              setState(() => _generateAlternatives = value),
                          secondary: const _SettingIcon(
                            icon: Icons.auto_awesome_motion_rounded,
                            color: AppColors.teal,
                          ),
                          title: const Text(
                            '尝试生成不同方案',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            _generateAlternatives
                                ? '每张图片生成 $_variantCount 个独立配色方案'
                                : '关闭时每张图片只生成一个方案',
                          ),
                        ),
                        if (_generateAlternatives)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                            child: Row(
                              children: [
                                const Text('方案数量'),
                                Expanded(
                                  child: Slider(
                                    min: 2,
                                    max: 6,
                                    divisions: 4,
                                    label: '$_variantCount 个',
                                    value: _variantCount.toDouble(),
                                    onChanged: (value) => setState(
                                      () => _variantCount = value.round(),
                                    ),
                                  ),
                                ),
                                Text(
                                  '$_variantCount',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _ControlHeader(
                    title: '图纸模板（可不选）',
                    helper: _template == PatternTemplate.none
                        ? '当前：无模板'
                        : '当前：${_template.label}',
                  ),
                  const SizedBox(height: 10),
                  if (_template != PatternTemplate.none) ...[
                    _TemplatePreview(template: _template),
                    const SizedBox(height: 10),
                  ],
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: [
                      for (final template in PatternTemplate.values.skip(1))
                        _TemplateChoiceCard(
                          template: template,
                          selected: _template == template,
                          onTap: () => setState(
                            () => _template = _template == template
                                ? PatternTemplate.none
                                : template,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _template.description,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  if (widget.overwriteProjectId != null) ...[
                    const SizedBox(height: 18),
                    Card(
                      color: _overwriteExisting
                          ? const Color(0xFFFFEEE9)
                          : null,
                      child: SwitchListTile(
                        value: _overwriteExisting,
                        onChanged: (value) =>
                            setState(() => _overwriteExisting = value),
                        secondary: const _SettingIcon(
                          icon: Icons.layers_clear_outlined,
                          color: AppColors.coral,
                        ),
                        title: const Text(
                          '覆盖之前生成的作品',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: const Text('默认关闭；开启后新结果会替换原作品，不会新增一份'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: AppColors.muted,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '图片仅在本机处理，不会上传到服务器。',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              decoration: const BoxDecoration(
                color: AppColors.canvas,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '当前画板',
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                      Text(
                        _inputs.length > 1 && !_sameBatchParameters
                            ? '第 ${_activeBatchIndex + 1} 张 · $_width×$_height 格'
                            : '$_width×$_height 格',
                        style: const TextStyle(
                          color: AppColors.teal,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _generate,
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome_rounded),
                      label: Text(
                        _submitting
                            ? '正在加入处理中心…'
                            : widget.batchImages.isEmpty
                            ? '生成拼豆图纸'
                            : '批量生成 ${widget.batchImages.length + 1} 张图片',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const boardSizePresets = <int>[
  15,
  20,
  29,
  30,
  40,
  50,
  58,
  87,
  100,
  104,
  116,
  200,
];

class ImageCropScreen extends StatefulWidget {
  const ImageCropScreen({
    super.key,
    required this.imageBytes,
    required this.aspectRatio,
  });

  final Uint8List imageBytes;
  final double aspectRatio;

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  ui.Image? _image;
  Object? _error;
  var _zoom = 1.0;
  var _startZoom = 1.0;
  var _offset = Offset.zero;
  var _startOffset = Offset.zero;
  var _startFocalPoint = Offset.zero;
  var _viewportSize = Size.zero;
  var _baseScale = 1.0;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(widget.imageBytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      const maxDecodeDimension = 2400;
      final longestSide = math.max(descriptor.width, descriptor.height);
      final decodeScale = longestSide > maxDecodeDimension
          ? maxDecodeDimension / longestSide
          : 1.0;
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * decodeScale).round()),
        targetHeight: math.max(1, (descriptor.height * decodeScale).round()),
      );
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _zoom = 1;
      _offset = Offset.zero;
    });
  }

  void _setZoom(double value) {
    final nextZoom = value.clamp(1.0, 8.0);
    if (nextZoom == _zoom) return;
    setState(() {
      final ratio = nextZoom / _zoom;
      _zoom = nextZoom;
      _offset = _clampOffset(_offset * ratio, nextZoom);
    });
  }

  Offset _clampOffset(Offset value, double zoom) {
    final image = _image;
    if (image == null || _viewportSize.isEmpty) return Offset.zero;
    final renderedWidth = image.width * _baseScale * zoom;
    final renderedHeight = image.height * _baseScale * zoom;
    final maxX = math.max(0.0, (renderedWidth - _viewportSize.width) / 2);
    final maxY = math.max(0.0, (renderedHeight - _viewportSize.height) / 2);
    return Offset(value.dx.clamp(-maxX, maxX), value.dy.clamp(-maxY, maxY));
  }

  Future<void> _confirmCrop() async {
    final image = _image;
    if (image == null || _viewportSize.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final renderedWidth = image.width * _baseScale * _zoom;
      final renderedHeight = image.height * _baseScale * _zoom;
      final sourceWidth = (_viewportSize.width / renderedWidth * image.width)
          .clamp(1.0, image.width.toDouble());
      final sourceHeight =
          (_viewportSize.height / renderedHeight * image.height).clamp(
            1.0,
            image.height.toDouble(),
          );
      final sourceLeft =
          (((renderedWidth - _viewportSize.width) / 2 - _offset.dx) /
                  renderedWidth *
                  image.width)
              .clamp(0.0, image.width - sourceWidth);
      final sourceTop =
          (((renderedHeight - _viewportSize.height) / 2 - _offset.dy) /
                  renderedHeight *
                  image.height)
              .clamp(0.0, image.height - sourceHeight);
      final longestSide = math.max(sourceWidth, sourceHeight);
      final outputScale = longestSide > 2400 ? 2400 / longestSide : 1.0;
      final outputWidth = math.max(1, (sourceWidth * outputScale).round());
      final outputHeight = math.max(1, (sourceHeight * outputScale).round());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(sourceLeft, sourceTop, sourceWidth, sourceHeight),
        Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final output = await picture.toImage(outputWidth, outputHeight);
      picture.dispose();
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      output.dispose();
      if (data == null) throw StateError('无法生成裁剪图片');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (mounted) Navigator.pop(context, Uint8List.fromList(bytes));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('裁剪失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF171515),
      appBar: AppBar(
        backgroundColor: const Color(0xFF171515),
        foregroundColor: Colors.white,
        title: const Text(
          '裁剪与调整构图',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton.icon(
            onPressed: _image == null ? null : _reset,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重置'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _error != null
          ? Center(
              child: Text(
                '无法读取图片：$_error',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : _image == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = math.max(1.0, constraints.maxWidth - 36);
                final availableHeight = math.max(
                  1.0,
                  constraints.maxHeight - 138,
                );
                late final double viewportWidth;
                late final double viewportHeight;
                if (availableWidth / availableHeight > widget.aspectRatio) {
                  viewportHeight = availableHeight;
                  viewportWidth = viewportHeight * widget.aspectRatio;
                } else {
                  viewportWidth = availableWidth;
                  viewportHeight = viewportWidth / widget.aspectRatio;
                }
                _viewportSize = Size(viewportWidth, viewportHeight);
                final image = _image!;
                _baseScale = math.max(
                  viewportWidth / image.width,
                  viewportHeight / image.height,
                );
                _offset = _clampOffset(_offset, _zoom);
                return Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 12, 20, 14),
                      child: Text(
                        '双指缩放、拖动图片；亮色框内就是最终上传范围',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Container(
                          width: viewportWidth,
                          height: viewportHeight,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0xAAE85584),
                                blurRadius: 22,
                              ),
                            ],
                          ),
                          child: ClipRect(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: (details) {
                                _startZoom = _zoom;
                                _startOffset = _offset;
                                _startFocalPoint = details.localFocalPoint;
                              },
                              onScaleUpdate: (details) {
                                final zoom = (_startZoom * details.scale).clamp(
                                  1.0,
                                  8.0,
                                );
                                final zoomRatio = zoom / _startZoom;
                                final center = _viewportSize.center(
                                  Offset.zero,
                                );
                                final startFromCenter =
                                    _startFocalPoint - center;
                                final anchoredOffset =
                                    startFromCenter -
                                    (startFromCenter - _startOffset) *
                                        zoomRatio;
                                final offset =
                                    anchoredOffset +
                                    details.localFocalPoint -
                                    _startFocalPoint;
                                setState(() {
                                  _zoom = zoom;
                                  _offset = _clampOffset(offset, zoom);
                                });
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  const ColoredBox(color: Colors.black),
                                  OverflowBox(
                                    maxWidth: double.infinity,
                                    maxHeight: double.infinity,
                                    child: Center(
                                      child: Transform.translate(
                                        offset: _offset,
                                        child: Transform.scale(
                                          scale: _zoom,
                                          child: RawImage(
                                            image: image,
                                            width: image.width * _baseScale,
                                            height: image.height * _baseScale,
                                            fit: BoxFit.fill,
                                            filterQuality: FilterQuality.medium,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const IgnorePointer(
                                    child: CustomPaint(
                                      painter: _CropGridPainter(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: _zoom <= 1
                                ? null
                                : () => _setZoom(_zoom - 0.25),
                            color: Colors.white,
                            disabledColor: Colors.white24,
                            icon: const Icon(Icons.remove_circle_outline),
                            tooltip: '缩小',
                          ),
                          Expanded(
                            child: Slider(
                              value: _zoom,
                              min: 1,
                              max: 8,
                              onChanged: _setZoom,
                            ),
                          ),
                          IconButton(
                            onPressed: _zoom >= 8
                                ? null
                                : () => _setZoom(_zoom + 0.25),
                            color: Colors.white,
                            disabledColor: Colors.white24,
                            icon: const Icon(Icons.add_circle_outline),
                            tooltip: '放大',
                          ),
                          SizedBox(
                            width: 48,
                            child: Text(
                              '${_zoom.toStringAsFixed(1)}×',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          child: FilledButton.icon(
            onPressed: _image == null || _saving ? null : _confirmCrop,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.crop_rounded),
            label: Text(_saving ? '正在生成裁剪图片…' : '使用这个裁剪结果'),
          ),
        ),
      ),
    );
  }
}

class _CropGridPainter extends CustomPainter {
  const _CropGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.48)
      ..strokeWidth = 1;
    for (var index = 1; index <= 2; index++) {
      final x = size.width * index / 3;
      final y = size.height * index / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropGridPainter oldDelegate) => false;
}

class _TemplatePreview extends StatelessWidget {
  const _TemplatePreview({required this.template});

  final PatternTemplate template;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F0EC),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 126,
          height: 94,
          child: CustomPaint(painter: _TemplateMiniaturePainter(template)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '所选模板大致效果',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
              const SizedBox(height: 4),
              Text(
                template.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                template.description,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TemplateChoiceCard extends StatelessWidget {
  const _TemplateChoiceCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final PatternTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 108,
    child: Material(
      color: selected ? const Color(0xFFFFEEE8) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AppColors.coral : AppColors.line,
          width: selected ? 2.2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 76,
                width: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TemplateMiniaturePainter(template),
                      ),
                    ),
                    if (selected)
                      const Positioned(
                        top: 2,
                        right: 2,
                        child: CircleAvatar(
                          radius: 9,
                          backgroundColor: AppColors.coral,
                          child: Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                template.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: selected ? AppColors.coralDark : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TemplateMiniaturePainter extends CustomPainter {
  const _TemplateMiniaturePainter(this.template);

  final PatternTemplate template;

  @override
  void paint(Canvas canvas, Size size) {
    final paper = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(5)),
      paper,
    );
    final accent = switch (template) {
      PatternTemplate.classic => AppColors.coral,
      PatternTemplate.fresh => AppColors.teal,
      PatternTemplate.mard => const Color(0xFF687FA5),
      PatternTemplate.none => AppColors.muted,
    };
    final headerHeight = switch (template) {
      PatternTemplate.classic => 15.0,
      PatternTemplate.fresh => 12.0,
      PatternTemplate.mard => 10.0,
      PatternTemplate.none => 0.0,
    };
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, headerHeight),
      Paint()..color = accent.withValues(alpha: 0.18),
    );
    canvas.drawRect(
      Rect.fromLTWH(5, 4, headerHeight - 4, headerHeight - 6),
      Paint()..color = accent,
    );
    canvas.drawRect(
      Rect.fromLTWH(headerHeight + 5, 5, size.width * 0.48, 2.4),
      Paint()..color = AppColors.ink,
    );
    final grid = Rect.fromLTRB(
      9,
      headerHeight + 5,
      size.width - 5,
      size.height - 13,
    );
    if (template == PatternTemplate.mard) {
      canvas.drawRect(
        Rect.fromLTWH(4, grid.top, 5, grid.height),
        Paint()..color = const Color(0xFFE5ECF7),
      );
      canvas.drawRect(
        Rect.fromLTWH(grid.left, grid.top - 4, grid.width, 4),
        Paint()..color = const Color(0xFFE5ECF7),
      );
    }
    const columns = 8;
    const rows = 6;
    final cellWidth = grid.width / columns;
    final cellHeight = grid.height / rows;
    final sampleColors = [
      accent,
      const Color(0xFFFFD76A),
      const Color(0xFFEE927E),
      const Color(0xFF393536),
    ];
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        if ((x + y * 2) % 5 > 2) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            grid.left + x * cellWidth,
            grid.top + y * cellHeight,
            cellWidth,
            cellHeight,
          ),
          Paint()..color = sampleColors[(x + y) % sampleColors.length],
        );
      }
    }
    final linePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 0.55;
    for (var x = 0; x <= columns; x++) {
      canvas.drawLine(
        Offset(grid.left + x * cellWidth, grid.top),
        Offset(grid.left + x * cellWidth, grid.bottom),
        linePaint..strokeWidth = x % 4 == 0 ? 1.2 : 0.45,
      );
    }
    for (var y = 0; y <= rows; y++) {
      canvas.drawLine(
        Offset(grid.left, grid.top + y * cellHeight),
        Offset(grid.right, grid.top + y * cellHeight),
        linePaint..strokeWidth = y % 3 == 0 ? 1.2 : 0.45,
      );
    }
    for (var index = 0; index < 4; index++) {
      canvas.drawRect(
        Rect.fromLTWH(
          6 + index * ((size.width - 9) / 4),
          size.height - 9,
          (size.width - 16) / 4,
          5,
        ),
        Paint()..color = sampleColors[index],
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TemplateMiniaturePainter oldDelegate) =>
      oldDelegate.template != template;
}

class _ControlHeader extends StatelessWidget {
  const _ControlHeader({required this.title, required this.helper});
  final String title;
  final String helper;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const Spacer(),
      Text(
        helper,
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
    ],
  );
}

class _SettingIcon extends StatelessWidget {
  const _SettingIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, color: color),
  );
}

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({
    super.key,
    required this.imageBytes,
    required this.options,
  });

  final Uint8List imageBytes;
  final ProcessingOptions options;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with SingleTickerProviderStateMixin {
  static const _steps = ['分析图片结构', '聚类主要颜色', '匹配 Artkal 300 色号', '生成格子与清单'];
  late final AnimationController _animation;
  Timer? _timer;
  var _step = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
    _timer = Timer.periodic(const Duration(milliseconds: 780), (_) {
      if (mounted && _step < _steps.length - 1) setState(() => _step++);
    });
    _run();
  }

  Future<void> _run() async {
    try {
      final pattern = await PatternProcessor().process(
        widget.imageBytes,
        widget.options,
      );
      await ProjectRepository().save(pattern);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<bool, bool>(
        MaterialPageRoute(
          builder: (_) => ResultScreen(pattern: pattern, isNew: true),
        ),
        result: true,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _error != null,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: _error == null
                  ? _buildProgress(context)
                  : _buildError(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedBuilder(
        animation: _animation,
        builder: (context, _) => Transform.rotate(
          angle: _animation.value * 6.283,
          child: Container(
            width: 112,
            height: 112,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  AppColors.coral,
                  AppColors.peach,
                  AppColors.teal,
                  AppColors.coral,
                ],
              ),
            ),
            child: const Center(
              child: CircleAvatar(
                radius: 44,
                backgroundColor: AppColors.canvas,
                child: Icon(
                  Icons.blur_circular_rounded,
                  color: AppColors.coral,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 34),
      Text('AI 正在设计你的作品', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 10),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Text(
          _steps[_step],
          key: ValueKey(_step),
          style: const TextStyle(color: AppColors.muted),
        ),
      ),
      const SizedBox(height: 28),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: (_step + 0.35) / _steps.length,
          minHeight: 8,
          backgroundColor: AppColors.line,
        ),
      ),
      const SizedBox(height: 14),
      Text(
        '${widget.options.width}×${widget.options.outputHeight} · 最多 ${widget.options.maxColors} 色',
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
    ],
  );

  Widget _buildError(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.error_outline_rounded, color: AppColors.coral, size: 60),
      const SizedBox(height: 16),
      Text('生成失败', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(
        '$_error',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('返回调整'),
      ),
    ],
  );
}
