import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/bead_palettes.dart';
import '../l10n/app_strings.dart';
import '../models/bead_color.dart';
import '../models/bead_palette.dart';
import '../models/bead_pattern.dart';
import '../services/app_notice_center.dart';
import '../services/color_science.dart';
import '../services/project_repository.dart';
import '../services/text_bead_renderer.dart';
import '../theme/app_theme.dart';

class TextBeadScreen extends StatefulWidget {
  const TextBeadScreen({super.key});

  @override
  State<TextBeadScreen> createState() => _TextBeadScreenState();
}

class _TextBeadScreenState extends State<TextBeadScreen> {
  final _text = TextEditingController(text: 'LOVE');
  final _widthController = TextEditingController(text: '48');
  final _heightController = TextEditingController(text: '32');
  var _foreground = const Color(0xFFE94B4B);
  var _background = Colors.white;
  var _font = 'sans-serif';
  var _bold = true;
  var _italic = false;
  var _paletteId = BeadPaletteId.mard291;
  var _boardWidth = 48;
  var _boardHeight = 32;
  var _layout = TextBeadLayout.horizontal;
  List<Offset> _characterOffsets = const [];
  var _working = false;
  var _previewLoading = false;
  TextBeadRenderResult? _previewResult;
  Timer? _previewTimer;
  var _previewRevision = 0;
  final _projects = ProjectRepository();

  static const _swatches = <Color>[
    Color(0xFFE53935),
    Color(0xFFFFB300),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
    Color(0xFF212121),
    Colors.white,
  ];
  static const _presets = <(int, int)>[
    (29, 29),
    (32, 32),
    (48, 48),
    (48, 32),
    (64, 48),
    (80, 64),
  ];

  @override
  void initState() {
    super.initState();
    _syncCharacterOffsets();
    _queuePreview(immediate: true);
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _text.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _changed() {
    setState(_syncCharacterOffsets);
    _queuePreview();
  }

  void _syncCharacterOffsets() {
    final count = TextBeadRenderer.editableCharacters(_text.text).length;
    _characterOffsets = List<Offset>.generate(
      count,
      (index) => index < _characterOffsets.length
          ? _characterOffsets[index]
          : Offset.zero,
      growable: false,
    );
  }

  void _setLayout(TextBeadLayout value) {
    setState(() {
      _layout = value;
      _characterOffsets = List<Offset>.filled(
        TextBeadRenderer.editableCharacters(_text.text).length,
        Offset.zero,
      );
    });
    _queuePreview(immediate: true);
  }

  void _setBoardSize(int width, int height) {
    setState(() {
      _boardWidth = width;
      _boardHeight = height;
      _widthController.text = '$width';
      _heightController.text = '$height';
      _characterOffsets = List<Offset>.filled(
        TextBeadRenderer.editableCharacters(_text.text).length,
        Offset.zero,
      );
    });
    _queuePreview();
  }

  void _applyCustomSize() {
    final width = int.tryParse(_widthController.text);
    final height = int.tryParse(_heightController.text);
    if (width == null ||
        height == null ||
        width < 5 ||
        height < 5 ||
        width > 200 ||
        height > 200) {
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text(AppStrings.ui(context, '画板宽高应在 5 到 200 格之间'))),
      );
      return;
    }
    _setBoardSize(width, height);
  }

  void _queuePreview({bool immediate = false}) {
    _previewTimer?.cancel();
    final revision = ++_previewRevision;
    _previewTimer = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 180),
      () => _refreshPreview(revision),
    );
  }

  Future<void> _refreshPreview(int revision) async {
    if (mounted) setState(() => _previewLoading = true);
    try {
      final rendered = await _render();
      if (!mounted || revision != _previewRevision) return;
      setState(() => _previewResult = rendered);
    } on Object {
      // Keep the last successful preview visible while a user is typing.
    } finally {
      if (mounted && revision == _previewRevision) {
        setState(() => _previewLoading = false);
      }
    }
  }

  Future<TextBeadRenderResult> _render() => TextBeadRenderer.render(
    text: _text.text,
    width: _boardWidth,
    height: _boardHeight,
    foreground: _foreground,
    background: _background,
    fontFamily: _font,
    bold: _bold,
    italic: _italic,
    layout: _layout,
    characterOffsets: List.unmodifiable(_characterOffsets),
  );

  void _positionsChanged(List<Offset> value) {
    _characterOffsets = List.unmodifiable(value);
    _queuePreview();
  }

  Future<void> _openFullscreenPreview() async {
    final result = _previewResult;
    if (result == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(
            title: const Text('文字拼豆全屏编辑'),
            actions: [
              IconButton(
                onPressed: () => Navigator.of(routeContext).pop(),
                tooltip: '关闭全屏',
                icon: const Icon(Icons.fullscreen_exit_rounded),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final ratio = _boardWidth / _boardHeight;
                  var previewWidth = constraints.maxWidth;
                  var previewHeight = previewWidth / ratio;
                  if (previewHeight > constraints.maxHeight) {
                    previewHeight = constraints.maxHeight;
                    previewWidth = previewHeight * ratio;
                  }
                  return Center(
                    child: SizedBox(
                      width: previewWidth,
                      height: previewHeight,
                      child: _EditableTextPreview(
                        result: result,
                        offsets: _characterOffsets,
                        foreground: _foreground,
                        background: _background,
                        loading: false,
                        onChanged: _positionsChanged,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) _queuePreview(immediate: true);
  }

  Future<void> _generate() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final rendered = await _render();
      final text = _text.text.trim().isEmpty ? 'LOVE' : _text.text.trim();
      final palette = BeadPalettes.byId(_paletteId);
      final background = _nearestColor(_background, palette.colors);
      var foreground = _nearestColor(_foreground, palette.colors);
      if (_foreground.toARGB32() != _background.toARGB32() &&
          foreground.id == background.id) {
        foreground = _nearestColor(
          _foreground,
          palette.colors,
          excludedId: background.id,
        );
      }
      final sameColor = foreground.id == background.id;
      final colors = sameColor
          ? <BeadColor>[background]
          : <BeadColor>[background, foreground];
      final cells = sameColor
          ? List<int>.filled(rendered.foregroundMask.length, 0)
          : rendered.foregroundMask
                .map((isForeground) => isForeground ? 1 : 0)
                .toList(growable: false);
      final now = DateTime.now();
      final pattern = BeadPattern(
        id: now.microsecondsSinceEpoch.toString(),
        title: '文字拼豆 ${text.replaceAll('\n', ' ')}',
        width: rendered.width,
        height: rendered.height,
        colors: colors,
        cells: cells,
        sourceBytes: rendered.bytes,
        referenceBytes: rendered.bytes,
        createdAt: now,
        requestedColorCount: colors.length,
        portraitMode: false,
        smoothing: false,
        paletteId: _paletteId,
        sourceName: '文字拼豆_${text.replaceAll('\n', '_')}.png',
      );
      await _projects.save(pattern);
      if (!mounted) return;
      // Returning the id lets the home shell refresh and open "我的作品".
      // The generated pattern is already durably written before navigation.
      Navigator.of(context).pop(pattern.id);
    } on Object catch (error) {
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('${AppStrings.ui(context, '生成失败')}：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  BeadColor _nearestColor(
    Color target,
    List<BeadColor> colors, {
    int? excludedId,
  }) {
    final value = target.toARGB32();
    final lab = ColorScience.rgbToLab(
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    );
    BeadColor? best;
    var bestDistance = double.infinity;
    for (final color in colors) {
      if (color.id == excludedId) continue;
      final distance = ColorScience.deltaE2000(lab, color.lab);
      if (distance < bestDistance) {
        best = color;
        bestDistance = distance;
      }
    }
    return best ?? colors.first;
  }

  Widget _swatchRow({
    required Color value,
    required ValueChanged<Color> onChanged,
  }) => Wrap(
    spacing: 8,
    children: [
      for (final color in _swatches)
        GestureDetector(
          onTap: () {
            onChanged(color);
            _queuePreview();
          },
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: value == color ? AppColors.ink : Colors.black12,
                width: value == color ? 3 : 1,
              ),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        AppStrings.ui(context, '文字拼豆'),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      children: [
        TextField(
          controller: _text,
          onChanged: (_) => _changed(),
          maxLines: 3,
          maxLength: 60,
          decoration: InputDecoration(
            labelText: AppStrings.ui(context, '输入文字'),
            prefixIcon: Icon(Icons.text_fields_rounded),
          ),
        ),
        const SizedBox(height: 14),
        SegmentedButton<TextBeadLayout>(
          segments: const [
            ButtonSegment(
              value: TextBeadLayout.horizontal,
              icon: Icon(Icons.format_textdirection_l_to_r_rounded),
              label: Text('横向'),
            ),
            ButtonSegment(
              value: TextBeadLayout.vertical,
              icon: Icon(Icons.vertical_align_center_rounded),
              label: Text('竖向'),
            ),
            ButtonSegment(
              value: TextBeadLayout.fourGrid,
              icon: Icon(Icons.grid_view_rounded),
              label: Text('四宫格'),
            ),
          ],
          selected: {_layout},
          onSelectionChanged: (value) => _setLayout(value.first),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<BeadPaletteId>(
          initialValue: _paletteId,
          decoration: InputDecoration(
            labelText: AppStrings.ui(context, '色号方案'),
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
        const SizedBox(height: 16),
        Text(
          AppStrings.ui(context, '画板大小'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final preset in _presets)
              ChoiceChip(
                label: Text('${preset.$1}×${preset.$2}'),
                selected: _boardWidth == preset.$1 && _boardHeight == preset.$2,
                onSelected: (_) => _setBoardSize(preset.$1, preset.$2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _widthController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: AppStrings.ui(context, '自定义宽度（格）'),
                ),
                onSubmitted: (_) => _applyCustomSize(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _heightController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: AppStrings.ui(context, '自定义高度（格）'),
                ),
                onSubmitted: (_) => _applyCustomSize(),
              ),
            ),
            IconButton(
              onPressed: _applyCustomSize,
              tooltip: AppStrings.ui(context, '应用自定义画板'),
              icon: const Icon(Icons.check_circle_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.ui(context, '文字颜色'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _swatchRow(
          value: _foreground,
          onChanged: (value) => setState(() => _foreground = value),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.ui(context, '画板背景'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _swatchRow(
          value: _background,
          onChanged: (value) => setState(() => _background = value),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final family in const ['sans-serif', 'serif', 'monospace'])
              ChoiceChip(
                label: Text(family),
                selected: _font == family,
                onSelected: (_) {
                  setState(() => _font = family);
                  _queuePreview();
                },
              ),
          ],
        ),
        SwitchListTile(
          value: _bold,
          onChanged: (value) {
            setState(() => _bold = value);
            _queuePreview();
          },
          title: Text(AppStrings.ui(context, '粗体')),
          secondary: const Icon(Icons.format_bold_rounded),
        ),
        SwitchListTile(
          value: _italic,
          onChanged: (value) {
            setState(() => _italic = value);
            _queuePreview();
          },
          title: Text(AppStrings.ui(context, '斜体')),
          secondary: const Icon(Icons.format_italic_rounded),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.ui(context, '实时拼豆预览（可拖动文字位置）'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: _previewResult == null ? null : _openFullscreenPreview,
              tooltip: '全屏编辑',
              icon: const Icon(Icons.fullscreen_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 320,
          child: Center(
            child: AspectRatio(
              aspectRatio: _boardWidth / _boardHeight,
              child: _previewResult == null
                  ? const Center(child: CircularProgressIndicator())
                  : _EditableTextPreview(
                      result: _previewResult!,
                      offsets: _characterOffsets,
                      foreground: _foreground,
                      background: _background,
                      loading: _previewLoading,
                      onChanged: _positionsChanged,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _working ? null : _generate,
          icon: _working
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.edit_rounded),
          label: Text(AppStrings.ui(context, _working ? '正在生成' : '生成并保存到我的作品')),
        ),
      ],
    ),
  );
}

class _EditableTextPreview extends StatefulWidget {
  const _EditableTextPreview({
    required this.result,
    required this.offsets,
    required this.foreground,
    required this.background,
    required this.loading,
    required this.onChanged,
  });

  final TextBeadRenderResult result;
  final List<Offset> offsets;
  final Color foreground;
  final Color background;
  final bool loading;
  final ValueChanged<List<Offset>> onChanged;

  @override
  State<_EditableTextPreview> createState() => _EditableTextPreviewState();
}

class _EditableTextPreviewState extends State<_EditableTextPreview> {
  late List<Offset> _offsets;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _offsets = _normalizedOffsets(widget.offsets);
  }

  @override
  void didUpdateWidget(covariant _EditableTextPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.result, oldWidget.result)) {
      _offsets = _normalizedOffsets(widget.offsets);
      if ((_selectedIndex ?? -1) >= widget.result.characterMasks.length) {
        _selectedIndex = null;
      }
    }
  }

  List<Offset> _normalizedOffsets(List<Offset> source) => List<Offset>.generate(
    widget.result.characterMasks.length,
    (index) => index < source.length ? source[index] : Offset.zero,
    growable: false,
  );

  void _select(Offset localPosition, Size size) {
    final point = Offset(
      localPosition.dx / size.width * widget.result.width,
      localPosition.dy / size.height * widget.result.height,
    );
    int? selected;
    for (
      var index = widget.result.characterMasks.length - 1;
      index >= 0;
      index--
    ) {
      final mask = widget.result.characterMasks[index];
      final delta = _offsets[index] - mask.renderOffset;
      if (mask.bounds.shift(delta).inflate(1.5).contains(point)) {
        selected = index;
        break;
      }
    }
    setState(() => _selectedIndex = selected);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return RepaintBoundary(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _select(details.localPosition, size),
          onPanUpdate: (details) {
            final selected = _selectedIndex;
            if (selected == null) return;
            final next = List<Offset>.of(_offsets);
            next[selected] += Offset(
              details.delta.dx / size.width * widget.result.width,
              details.delta.dy / size.height * widget.result.height,
            );
            setState(() => _offsets = next);
          },
          onPanEnd: (_) => widget.onChanged(List.unmodifiable(_offsets)),
          onPanCancel: () => widget.onChanged(List.unmodifiable(_offsets)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _EditableTextPainter(
                      result: widget.result,
                      positions: _offsets,
                      foreground: widget.foreground,
                      background: widget.background,
                      selectedIndex: _selectedIndex,
                    ),
                  ),
                  if (widget.loading)
                    const Align(
                      alignment: Alignment.topCenter,
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _EditableTextPainter extends CustomPainter {
  const _EditableTextPainter({
    required this.result,
    required this.positions,
    required this.foreground,
    required this.background,
    required this.selectedIndex,
  });

  final TextBeadRenderResult result;
  final List<Offset> positions;
  final Color foreground;
  final Color background;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(background, BlendMode.src);
    final cellWidth = size.width / result.width;
    final cellHeight = size.height / result.height;
    final glyphPath = Path();
    for (
      var characterIndex = 0;
      characterIndex < result.characterMasks.length;
      characterIndex++
    ) {
      final mask = result.characterMasks[characterIndex];
      final currentOffset = characterIndex < positions.length
          ? positions[characterIndex]
          : Offset.zero;
      final delta = currentOffset - mask.renderOffset;
      for (final index in mask.cells) {
        final x = index % result.width;
        final y = index ~/ result.width;
        glyphPath.addRect(
          Rect.fromLTWH(
            (x + delta.dx) * cellWidth,
            (y + delta.dy) * cellHeight,
            cellWidth,
            cellHeight,
          ),
        );
      }
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(glyphPath, Paint()..color = foreground);

    final selected = selectedIndex;
    if (selected != null && selected < result.characterMasks.length) {
      final mask = result.characterMasks[selected];
      final currentOffset = selected < positions.length
          ? positions[selected]
          : Offset.zero;
      final delta = currentOffset - mask.renderOffset;
      final bounds = Rect.fromLTRB(
        (mask.bounds.left + delta.dx) * cellWidth,
        (mask.bounds.top + delta.dy) * cellHeight,
        (mask.bounds.right + delta.dx) * cellWidth,
        (mask.bounds.bottom + delta.dy) * cellHeight,
      );
      canvas.drawRect(
        bounds.inflate(3),
        Paint()
          ..color = const Color(0xFFE96354)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    if (math.min(cellWidth, cellHeight) < 4) {
      canvas.restore();
      return;
    }
    final line = Paint()
      ..color = Colors.black.withValues(alpha: 0.14)
      ..strokeWidth = 0.5;
    for (var x = 0; x <= result.width; x++) {
      canvas.drawLine(
        Offset(x * cellWidth, 0),
        Offset(x * cellWidth, size.height),
        line,
      );
    }
    for (var y = 0; y <= result.height; y++) {
      canvas.drawLine(
        Offset(0, y * cellHeight),
        Offset(size.width, y * cellHeight),
        line,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EditableTextPainter oldDelegate) =>
      !identical(oldDelegate.result, result) ||
      !identical(oldDelegate.positions, positions) ||
      oldDelegate.foreground != foreground ||
      oldDelegate.background != background ||
      oldDelegate.selectedIndex != selectedIndex;
}
