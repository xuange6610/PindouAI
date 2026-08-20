import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/bead_palettes.dart';
import '../models/bead_palette.dart';
import '../models/bead_pattern.dart';
import '../services/pattern_processor.dart';
import '../services/ai_api_health_service.dart';
import '../services/ai_design_task_center.dart';
import '../services/app_settings.dart';
import '../services/app_notice_center.dart';
import '../theme/app_theme.dart';
import '../widgets/bead_pattern_view.dart';
import 'api_settings_screen.dart';
import 'ai_design_task_center_screen.dart';

class ColorRecognitionScreen extends StatefulWidget {
  const ColorRecognitionScreen({super.key});

  @override
  State<ColorRecognitionScreen> createState() => _ColorRecognitionScreenState();
}

class _ColorRecognitionScreenState extends State<ColorRecognitionScreen> {
  final _picker = ImagePicker();
  final _processor = PatternProcessor();
  var _paletteId = BeadPaletteId.mard291;
  var _size = 48;
  var _loading = false;
  BeadPattern? _pattern;
  Uint8List? _sourceBytes;
  var _showOriginal = false;
  int? _selectedX;
  int? _selectedY;
  var _aiMode = false;
  final _taskCenter = AiDesignTaskCenter.instance;

  @override
  void initState() {
    super.initState();
    _taskCenter.addListener(_onTaskCenterChanged);
  }

  @override
  void dispose() {
    _taskCenter.removeListener(_onTaskCenterChanged);
    super.dispose();
  }

  void _onTaskCenterChanged() {
    if (mounted) setState(() {});
  }

  Future<({bool background, bool autoRetry})?>
  _showAiGenerationWarning() async {
    var autoRetry = false;
    return showDialog<({bool background, bool autoRetry})>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.auto_awesome_rounded),
          title: const Text('温馨提示'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '为保证您的图片质量，生图时间可能较长，预计需要5-10分钟~\n'
                '您可将任务放置后台进行等待！期间请勿退出本程序哦~\n'
                '如AI生图失败请尝试多生成几次呢~如果还是不行请检查API设置哟。',
                style: TextStyle(height: 1.55),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: autoRetry,
                onChanged: (value) =>
                    setDialogState(() => autoRetry = value ?? false),
                title: const Text('失败后持续自动重试，直到生成成功'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, (
                background: true,
                autoRetry: autoRetry,
              )),
              child: const Text('放到任务中心'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                background: false,
                autoRetry: autoRetry,
              )),
              child: const Text('当前页等待'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List?> _runAiRecognition(Uint8List source) async {
    final choice = await _showAiGenerationWarning();
    if (choice == null) return null;
    final id = _taskCenter.enqueue(
      styleId: 'color_recognition',
      styleTitle: 'AI 色号识别',
      displayPrompt: '识别主体、拼豆色号、坐标和用量',
      apiPrompt:
          '请严格保留参考图主体、构图和色彩，用清晰像素/拼豆风格重绘，去除模糊和压缩噪点。'
          '输出适合逐格色号识别的正视图，边缘清楚、每个色块边界明确，不改变主体。',
      sourceImage: source,
      model: AppSettings.instance.aiImageModel,
      autoRetry: choice.autoRetry,
      backgrounded: choice.background,
      scope: AiDesignTaskScope.colorRecognition,
    );
    if (choice.background) {
      AppNoticeCenter.instance.show(
        'AI 色号识别任务已放入右上角任务中心，可继续使用其他功能。',
        kind: AppNoticeKind.success,
      );
      return null;
    }
    final completer = Completer<Uint8List?>();
    void changed() {
      final task = _taskCenter.taskById(id);
      if (task == null || completer.isCompleted) return;
      if (task.status == AiDesignTaskStatus.succeeded) {
        completer.complete(task.result?.bytes);
      } else if (task.status == AiDesignTaskStatus.failed) {
        completer.completeError(StateError(task.error ?? 'AI 色号识别失败'));
      } else if (task.status == AiDesignTaskStatus.cancelled) {
        completer.complete(null);
      }
    }

    _taskCenter.addListener(changed);
    changed();
    try {
      return await completer.future;
    } finally {
      _taskCenter.removeListener(changed);
    }
  }

  Future<void> _pickAndRecognize() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (file == null || !mounted) return;
    setState(() {
      _loading = true;
      _pattern = null;
      _sourceBytes = null;
      _showOriginal = false;
      _selectedX = null;
      _selectedY = null;
    });
    try {
      var bytes = Uint8List.fromList(await file.readAsBytes());
      if (_aiMode) {
        final generated = await _runAiRecognition(bytes);
        if (generated == null) return;
        bytes = generated;
      }
      if (mounted) setState(() => _sourceBytes = bytes);
      final pattern = await _processor.process(
        bytes,
        ProcessingOptions(
          size: _size,
          height: _size,
          maxColors: BeadPalettes.byId(_paletteId).colors.length,
          portraitMode: false,
          smoothing: false,
          paletteId: _paletteId,
        ),
      );
      if (mounted) setState(() => _pattern = pattern);
    } on Object catch (error) {
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('识别失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_loading,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _loading) {
        AppNoticeCenter.instance.showSnackBar(
          const SnackBar(content: Text('正在识别，请稍候完成后再退出')),
        );
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text(
          '图片色号识别',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => AiDesignTaskCenterScreen(
                  center: _taskCenter,
                  scope: AiDesignTaskScope.colorRecognition,
                ),
              ),
            ),
            tooltip: 'AI 任务中心',
            icon: Badge(
              isLabelVisible:
                  _taskCenter.activeBackgroundCountFor(
                    AiDesignTaskScope.colorRecognition,
                  ) >
                  0,
              label: Text(
                '${_taskCenter.activeBackgroundCountFor(AiDesignTaskScope.colorRecognition)}',
              ),
              child: const Icon(Icons.task_outlined),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          AiApiStatusBanner(
            onOpenSettings: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ApiSettingsScreen()),
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.grid_on_rounded),
                label: Text('本地精准识别'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.auto_awesome_rounded),
                label: Text('AI 智能识别'),
              ),
            ],
            selected: {_aiMode},
            onSelectionChanged: _loading
                ? null
                : (value) => setState(() => _aiMode = value.first),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<BeadPaletteId>(
            initialValue: _paletteId,
            decoration: const InputDecoration(
              labelText: '识别色库',
              prefixIcon: Icon(Icons.palette_outlined),
            ),
            items: [
              for (final palette in BeadPalettes.all)
                DropdownMenuItem(
                  value: palette.id,
                  child: Text(palette.displayName),
                ),
            ],
            onChanged: (value) =>
                setState(() => _paletteId = value ?? _paletteId),
          ),
          Row(
            children: [
              const Text('定位精度'),
              Expanded(
                child: Slider(
                  value: _size.toDouble(),
                  min: 12,
                  max: 120,
                  divisions: 18,
                  label: '$_size × $_size',
                  onChanged: (value) => setState(() => _size = value.round()),
                ),
              ),
              Text('$_size'),
            ],
          ),
          FilledButton.icon(
            onPressed: _loading ? null : _pickAndRecognize,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_rounded),
            label: Text(_loading ? '正在识别每个位置' : '上传图片并识别色号'),
          ),
          if (_pattern != null) ...[
            const SizedBox(height: 18),
            Container(
              height: (MediaQuery.sizeOf(context).height * 0.52).clamp(
                320.0,
                560.0,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF3ECE6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('色号坐标图'),
                          selected: !_showOriginal,
                          onSelected: (_) =>
                              setState(() => _showOriginal = false),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('原图预览'),
                          selected: _showOriginal,
                          onSelected: (_) =>
                              setState(() => _showOriginal = true),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '全屏预览',
                          onPressed: () => _openFullscreen(context),
                          icon: const Icon(Icons.fullscreen_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _showOriginal && _sourceBytes != null
                        ? InteractiveViewer(
                            minScale: 0.2,
                            maxScale: 12,
                            child: Center(
                              child: Image.memory(
                                _sourceBytes!,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          )
                        : _CoordinatePatternViewer(
                            pattern: _pattern!,
                            selectedX: _selectedX,
                            selectedY: _selectedY,
                            onSelected: (x, y) => setState(() {
                              _selectedX = x;
                              _selectedY = y;
                            }),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_selectedX != null && _selectedY != null)
              _SelectedColorPanel(
                pattern: _pattern!,
                x: _selectedX!,
                y: _selectedY!,
              )
            else
              const Text(
                '点击任意豆位，查看该坐标对应的色号',
                style: TextStyle(color: AppColors.muted),
              ),
            const SizedBox(height: 14),
            Text('颜色用量', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final entry in _pattern!.sortedCounts)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: _pattern!.colors[entry.key].color,
                ),
                title: Text(_pattern!.colors[entry.key].code),
                trailing: Text('${entry.value} 颗'),
                subtitle: Text(_pattern!.colors[entry.key].nameEn),
              ),
          ],
        ],
      ),
    ),
  );

  Future<void> _openFullscreen(BuildContext context) async {
    final pattern = _pattern;
    if (pattern == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('图片色号全屏预览')),
          body: _CoordinatePatternViewer(
            pattern: pattern,
            selectedX: _selectedX,
            selectedY: _selectedY,
            onSelected: (x, y) => setState(() {
              _selectedX = x;
              _selectedY = y;
            }),
          ),
        ),
      ),
    );
  }
}

class _CoordinatePatternViewer extends StatefulWidget {
  const _CoordinatePatternViewer({
    required this.pattern,
    required this.selectedX,
    required this.selectedY,
    required this.onSelected,
  });

  final BeadPattern pattern;
  final int? selectedX;
  final int? selectedY;
  final void Function(int x, int y) onSelected;

  @override
  State<_CoordinatePatternViewer> createState() =>
      _CoordinatePatternViewerState();
}

class _CoordinatePatternViewerState extends State<_CoordinatePatternViewer> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final next = _transform.value.clone()
      ..scaleByDouble(factor, factor, factor, 1);
    setState(() => _transform.value = next);
  }

  @override
  Widget build(BuildContext context) {
    const cell = 28.0;
    final canvasSize = Size(
      widget.pattern.width * cell,
      widget.pattern.height * cell,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        InteractiveViewer(
          transformationController: _transform,
          minScale: 0.08,
          maxScale: 12,
          boundaryMargin: const EdgeInsets.all(120),
          constrained: false,
          alignment: Alignment.topLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () =>
                setState(() => _transform.value = Matrix4.identity()),
            onTapDown: (details) {
              final x = (details.localPosition.dx / cell).floor();
              final y = (details.localPosition.dy / cell).floor();
              if (x >= 0 &&
                  x < widget.pattern.width &&
                  y >= 0 &&
                  y < widget.pattern.height) {
                widget.onSelected(x, y);
              }
            },
            child: SizedBox.fromSize(
              size: canvasSize,
              child: CustomPaint(
                painter: _CoordinatePatternPainter(
                  widget.pattern,
                  selectedX: widget.selectedX,
                  selectedY: widget.selectedY,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 10,
          bottom: 10,
          child: Column(
            children: [
              IconButton.filledTonal(
                onPressed: () => _zoom(1.35),
                tooltip: '放大',
                icon: const Icon(Icons.add_rounded),
              ),
              const SizedBox(height: 6),
              IconButton.filledTonal(
                onPressed: () => _zoom(0.74),
                tooltip: '缩小',
                icon: const Icon(Icons.remove_rounded),
              ),
              const SizedBox(height: 6),
              IconButton.filledTonal(
                onPressed: () =>
                    setState(() => _transform.value = Matrix4.identity()),
                tooltip: '复位缩放',
                icon: const Icon(Icons.center_focus_strong_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoordinatePatternPainter extends BeadPatternPainter {
  _CoordinatePatternPainter(
    super.pattern, {
    required this.selectedX,
    required this.selectedY,
  }) : super(showCodes: true);

  final int? selectedX;
  final int? selectedY;

  @override
  void paint(Canvas canvas, Size size) {
    super.paint(canvas, size);
    final x = selectedX;
    final y = selectedY;
    if (x == null || y == null) return;
    final cellWidth = size.width / pattern.width;
    final cellHeight = size.height / pattern.height;
    final rect = Rect.fromLTWH(
      x * cellWidth,
      y * cellHeight,
      cellWidth,
      cellHeight,
    );
    canvas.drawRect(
      rect.deflate(1.2),
      Paint()
        ..color = const Color(0xFFE53935)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _CoordinatePatternPainter oldDelegate) =>
      super.shouldRepaint(oldDelegate) ||
      oldDelegate.selectedX != selectedX ||
      oldDelegate.selectedY != selectedY;
}

class _SelectedColorPanel extends StatelessWidget {
  const _SelectedColorPanel({
    required this.pattern,
    required this.x,
    required this.y,
  });

  final BeadPattern pattern;
  final int x;
  final int y;

  @override
  Widget build(BuildContext context) {
    final colorIndex = pattern.cells[y * pattern.width + x];
    if (colorIndex < 0 || colorIndex >= pattern.colors.length) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.grid_off_rounded),
        title: Text('坐标 X${x + 1}, Y${y + 1}'),
        subtitle: const Text('透明位置 / 不放置拼豆'),
      );
    }
    final color = pattern.colors[colorIndex];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '坐标 X${x + 1}, Y${y + 1}  ·  ${color.code}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text('${color.nameCn} ${color.nameEn}'.trim()),
                Text(
                  'RGB(${color.red}, ${color.green}, ${color.blue})  ·  ${color.hex}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
