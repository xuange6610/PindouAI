import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/export_service.dart';
import '../services/ai_api_health_service.dart';
import '../services/ai_background_image_workflow.dart';
import '../services/app_notice_center.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';
import 'api_settings_screen.dart';

enum _CutoutMode { keepLasso, erase }

class ManualCutoutScreen extends StatefulWidget {
  const ManualCutoutScreen({
    super.key,
    required this.imageBytes,
    required this.sourceName,
  });

  final Uint8List imageBytes;
  final String sourceName;

  @override
  State<ManualCutoutScreen> createState() => _ManualCutoutScreenState();
}

class _ManualCutoutScreenState extends State<ManualCutoutScreen> {
  ui.Image? _image;
  final List<List<Offset>> _strokes = [];
  double _brush = 0.055;
  final _CutoutMode _mode = _CutoutMode.erase;
  bool _saving = false;
  bool _autoProcessing = false;
  bool _autoApplied = false;

  @override
  void initState() {
    super.initState();
    unawaited(_decode());
  }

  Future<void> _decode() async {
    final decoded = await _decodeBytes(widget.imageBytes);
    if (!mounted) {
      decoded.dispose();
      return;
    }
    setState(() => _image = decoded);
  }

  Future<ui.Image> _decodeBytes(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }

  Future<void> _autoCutout({bool useAi = true}) async {
    if (_autoProcessing) return;
    setState(() => _autoProcessing = true);
    try {
      await AppSettings.instance.initialize();
      final result = await AiBackgroundImageWorkflow.instance.cutout(
        sourceImage: widget.imageBytes,
        imageModel: AppSettings.instance.aiImageModel,
        useAi: useAi,
      );
      if (result.warning != null) {
        AppNoticeCenter.instance.show(
          result.warning!,
          kind: AppNoticeKind.warning,
          duration: const Duration(seconds: 12),
        );
      }
      final bytes = result.bytes;
      final decoded = await _decodeBytes(bytes);
      if (!mounted) {
        decoded.dispose();
        return;
      }
      final previous = _image;
      setState(() {
        _image = decoded;
        _strokes.clear();
        _autoApplied = true;
        _autoProcessing = false;
      });
      previous?.dispose();
      AppNoticeCenter.instance.show(
        result.usedAi ? 'AI 已识别并抠出主体，可继续用橡皮精修边缘。' : '已自动抠出主体，可继续用橡皮精修边缘。',
        kind: AppNoticeKind.success,
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _autoProcessing = false);
      AppNoticeCenter.instance.showError(
        error,
        operation: useAi ? 'AI 智能抠图' : '本地抠图',
        openApiSettings: useAi
            ? () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const ApiSettingsScreen()),
              )
            : null,
      );
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<Uint8List> _render() async {
    final image = _image;
    if (image == null) throw StateError('图片尚未加载完成');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    _paintCutout(canvas, size, image, _strokes, _brush, _mode);
    final output = await recorder.endRecording().toImage(
      image.width,
      image.height,
    );
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    output.dispose();
    if (data == null) throw StateError('无法生成透明抠图');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<void> _finish({required bool saveCopy}) async {
    if (_saving || _image == null) return;
    final hasUsefulStroke =
        _autoApplied || _strokes.any((stroke) => stroke.isNotEmpty);
    if (!hasUsefulStroke) {
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: const Text('请先点击“一键抠出主体”，或在背景上直接擦除')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final bytes = await _render();
      if (saveCopy) {
        final base = widget.sourceName.replaceFirst(RegExp(r'\.[^.]+$'), '');
        await ExportService().saveImageBytes(bytes, '${base}_手动抠图.png');
      }
      if (mounted) Navigator.pop(context, bytes);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('抠图保存失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '智能抠图与精修',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() => _strokes.removeLast()),
            icon: const Icon(Icons.undo_rounded),
            tooltip: '撤销上一笔',
          ),
          IconButton(
            onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: '重置抠图',
          ),
        ],
      ),
      body: image == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                AiApiStatusBanner(
                  onOpenSettings: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const ApiSettingsScreen(),
                    ),
                  ),
                  compact: true,
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFFE5E5E5),
                    padding: const EdgeInsets.all(12),
                    alignment: Alignment.center,
                    child: AspectRatio(
                      aspectRatio: image.width / image.height,
                      child: LayoutBuilder(
                        builder: (context, constraints) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) => setState(
                            () => _strokes.add([
                              _normalize(
                                details.localPosition,
                                constraints.biggest,
                              ),
                            ]),
                          ),
                          onPanUpdate: (details) => setState(
                            () => _strokes.last.add(
                              _normalize(
                                details.localPosition,
                                constraints.biggest,
                              ),
                            ),
                          ),
                          child: CustomPaint(
                            painter: const _CheckerPainter(),
                            child: CustomPaint(
                              painter: _CutoutPainter(
                                image: image,
                                strokes: _strokes,
                                brush: _brush,
                                mode: _mode,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: AppColors.line)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _autoProcessing
                                  ? null
                                  : () => _autoCutout(useAi: true),
                              icon: _autoProcessing
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.auto_fix_high_rounded),
                              label: Text(
                                _autoProcessing ? '正在识别…' : '一键智能抠出主体',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _autoProcessing
                                  ? null
                                  : () => _autoCutout(useAi: false),
                              icon: const Icon(Icons.phone_android_rounded),
                              label: const Text('本地快速抠图'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'AI 模式会把图片发送到已配置的模型进行主体识别；本地模式不上传。完成后可直接擦除残留背景，棋盘格区域就是透明部分。',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Row(
                        children: [
                          const Icon(Icons.brush_rounded, size: 19),
                          const SizedBox(width: 8),
                          const Text('擦除笔刷'),
                          Expanded(
                            child: Slider(
                              min: 0.015,
                              max: 0.16,
                              value: _brush,
                              onChanged: (value) =>
                                  setState(() => _brush = value),
                            ),
                          ),
                          Text('${(_brush * 100).round()}'),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () => _finish(saveCopy: false),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('仅用于生成'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () => _finish(saveCopy: true),
                              icon: _saving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_alt_rounded),
                              label: const Text('保存并使用'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Offset _normalize(Offset point, Size size) {
    return Offset(
      (point.dx / size.width).clamp(0, 1),
      (point.dy / size.height).clamp(0, 1),
    );
  }
}

class _CutoutPainter extends CustomPainter {
  const _CutoutPainter({
    required this.image,
    required this.strokes,
    required this.brush,
    required this.mode,
  });

  final ui.Image image;
  final List<List<Offset>> strokes;
  final double brush;
  final _CutoutMode mode;

  @override
  void paint(Canvas canvas, Size size) =>
      _paintCutout(canvas, size, image, strokes, brush, mode, preview: true);

  @override
  bool shouldRepaint(covariant _CutoutPainter oldDelegate) => true;
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 14.0;
    final light = Paint()..color = const Color(0xFFF5F5F5);
    final dark = Paint()..color = const Color(0xFFD6D6D6);
    for (var y = 0; y < (size.height / tile).ceil(); y++) {
      for (var x = 0; x < (size.width / tile).ceil(); x++) {
        canvas.drawRect(
          Rect.fromLTWH(x * tile, y * tile, tile, tile),
          (x + y).isEven ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _paintCutout(
  Canvas canvas,
  Size size,
  ui.Image image,
  List<List<Offset>> strokes,
  double brush,
  _CutoutMode mode, {
  bool preview = false,
}) {
  final validStrokes = strokes
      .where(
        (stroke) => mode == _CutoutMode.keepLasso
            ? stroke.length >= 3
            : stroke.isNotEmpty,
      )
      .toList();
  final source = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  final destination = Offset.zero & size;
  if (mode == _CutoutMode.keepLasso) {
    if (validStrokes.isEmpty) {
      if (preview) {
        canvas.drawImageRect(
          image,
          source,
          destination,
          Paint()
            ..filterQuality = FilterQuality.high
            ..color = const Color.fromARGB(145, 255, 255, 255),
        );
      }
      return;
    }
    final path = Path();
    for (final stroke in validStrokes) {
      path.moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      path.close();
    }
    canvas.save();
    canvas.clipPath(path);
    canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
    return;
  }
  canvas.saveLayer(destination, Paint());
  canvas.drawImageRect(
    image,
    source,
    destination,
    Paint()..filterQuality = FilterQuality.high,
  );
  final paint = Paint()
    ..blendMode = BlendMode.clear
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..strokeWidth = brush * size.shortestSide;
  for (final stroke in strokes) {
    if (stroke.isEmpty) continue;
    if (stroke.length == 1) {
      canvas.drawPoints(ui.PointMode.points, [
        Offset(stroke.first.dx * size.width, stroke.first.dy * size.height),
      ], paint);
      continue;
    }
    final path = Path()
      ..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
    for (final point in stroke.skip(1)) {
      path.lineTo(point.dx * size.width, point.dy * size.height);
    }
    canvas.drawPath(path, paint);
  }
  canvas.restore();
}
