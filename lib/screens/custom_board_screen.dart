import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../data/bead_palettes.dart';
import '../models/bead_color.dart';
import '../models/bead_palette.dart';
import '../models/bead_pattern.dart';
import '../services/app_notice_center.dart';
import '../services/app_settings.dart';
import '../services/board_color_replacer.dart';
import '../services/custom_board_draft.dart';
import '../services/project_repository.dart';
import '../services/pattern_processor.dart';
import '../theme/app_theme.dart';
import '../widgets/palette_selector.dart';
import 'editor_screen.dart' show boardSizePresets;

enum _BoardTool { free, draw, erase, fill, picker, move }

class CustomBoardScreen extends StatefulWidget {
  const CustomBoardScreen({
    super.key,
    this.initialPattern,
    this.onSaved,
    this.onDirtyChanged,
    this.embedded = false,
  });

  final BeadPattern? initialPattern;
  final Future<void> Function()? onSaved;
  final ValueChanged<bool>? onDirtyChanged;
  final bool embedded;

  @override
  State<CustomBoardScreen> createState() => _CustomBoardScreenState();
}

class _DraftPreview extends StatelessWidget {
  const _DraftPreview({required this.draft, this.showGrid = false});

  final CustomBoardDraft draft;
  final bool showGrid;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFF3ECE6),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.line),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: CustomPaint(
        painter: _DraftPreviewPainter(draft, showGrid: showGrid),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _DraftPreviewPainter extends CustomPainter {
  const _DraftPreviewPainter(this.draft, {required this.showGrid});

  final CustomBoardDraft draft;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFFF7F1EB), BlendMode.src);
    final palette = BeadPalettes.byId(draft.paletteId);
    final cellWidth = size.width / draft.width;
    final cellHeight = size.height / draft.height;
    final paint = Paint();
    for (var y = 0; y < draft.height; y++) {
      for (var x = 0; x < draft.width; x++) {
        final colorIndex = draft.cells[y * draft.width + x];
        if (colorIndex < 0 || colorIndex >= palette.colors.length) continue;
        paint.color = palette.colors[colorIndex].color;
        canvas.drawRect(
          Rect.fromLTWH(
            x * cellWidth,
            y * cellHeight,
            cellWidth + .2,
            cellHeight + .2,
          ),
          paint,
        );
      }
    }
    if (showGrid && cellWidth >= 5 && cellHeight >= 5) {
      final grid = Paint()
        ..color = Colors.black.withValues(alpha: .12)
        ..strokeWidth = .5;
      for (var x = 0; x <= draft.width; x++) {
        canvas.drawLine(
          Offset(x * cellWidth, 0),
          Offset(x * cellWidth, size.height),
          grid,
        );
      }
      for (var y = 0; y <= draft.height; y++) {
        canvas.drawLine(
          Offset(0, y * cellHeight),
          Offset(size.width, y * cellHeight),
          grid,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DraftPreviewPainter oldDelegate) =>
      oldDelegate.draft != draft || oldDelegate.showGrid != showGrid;
}

class _CustomBoardScreenState extends State<CustomBoardScreen> {
  final _repository = ProjectRepository();
  final _draftStore = CustomBoardDraftStore();
  final _picker = ImagePicker();
  final _processor = PatternProcessor();
  final _transform = TransformationController();
  final _boardKey = GlobalKey();
  final _viewportKey = GlobalKey();
  late int _width;
  late int _height;
  late List<int> _cells;
  late String _title;
  var _paletteId = BeadPaletteId.mard291;
  int _selectedColor = 0;
  _BoardTool _tool = _BoardTool.free;
  final List<Map<int, int>> _undo = [];
  final List<Map<int, int>> _redo = [];
  Map<int, int>? _strokeChanges;
  bool _saving = false;
  bool _dirty = false;
  bool _restoringDraft = false;
  int _brushSize = 1;
  Offset? _brushPoint;
  Timer? _draftTimer;
  final Map<int, Offset> _freePointers = {};
  Matrix4? _freeTransformStart;
  Offset? _freeTransformFocalStart;
  double _freeTransformSpanStart = 1;
  bool _suppressFreeDrawUntilClear = false;

  BeadPalette get _palette => BeadPalettes.byId(_paletteId);

  int _indexForColor(BeadColor color) {
    final index = _palette.colors.indexWhere((item) => item.code == color.code);
    return index < 0 ? 0 : index;
  }

  void _changePalette(BeadPaletteId next) {
    if (next == _paletteId) return;
    final previous = _palette;
    final nextPalette = BeadPalettes.byId(next);
    final remap = <int, int>{};
    for (var i = 0; i < previous.colors.length; i++) {
      final code = previous.colors[i].code;
      remap[i] = nextPalette.colors.indexWhere((color) => color.code == code);
    }
    setState(() {
      _paletteId = next;
      _cells = _cells
          .map((value) => value < 0 ? -1 : (remap[value] ?? -1))
          .toList();
      _selectedColor = nextPalette.colors.indexWhere(
        (color) => color.code == 'MA4',
      );
      if (_selectedColor < 0) _selectedColor = 0;
      _undo.clear();
      _redo.clear();
    });
    _markChanged();
  }

  @override
  void initState() {
    super.initState();
    final pattern = widget.initialPattern;
    _paletteId = pattern?.paletteId ?? BeadPaletteId.mard291;
    _width = pattern?.width ?? 29;
    _height = pattern?.height ?? 29;
    _title = pattern == null ? '自定义作品' : '${pattern.title} 修改版';
    if (pattern == null) {
      _cells = List<int>.filled(_width * _height, -1);
    } else {
      final lookup = <int, int>{
        for (var i = 0; i < pattern.colors.length; i++)
          i: _indexForColor(pattern.colors[i]),
      };
      _cells = pattern.cells
          .map((value) => value < 0 ? -1 : lookup[value] ?? -1)
          .toList();
    }
    _selectedColor = _palette.colors.indexWhere((color) => color.code == 'MA4');
    if (_selectedColor < 0) _selectedColor = 0;
    if (widget.embedded && pattern == null) {
      unawaited(_restoreDraft());
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (_dirty) unawaited(_persistDraft());
    _transform.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    if (_restoringDraft) return;
    _restoringDraft = true;
    final draft = await _draftStore.load();
    if (!mounted || draft == null) return;
    setState(() {
      _width = draft.width;
      _height = draft.height;
      _cells = List<int>.from(draft.cells);
      _title = draft.title;
      _paletteId = draft.paletteId;
      _selectedColor = draft.selectedColor.clamp(0, _palette.colors.length - 1);
      _dirty = true;
    });
    widget.onDirtyChanged?.call(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(
          content: Text(
            '已恢复 ${draft.updatedAt.month}月${draft.updatedAt.day}日的自动草稿',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  CustomBoardDraft _currentDraft() => CustomBoardDraft(
    width: _width,
    height: _height,
    cells: List<int>.from(_cells),
    title: _title,
    selectedColor: _selectedColor,
    updatedAt: DateTime.now(),
    paletteId: _paletteId,
  );

  void _applyDraft(CustomBoardDraft draft) {
    _draftTimer?.cancel();
    setState(() {
      _width = draft.width;
      _height = draft.height;
      _cells = List<int>.from(draft.cells);
      _title = draft.title;
      _paletteId = draft.paletteId;
      _selectedColor = draft.selectedColor.clamp(0, _palette.colors.length - 1);
      _undo.clear();
      _redo.clear();
      _dirty = true;
      _transform.value = Matrix4.identity();
    });
    widget.onDirtyChanged?.call(true);
    unawaited(_persistDraft());
  }

  Future<void> _archiveCurrent(String reason) =>
      _draftStore.archive(_currentDraft(), reason: reason);

  void _markChanged() {
    if (!_dirty) {
      _dirty = true;
      widget.onDirtyChanged?.call(true);
    }
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(_persistDraft());
    });
  }

  Future<void> _persistDraft() => _draftStore.save(_currentDraft());

  void _beginStroke() => _strokeChanges = <int, int>{};

  void _selectBoardTool(_BoardTool tool) {
    _freePointers.clear();
    _freeTransformStart = null;
    _freeTransformFocalStart = null;
    _suppressFreeDrawUntilClear = false;
    _endStroke();
    setState(() => _tool = tool);
  }

  void _freePointerDown(PointerDownEvent event) {
    _freePointers[event.pointer] = event.position;
    if (_freePointers.length == 1 && !_suppressFreeDrawUntilClear) {
      _beginStroke();
      _applyFreeAt(event.position);
      return;
    }
    if (_freePointers.length >= 2) {
      _endStroke();
      _suppressFreeDrawUntilClear = true;
      _startFreeTransform();
    }
  }

  void _freePointerMove(PointerMoveEvent event) {
    if (!_freePointers.containsKey(event.pointer)) return;
    _freePointers[event.pointer] = event.position;
    if (_freePointers.length >= 2) {
      _updateFreeTransform();
    } else if (!_suppressFreeDrawUntilClear) {
      _applyFreeAt(event.position);
    }
  }

  void _freePointerEnd(PointerEvent event) {
    if (!_freePointers.containsKey(event.pointer)) return;
    if (_freePointers.length == 1 && !_suppressFreeDrawUntilClear) {
      _endStroke();
    }
    _freePointers.remove(event.pointer);
    if (_freePointers.length >= 2) {
      _startFreeTransform();
    } else {
      _freeTransformStart = null;
      _freeTransformFocalStart = null;
    }
    if (_freePointers.isEmpty) {
      _suppressFreeDrawUntilClear = false;
    }
  }

  void _applyFreeAt(Offset globalPosition) {
    final renderObject = _boardKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    _applyAt(renderObject.globalToLocal(globalPosition), renderObject.size);
  }

  void _startFreeTransform() {
    final points = _freePointers.values.take(2).toList(growable: false);
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (points.length < 2 || viewport is! RenderBox) return;
    _freeTransformStart = _transform.value.clone();
    _freeTransformFocalStart = viewport.globalToLocal(
      Offset(
        (points[0].dx + points[1].dx) / 2,
        (points[0].dy + points[1].dy) / 2,
      ),
    );
    _freeTransformSpanStart = math.max(1, (points[0] - points[1]).distance);
  }

  void _updateFreeTransform() {
    final initial = _freeTransformStart;
    final initialFocal = _freeTransformFocalStart;
    final viewport = _viewportKey.currentContext?.findRenderObject();
    final points = _freePointers.values.take(2).toList(growable: false);
    if (initial == null ||
        initialFocal == null ||
        viewport is! RenderBox ||
        points.length < 2) {
      return;
    }
    final currentFocal = viewport.globalToLocal(
      Offset(
        (points[0].dx + points[1].dx) / 2,
        (points[0].dy + points[1].dy) / 2,
      ),
    );
    final span = math.max(1, (points[0] - points[1]).distance);
    final initialScale = initial.getMaxScaleOnAxis();
    final targetScale = (initialScale * span / _freeTransformSpanStart).clamp(
      0.4,
      8.0,
    );
    final scaleDelta = targetScale / initialScale;
    final next = Matrix4.identity()
      ..translateByDouble(currentFocal.dx, currentFocal.dy, 0, 1)
      ..scaleByDouble(scaleDelta, scaleDelta, 1, 1)
      ..translateByDouble(-initialFocal.dx, -initialFocal.dy, 0, 1)
      ..multiply(initial);
    _transform.value = next;
  }

  void _endStroke() {
    final changes = _strokeChanges;
    _strokeChanges = null;
    if (changes == null || changes.isEmpty) return;
    _undo.add(changes);
    if (_undo.length > 80) _undo.removeAt(0);
    _redo.clear();
    _markChanged();
  }

  void _applyAt(Offset point, Size size) {
    final x = (point.dx / size.width * _width).floor();
    final y = (point.dy / size.height * _height).floor();
    if (x < 0 || x >= _width || y < 0 || y >= _height) return;
    _brushPoint = point;
    final index = y * _width + x;
    if (_tool == _BoardTool.picker) {
      if (_cells[index] >= 0) {
        setState(() {
          _selectedColor = _cells[index];
          _tool = _BoardTool.free;
        });
      }
      return;
    }
    if (_tool == _BoardTool.fill) {
      _floodFill(index, _selectedColor);
      return;
    }
    final next = _tool == _BoardTool.erase ? -1 : _selectedColor;
    final radius = (_brushSize - 1) ~/ 2;
    final changes = <int, int>{};
    for (var row = y - radius; row <= y + radius; row++) {
      for (var column = x - radius; column <= x + radius; column++) {
        if (column < 0 || column >= _width || row < 0 || row >= _height) {
          continue;
        }
        final target = row * _width + column;
        if (_cells[target] == next) continue;
        _strokeChanges?.putIfAbsent(target, () => _cells[target]);
        changes[target] = next;
      }
    }
    if (changes.isEmpty) return;
    setState(() {
      for (final entry in changes.entries) {
        _cells[entry.key] = entry.value;
      }
    });
  }

  void _floodFill(int start, int replacement) {
    final target = _cells[start];
    if (target == replacement) return;
    final changes = <int, int>{};
    final queue = <int>[start];
    final visited = <int>{start};
    while (queue.isNotEmpty) {
      final index = queue.removeLast();
      if (_cells[index] != target) continue;
      changes[index] = target;
      final x = index % _width;
      final y = index ~/ _width;
      if (x > 0 && visited.add(index - 1)) queue.add(index - 1);
      if (x + 1 < _width && visited.add(index + 1)) queue.add(index + 1);
      if (y > 0 && visited.add(index - _width)) queue.add(index - _width);
      if (y + 1 < _height && visited.add(index + _width)) {
        queue.add(index + _width);
      }
    }
    setState(() {
      for (final index in changes.keys) {
        _cells[index] = replacement;
      }
      _undo.add(changes);
      _redo.clear();
    });
    _markChanged();
  }

  void _undoChange() {
    if (_undo.isEmpty) return;
    final changes = _undo.removeLast();
    final reverse = <int, int>{};
    setState(() {
      for (final entry in changes.entries) {
        reverse[entry.key] = _cells[entry.key];
        _cells[entry.key] = entry.value;
      }
      _redo.add(reverse);
    });
    _markChanged();
  }

  void _redoChange() {
    if (_redo.isEmpty) return;
    final changes = _redo.removeLast();
    final reverse = <int, int>{};
    setState(() {
      for (final entry in changes.entries) {
        reverse[entry.key] = _cells[entry.key];
        _cells[entry.key] = entry.value;
      }
      _undo.add(reverse);
    });
    _markChanged();
  }

  void _replaceColor(int source, int target) {
    if (source == target) return;
    late Map<int, int> changes;
    setState(() {
      changes = replaceBoardColorInPlace(
        _cells,
        source: source,
        target: target,
      );
      if (changes.isEmpty) return;
      _undo.add(changes);
      if (_undo.length > 80) _undo.removeAt(0);
      _redo.clear();
      _selectedColor = target;
    });
    if (changes.isEmpty) return;
    _markChanged();
    AppNoticeCenter.instance.showSnackBar(
      SnackBar(
        content: Text(
          '已将 ${_palette.colors[source].code} 批量替换为 '
          '${_palette.colors[target].code}，共 ${changes.length} 格',
        ),
      ),
    );
  }

  Future<void> _showReplaceColorDialog({int? initialSource}) async {
    final counts = <int, int>{};
    for (final cell in _cells) {
      if (cell >= 0) counts[cell] = (counts[cell] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      AppNoticeCenter.instance.showSnackBar(
        const SnackBar(content: Text('画板中还没有可替换的颜色')),
      );
      return;
    }
    final used = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final source = counts.containsKey(initialSource)
        ? initialSource!
        : used.first.key;
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) => _ReplaceColorDialog(
        palette: _palette,
        usedColors: used,
        initialSource: source,
        initialTarget: _selectedColor == source ? null : _selectedColor,
      ),
    );
    if (result == null || !mounted) return;
    _replaceColor(result.$1, result.$2);
  }

  Future<void> _chooseSize() async {
    final widthController = TextEditingController(text: '$_width');
    final heightController = TextEditingController(text: '$_height');
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建画板'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final size in boardSizePresets)
                    ActionChip(
                      label: Text('$size×$size'),
                      onPressed: () {
                        widthController.text = '$size';
                        heightController.text = '$size';
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: widthController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '宽度'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: heightController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '高度'),
                    ),
                  ),
                ],
              ),
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
              final width = int.tryParse(widthController.text);
              final height = int.tryParse(heightController.text);
              if (width == null ||
                  height == null ||
                  width < 5 ||
                  height < 5 ||
                  width > 300 ||
                  height > 300) {
                return;
              }
              Navigator.pop(context, (width, height));
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    widthController.dispose();
    heightController.dispose();
    if (result == null || !mounted) return;
    if (_cells.any((value) => value >= 0)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('更换尺寸并清空画板？'),
          content: const Text('创建新尺寸会清空当前内容。自动草稿会在确认后替换，无法通过返回恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留当前画板'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空并创建'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (_cells.any((value) => value >= 0)) {
      await _archiveCurrent('更换画板尺寸前自动备份');
    }
    setState(() {
      _width = result.$1;
      _height = result.$2;
      _cells = List<int>.filled(_width * _height, -1);
      _undo.clear();
      _redo.clear();
      _transform.value = Matrix4.identity();
    });
    _markChanged();
  }

  Future<void> _factoryReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restart_alt_rounded),
        title: const Text('恢复出厂白板？'),
        content: const Text('画板将恢复为 29×29 空白板，当前内容、撤销记录和自动草稿都会被清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复白板'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _draftTimer?.cancel();
    await _archiveCurrent('恢复出厂白板前自动备份');
    await _draftStore.clear();
    if (!mounted) return;
    setState(() {
      _width = 29;
      _height = 29;
      _cells = List<int>.filled(29 * 29, -1);
      _title = '自定义作品';
      _selectedColor = _palette.colors.indexWhere(
        (color) => color.code == 'MA4',
      );
      if (_selectedColor < 0) _selectedColor = 0;
      _tool = _BoardTool.free;
      _undo.clear();
      _redo.clear();
      _dirty = widget.initialPattern != null;
      _transform.value = Matrix4.identity();
    });
    widget.onDirtyChanged?.call(_dirty);
    AppNoticeCenter.instance.showSnackBar(
      const SnackBar(content: Text('已恢复 29×29 出厂白板')),
    );
  }

  Future<void> _confirmDiscardAndPop() async {
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.edit_note_rounded),
        title: const Text('画板还没有保存'),
        content: const Text('可以继续编辑，或放弃本次修改。首页自定义画板的自动草稿不会因切换选项卡丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('继续编辑'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'stash'),
            child: const Text('暂存并退出'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    if (decision == null || !mounted) return;
    if (decision == 'stash') {
      await _persistDraft();
      await _archiveCurrent('手动暂存');
    } else {
      await _archiveCurrent('放弃修改前自动备份');
      await _draftStore.clear();
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _manualStash() async {
    await _persistDraft();
    await _archiveCurrent('手动暂存');
    if (!mounted) return;
    AppNoticeCenter.instance.showSnackBar(
      const SnackBar(content: Text('已暂存，下次打开软件可继续绘制')),
    );
  }

  Future<void> _showTemporaryTrash() async {
    if (_dirty && _cells.any((value) => value >= 0)) {
      await _persistDraft();
      await _archiveCurrent('打开临时回收站前自动保护');
    }
    var entries = await _draftStore.loadTrash();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.68,
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.history_rounded),
                  title: Text(
                    '自定义画板临时回收站',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text('自动保留最近 20 份，可恢复后继续编辑'),
                ),
                const Divider(height: 1),
                Expanded(
                  child: entries.isEmpty
                      ? const Center(child: Text('暂时没有可恢复的画板'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 7),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final time = entry.draft.updatedAt;
                            return Card(
                              child: ListTile(
                                leading: SizedBox(
                                  width: 64,
                                  height: 54,
                                  child: _DraftPreview(draft: entry.draft),
                                ),
                                title: Text(
                                  entry.draft.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${entry.draft.width}×${entry.draft.height} · ${entry.reason}\n'
                                  '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
                                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                ),
                                isThreeLine: true,
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _applyDraft(entry.draft);
                                },
                                onLongPress: () =>
                                    _previewTemporaryDraft(entry),
                                trailing: IconButton(
                                  tooltip: '删除这份暂存',
                                  onPressed: () async {
                                    await _draftStore.deleteTrash(entry.id);
                                    entries = await _draftStore.loadTrash();
                                    setSheetState(() {});
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _previewTemporaryDraft(CustomBoardTrashEntry entry) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.draft.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${entry.draft.width}×${entry.draft.height} · ${entry.reason}',
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: AspectRatio(
                    aspectRatio: entry.draft.width / entry.draft.height,
                    child: _DraftPreview(draft: entry.draft, showGrid: true),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭预览'),
                    ),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(context);
                        _applyDraft(entry.draft);
                      },
                      child: const Text('恢复这份作品'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseColor() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _ColorPickerSheet(selected: _selectedColor, palette: _palette),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedColor = result;
        _tool = _BoardTool.free;
      });
    }
  }

  Future<void> _chooseBrushSize() async {
    var size = _brushSize.toDouble();
    final value = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${_tool == _BoardTool.erase ? '橡皮' : '画笔'}大小'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: size,
                min: 1,
                max: 9,
                divisions: 8,
                label: '${size.round()}×${size.round()}',
                onChanged: (next) => setDialogState(() => size = next),
              ),
              Text('${size.round()} × ${size.round()} 格'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, size.round()),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    if (value != null && mounted) setState(() => _brushSize = value);
  }

  Future<bool> _confirmReplaceBoard(String action) async {
    if (!_cells.any((value) => value >= 0)) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text('$action？'),
        content: const Text('当前画板会先自动放入临时回收站，之后仍可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('备份并继续'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _exportBoard() async {
    try {
      await _draftStore.share(_currentDraft());
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('导出画板失败：$error')),
      );
    }
  }

  Future<void> _importBoard() async {
    try {
      final draft = await _draftStore.pickAndImport();
      if (draft == null || !mounted) return;
      if (!await _confirmReplaceBoard('导入画板工程') || !mounted) return;
      await _archiveCurrent('导入画板工程前自动备份');
      if (!mounted) return;
      _applyDraft(draft);
      AppNoticeCenter.instance.showSnackBar(
        const SnackBar(content: Text('工程导入成功，可以继续编辑')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('导入画板失败：$error')),
      );
    }
  }

  Future<void> _importImage() async {
    var progressOpen = false;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
        requestFullMetadata: false,
      );
      if (file == null || !mounted) return;
      if (!await _confirmReplaceBoard('把图片转换到当前画板') || !mounted) {
        return;
      }
      await _archiveCurrent('导入图片前自动备份');
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 18),
              Expanded(child: Text('正在按当前尺寸转换图片…')),
            ],
          ),
        ),
      );
      progressOpen = true;
      final pattern = await _processor.process(
        Uint8List.fromList(await file.readAsBytes()),
        ProcessingOptions(
          size: _width,
          height: _height,
          maxColors: 300,
          portraitMode: false,
          smoothing: false,
          paletteId: _paletteId,
        ),
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      progressOpen = false;
      final colorLookup = <int, int>{
        for (var i = 0; i < pattern.colors.length; i++)
          i: _indexForColor(pattern.colors[i]),
      };
      final baseName = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      _applyDraft(
        CustomBoardDraft(
          width: pattern.width,
          height: pattern.height,
          cells: pattern.cells
              .map((value) => value < 0 ? -1 : colorLookup[value] ?? -1)
              .toList(),
          title: baseName.isEmpty ? '导入图片作品' : baseName,
          selectedColor: _selectedColor,
          updatedAt: DateTime.now(),
          paletteId: _paletteId,
        ),
      );
      AppNoticeCenter.instance.showSnackBar(
        const SnackBar(content: Text('图片已导入，可逐格继续修改')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      if (progressOpen) Navigator.of(context, rootNavigator: true).pop();
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('导入图片失败：$error')),
      );
    }
  }

  Future<({String title, bool overwrite})?> _askSaveOptions() async {
    final controller = TextEditingController(text: _title);
    var overwrite = false;
    final result = await showDialog<({String title, bool overwrite})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('保存自定义画板'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: '作品名称',
                  prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
                ),
              ),
              if (widget.initialPattern != null) ...[
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.add_to_photos_outlined),
                      label: Text('保存为新作品'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.layers_rounded),
                      label: Text('覆盖当前作品'),
                    ),
                  ],
                  selected: {overwrite},
                  onSelectionChanged: (value) =>
                      setDialogState(() => overwrite = value.first),
                ),
                const SizedBox(height: 8),
                Text(
                  overwrite ? '覆盖前的版本会自动放入作品回收站。' : '原作品保持不变，新建一份可继续编辑的作品。',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final title = controller.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(context, (title: title, overwrite: overwrite));
              },
              child: const Text('确认保存'),
            ),
          ],
        ),
      ),
    );
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 350),
        controller.dispose,
      ),
    );
    return result;
  }

  Future<void> _save() async {
    if (_saving) return;
    final used = _cells.where((value) => value >= 0).toSet().toList()
      ..sort(
        (a, b) => _palette.colors[a].code.compareTo(_palette.colors[b].code),
      );
    if (used.isEmpty) {
      AppNoticeCenter.instance.showSnackBar(
        const SnackBar(content: Text('画板还是空的，请先绘制一些拼豆')),
      );
      return;
    }
    final saveOptions = await _askSaveOptions();
    if (saveOptions == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final indexMap = <int, int>{
        for (var i = 0; i < used.length; i++) used[i]: i,
      };
      final colors = used.map((index) => _palette.colors[index]).toList();
      final mapped = _cells
          .map((value) => value < 0 ? -1 : indexMap[value]!)
          .toList();
      final now = DateTime.now();
      final image = img.Image(width: _width, height: _height, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(255, 255, 255, 0));
      for (var i = 0; i < mapped.length; i++) {
        final colorIndex = mapped[i];
        if (colorIndex < 0) continue;
        final color = colors[colorIndex];
        image.setPixelRgba(
          i % _width,
          i ~/ _width,
          color.red,
          color.green,
          color.blue,
          255,
        );
      }
      final source = Uint8List.fromList(img.encodePng(image));
      final overwrite = saveOptions.overwrite && widget.initialPattern != null;
      if (overwrite) {
        await _repository.snapshotToTrash(
          widget.initialPattern!.id,
          deletionSource: '自定义画板覆盖',
        );
      }
      final pattern = BeadPattern(
        id: overwrite
            ? widget.initialPattern!.id
            : now.microsecondsSinceEpoch.toString(),
        title: saveOptions.title,
        width: _width,
        height: _height,
        colors: colors,
        cells: mapped,
        sourceBytes: source,
        referenceBytes: source,
        createdAt: overwrite ? widget.initialPattern!.createdAt : now,
        requestedColorCount: colors.length,
        portraitMode: false,
        smoothing: false,
        sourceName: '自定义画板.png',
        isCustomBoard: true,
        paletteId: _paletteId,
      );
      await _repository.save(pattern);
      await widget.onSaved?.call();
      _draftTimer?.cancel();
      await _draftStore.clear();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
        _title = saveOptions.title;
      });
      widget.onDirtyChanged?.call(false);
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(
          content: Text(
            overwrite
                ? '“${pattern.title}”已覆盖保存，旧版本已放入回收站'
                : '“${pattern.title}”已保存到我的作品',
          ),
        ),
      );
      if (!widget.embedded) Navigator.pop(context, pattern.id);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final boardPixels = math.max(360.0, math.max(_width, _height) * 14.0);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ToolBar(
          tool: _tool,
          color: _palette.colors[_selectedColor],
          canUndo: _undo.isNotEmpty,
          canRedo: _redo.isNotEmpty,
          onTool: _selectBoardTool,
          onColor: _chooseColor,
          onReplaceColor: () => _showReplaceColorDialog(),
          onUndo: _undoChange,
          onRedo: _redoChange,
          onFactoryReset: _factoryReset,
          onStash: _manualStash,
          onTemporaryTrash: _showTemporaryTrash,
          brushSize: _brushSize,
          onBrushSize: _chooseBrushSize,
          onImportImage: _importImage,
          onImportBoard: _importBoard,
          onExportBoard: _exportBoard,
          showLabels: AppSettings.instance.boardToolLabels,
          onShowLabelsChanged: (value) {
            unawaited(AppSettings.instance.setBoardToolLabels(value));
            setState(() {});
          },
        ),
        _UsedColorsBar(
          cells: _cells,
          palette: _palette,
          onReplace: (source) => _showReplaceColorDialog(initialSource: source),
        ),
        Expanded(
          child: Container(
            key: _viewportKey,
            color: const Color(0xFFE7E5E2),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _tool == _BoardTool.free
                        ? _freePointerDown
                        : null,
                    onPointerMove: _tool == _BoardTool.free
                        ? _freePointerMove
                        : null,
                    onPointerUp: _tool == _BoardTool.free
                        ? _freePointerEnd
                        : null,
                    onPointerCancel: _tool == _BoardTool.free
                        ? _freePointerEnd
                        : null,
                    child: InteractiveViewer(
                      transformationController: _transform,
                      minScale: 0.4,
                      maxScale: 8,
                      panEnabled: _tool == _BoardTool.move,
                      scaleEnabled: _tool != _BoardTool.free,
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(120),
                      child: SizedBox(
                        width: _width >= _height
                            ? boardPixels
                            : boardPixels * _width / _height,
                        height: _height >= _width
                            ? boardPixels
                            : boardPixels * _height / _width,
                        child: LayoutBuilder(
                          builder: (context, constraints) => GestureDetector(
                            key: const ValueKey('customBoardCanvasGesture'),
                            behavior: HitTestBehavior.opaque,
                            onPanStart:
                                _tool == _BoardTool.move ||
                                    _tool == _BoardTool.free
                                ? null
                                : (details) {
                                    _beginStroke();
                                    _applyAt(
                                      details.localPosition,
                                      constraints.biggest,
                                    );
                                  },
                            onPanUpdate:
                                _tool == _BoardTool.move ||
                                    _tool == _BoardTool.free ||
                                    _tool == _BoardTool.fill ||
                                    _tool == _BoardTool.picker
                                ? null
                                : (details) => _applyAt(
                                    details.localPosition,
                                    constraints.biggest,
                                  ),
                            onPanEnd:
                                _tool == _BoardTool.move ||
                                    _tool == _BoardTool.free
                                ? null
                                : (_) => _endStroke(),
                            onTapUp:
                                _tool == _BoardTool.move ||
                                    _tool == _BoardTool.free
                                ? null
                                : (details) {
                                    _beginStroke();
                                    _applyAt(
                                      details.localPosition,
                                      constraints.biggest,
                                    );
                                    _endStroke();
                                  },
                            child: CustomPaint(
                              key: _boardKey,
                              painter: _BoardPainter(
                                width: _width,
                                height: _height,
                                cells: _cells,
                                palette: _palette,
                                tool: _tool,
                                brushSize: _brushSize,
                                brushPoint: _brushPoint,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_tool == _BoardTool.free)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.68),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 7,
                          ),
                          child: Text(
                            '自由创作 · 单指画豆 · 双指移动/缩放',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: IconButton.filledTonal(
                    key: const ValueKey('resetCustomBoardViewportButton'),
                    onPressed: () => _transform.value = Matrix4.identity(),
                    tooltip: '重置画面位置与缩放',
                    icon: const Icon(Icons.center_focus_strong_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.initialPattern == null
                  ? '自定义画板'
                  : widget.initialPattern!.isCustomBoard
                  ? '继续编辑自定义画板'
                  : '自定义修改颜色',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              '$_width×$_height · ${_cells.where((value) => value >= 0).length} 颗',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final selected = await showPaletteSelector(
                context,
                selected: _paletteId,
              );
              if (selected != null) _changePalette(selected);
            },
            icon: const Icon(Icons.palette_outlined),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 105),
              child: Text(
                _palette.shortName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (AppSettings.instance.boardToolLabels) ...[
            Tooltip(
              message: '设置画板尺寸：新建预设或自定义宽高，已有内容会先确认',
              child: TextButton.icon(
                onPressed: _chooseSize,
                icon: const Icon(Icons.aspect_ratio_rounded),
                label: const Text('尺寸'),
              ),
            ),
            Tooltip(
              message: '保存到我的作品：生成可预览、统计和导出的正式作品',
              child: TextButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('保存'),
              ),
            ),
          ] else ...[
            IconButton(
              onPressed: _chooseSize,
              icon: const Icon(Icons.aspect_ratio_rounded),
              tooltip: '设置画板尺寸：新建预设或自定义宽高，已有内容会先确认',
            ),
            IconButton(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : const Icon(Icons.save_rounded),
              tooltip: '保存到我的作品：生成可预览、统计和导出的正式作品',
            ),
          ],
        ],
      ),
      body: content,
    );
    if (widget.embedded) return scaffold;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmDiscardAndPop());
      },
      child: scaffold,
    );
  }
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({
    required this.tool,
    required this.color,
    required this.canUndo,
    required this.canRedo,
    required this.onTool,
    required this.onColor,
    required this.onReplaceColor,
    required this.onUndo,
    required this.onRedo,
    required this.onFactoryReset,
    required this.onStash,
    required this.onTemporaryTrash,
    required this.brushSize,
    required this.onBrushSize,
    required this.onImportImage,
    required this.onImportBoard,
    required this.onExportBoard,
    required this.showLabels,
    required this.onShowLabelsChanged,
  });

  final _BoardTool tool;
  final BeadColor color;
  final bool canUndo;
  final bool canRedo;
  final ValueChanged<_BoardTool> onTool;
  final VoidCallback onColor;
  final VoidCallback onReplaceColor;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onFactoryReset;
  final VoidCallback onStash;
  final VoidCallback onTemporaryTrash;
  final int brushSize;
  final VoidCallback onBrushSize;
  final VoidCallback onImportImage;
  final VoidCallback onImportBoard;
  final VoidCallback onExportBoard;
  final bool showLabels;
  final ValueChanged<bool> onShowLabelsChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          _commandButton(
            context,
            Icons.undo_rounded,
            '撤销',
            '撤销：恢复最近一次画笔、橡皮或填充操作',
            canUndo ? onUndo : null,
          ),
          _commandButton(
            context,
            Icons.redo_rounded,
            '重做',
            '重做：重新应用刚刚撤销的操作',
            canRedo ? onRedo : null,
          ),
          const VerticalDivider(),
          Tooltip(
            message: '取色：点击已有拼豆读取其颜色，然后自动切回画笔',
            child: ActionChip(
              avatar: CircleAvatar(backgroundColor: color.color),
              label: Text(showLabels ? '取色 ${color.code}' : color.code),
              onPressed: onColor,
            ),
          ),
          _commandButton(
            context,
            Icons.find_replace_rounded,
            '批量换色',
            '批量换色：选择画板中已使用的色号，一次替换为当前色库中的其他色号',
            onReplaceColor,
          ),
          _toolButton(
            context,
            Icons.gesture_rounded,
            '自由创作',
            '自由创作：单指直接画豆，双指随时移动和缩放，不需要切换移动工具',
            _BoardTool.free,
          ),
          _toolButton(
            context,
            Icons.edit_rounded,
            '画笔',
            '画笔：按住并拖动，在经过的格子放置当前颜色',
            _BoardTool.draw,
          ),
          _toolButton(
            context,
            Icons.auto_fix_off_rounded,
            '橡皮',
            '橡皮：按住并拖动，清除经过格子的拼豆',
            _BoardTool.erase,
          ),
          Tooltip(
            message: '设置画笔或橡皮的作用范围，当前为 $brushSize×$brushSize 格',
            child: showLabels
                ? OutlinedButton.icon(
                    onPressed: onBrushSize,
                    icon: const Icon(Icons.brush_outlined, size: 17),
                    label: Text('$brushSize×$brushSize'),
                    style: _compactButtonStyle(),
                  )
                : IconButton(
                    onPressed: onBrushSize,
                    icon: const Icon(Icons.brush_outlined),
                    tooltip: '$brushSize×$brushSize',
                  ),
          ),
          _toolButton(
            context,
            Icons.format_color_fill_rounded,
            '填充',
            '填充：点击一个连续区域，一次替换整个区域的颜色',
            _BoardTool.fill,
          ),
          _toolButton(
            context,
            Icons.colorize_rounded,
            '取色',
            '取色：点击已有拼豆读取其颜色，然后自动切回画笔',
            _BoardTool.picker,
          ),
          _toolButton(
            context,
            Icons.pan_tool_alt_rounded,
            '移动',
            '移动：拖动画板位置；双指仍可缩放画板',
            _BoardTool.move,
          ),
          const SizedBox(width: 8),
          _commandButton(
            context,
            Icons.inventory_2_outlined,
            '暂存',
            '暂存：保存当前进度并加入临时回收站，下次打开软件可继续',
            onStash,
          ),
          _commandButton(
            context,
            Icons.history_rounded,
            '临时回收站',
            '临时回收站：打开最近 20 份自动备份并恢复继续编辑',
            onTemporaryTrash,
          ),
          _commandButton(
            context,
            Icons.add_photo_alternate_outlined,
            '导入图片',
            '导入图片：把相册图片转换到当前画板，之后可以逐格修改',
            onImportImage,
          ),
          _commandButton(
            context,
            Icons.file_download_outlined,
            '导入工程',
            '导入工程：读取 .beadboard 文件并继续编辑别人分享的画板',
            onImportBoard,
          ),
          _commandButton(
            context,
            Icons.file_upload_outlined,
            '导出工程',
            '导出工程：分享完整可编辑画板，不只是导出一张图片',
            onExportBoard,
          ),
          const SizedBox(width: 8),
          const SizedBox(width: 6),
          Tooltip(
            message: '恢复出厂白板：清空草稿并恢复为 29×29 空白画板',
            child: showLabels
                ? OutlinedButton.icon(
                    onPressed: onFactoryReset,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('白板'),
                    style: _compactButtonStyle(),
                  )
                : IconButton(
                    onPressed: onFactoryReset,
                    icon: const Icon(Icons.restart_alt_rounded),
                  ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: '按钮文字：开启后工具栏同时显示图标和名称；关闭后只显示图标',
            child: FilterChip(
              selected: showLabels,
              onSelected: onShowLabelsChanged,
              avatar: Icon(
                showLabels ? Icons.label_rounded : Icons.label_off_outlined,
                size: 18,
              ),
              label: const Text('按钮文字'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _toolButton(
    BuildContext context,
    IconData icon,
    String label,
    String description,
    _BoardTool value,
  ) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Tooltip(
      message: description,
      child: showLabels
          ? FilledButton.tonalIcon(
              key: ValueKey('customBoardTool_${value.name}'),
              onPressed: () => onTool(value),
              icon: Icon(icon, size: 19),
              label: Text(label),
              style: _compactButtonStyle(selected: tool == value),
            )
          : IconButton.filledTonal(
              key: ValueKey('customBoardTool_${value.name}'),
              onPressed: () => onTool(value),
              isSelected: tool == value,
              icon: Icon(icon),
            ),
    ),
  );

  Widget _commandButton(
    BuildContext context,
    IconData icon,
    String label,
    String description,
    VoidCallback? onPressed,
  ) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Tooltip(
      message: description,
      child: showLabels
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 19),
              label: Text(label),
              style: _compactButtonStyle(),
            )
          : IconButton(onPressed: onPressed, icon: Icon(icon)),
    ),
  );

  ButtonStyle _compactButtonStyle({bool selected = false}) => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(38, 36)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 11)),
    backgroundColor: selected
        ? const WidgetStatePropertyAll(Color(0xFFFFE4DC))
        : null,
  );
}

class _ReplaceColorDialog extends StatefulWidget {
  const _ReplaceColorDialog({
    required this.palette,
    required this.usedColors,
    required this.initialSource,
    this.initialTarget,
  });

  final BeadPalette palette;
  final List<MapEntry<int, int>> usedColors;
  final int initialSource;
  final int? initialTarget;

  @override
  State<_ReplaceColorDialog> createState() => _ReplaceColorDialogState();
}

class _ReplaceColorDialogState extends State<_ReplaceColorDialog> {
  late int _source;
  int? _target;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _source = widget.initialSource;
    _target = widget.initialTarget;
  }

  @override
  Widget build(BuildContext context) {
    final sourceColor = widget.palette.colors[_source];
    final sourceCount = widget.usedColors
        .firstWhere((entry) => entry.key == _source)
        .value;
    final targets = <(int, BeadColor)>[
      for (var index = 0; index < widget.palette.colors.length; index++)
        if (widget.palette.colors[index].matchesQuery(_query))
          (index, widget.palette.colors[index]),
    ];
    return AlertDialog(
      title: const Text('批量替换色号'),
      content: SizedBox(
        width: 520,
        height: MediaQuery.sizeOf(context).height * 0.64,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InputDecorator(
              decoration: const InputDecoration(
                labelText: '查找画板中已使用的色号',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _source,
                  isExpanded: true,
                  items: [
                    for (final entry in widget.usedColors)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 8,
                              backgroundColor:
                                  widget.palette.colors[entry.key].color,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${widget.palette.colors[entry.key].code} · '
                                '${widget.palette.colors[entry.key].nameCn} · '
                                '${entry.value} 格',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _source = value;
                      if (_target == value) _target = null;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: const InputDecoration(
                labelText: '搜索当前启用色库中的目标色号',
                hintText: '色号、中文颜色或英文名称',
                prefixIcon: Icon(Icons.manage_search_rounded),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '当前 ${widget.palette.displayName} · '
              '将替换 $sourceCount 格 ${sourceColor.code}',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: targets.isEmpty
                  ? const Center(child: Text('没有找到匹配的色号'))
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 118,
                            mainAxisSpacing: 7,
                            crossAxisSpacing: 7,
                            childAspectRatio: 1.25,
                          ),
                      itemCount: targets.length,
                      itemBuilder: (context, index) {
                        final entry = targets[index];
                        final disabled = entry.$1 == _source;
                        final selected = entry.$1 == _target;
                        return Tooltip(
                          message: disabled
                              ? '不能替换为相同色号'
                              : '${entry.$2.code} · ${entry.$2.nameCn}',
                          child: InkWell(
                            onTap: disabled
                                ? null
                                : () => setState(() => _target = entry.$1),
                            borderRadius: BorderRadius.circular(8),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: disabled
                                    ? Colors.black.withValues(alpha: 0.04)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : AppColors.line,
                                  width: selected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: entry.$2.color,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    entry.$2.code,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    entry.$2.nameCn,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 9),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _target == null || _target == _source
              ? null
              : () => Navigator.pop(context, (_source, _target!)),
          icon: const Icon(Icons.find_replace_rounded),
          label: Text(_target == null ? '请选择目标色号' : '替换 $sourceCount 格'),
        ),
      ],
    );
  }
}

class _UsedColorsBar extends StatelessWidget {
  const _UsedColorsBar({
    required this.cells,
    required this.palette,
    required this.onReplace,
  });

  final List<int> cells;
  final BeadPalette palette;
  final ValueChanged<int> onReplace;

  @override
  Widget build(BuildContext context) {
    final counts = <int, int>{};
    for (final cell in cells) {
      if (cell >= 0) counts[cell] = (counts[cell] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Material(
      color: const Color(0xFFFFFBF8),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 7),
              child: Text(
                '已用 ${entries.length} 色',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.teal,
                ),
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '还没有放置拼豆',
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final color = palette.colors[entry.key];
                        return Tooltip(
                          message: '双击批量替换 ${color.code}',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: () => onReplace(entry.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.line),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 7,
                                    backgroundColor: color.color,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${color.code} × ${entry.value}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  const _BoardPainter({
    required this.width,
    required this.height,
    required this.cells,
    required this.palette,
    required this.tool,
    required this.brushSize,
    required this.brushPoint,
  });

  final int width;
  final int height;
  final List<int> cells;
  final BeadPalette palette;
  final _BoardTool tool;
  final int brushSize;
  final Offset? brushPoint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final cw = size.width / width;
    final ch = size.height / height;
    final paint = Paint();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = cells[y * width + x];
        if (index < 0) continue;
        paint.color = palette.colors[index].color;
        canvas.drawRect(
          Rect.fromLTWH(x * cw, y * ch, cw + 0.2, ch + 0.2),
          paint,
        );
      }
    }
    final grid = Paint()
      ..color = const Color(0xFFB8B2AD)
      ..strokeWidth = 0.55;
    final strong = Paint()
      ..color = const Color(0xFF716C68)
      ..strokeWidth = 1.3;
    for (var x = 0; x <= width; x++) {
      canvas.drawLine(
        Offset(x * cw, 0),
        Offset(x * cw, size.height),
        x % 5 == 0 ? strong : grid,
      );
    }
    for (var y = 0; y <= height; y++) {
      canvas.drawLine(
        Offset(0, y * ch),
        Offset(size.width, y * ch),
        y % 5 == 0 ? strong : grid,
      );
    }
    if (brushPoint != null &&
        (tool == _BoardTool.free ||
            tool == _BoardTool.draw ||
            tool == _BoardTool.erase)) {
      final x = (brushPoint!.dx / cw).floor().clamp(0, width - 1);
      final y = (brushPoint!.dy / ch).floor().clamp(0, height - 1);
      final radius = (brushSize - 1) ~/ 2;
      final area = Rect.fromLTRB(
        (x - radius) * cw,
        (y - radius) * ch,
        (x + radius + 1) * cw,
        (y + radius + 1) * ch,
      ).intersect(Offset.zero & size);
      final fill = Paint()
        ..color =
            (tool == _BoardTool.erase
                    ? Colors.white
                    : palette.colors.first.color)
                .withValues(alpha: 0.24);
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = tool == _BoardTool.erase ? Colors.black54 : Colors.white;
      canvas.drawRect(area, fill);
      canvas.drawRect(area, border);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) => true;
}

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({required this.selected, required this.palette});

  final int selected;
  final BeadPalette palette;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final indexed = <(int, BeadColor)>[
      for (var i = 0; i < widget.palette.colors.length; i++)
        if (_query.isEmpty ||
            widget.palette.colors[i].code.toLowerCase().contains(
              _query.toLowerCase(),
            ) ||
            widget.palette.colors[i].matchesQuery(_query))
          (i, widget.palette.colors[i]),
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索色号或名称',
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.9,
                ),
                itemCount: indexed.length,
                itemBuilder: (context, i) {
                  final entry = indexed[i];
                  return InkWell(
                    onTap: () => Navigator.pop(context, entry.$1),
                    onDoubleTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('${entry.$2.code} · ${entry.$2.nameCn}'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                color: entry.$2.color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black26),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(entry.$2.hex),
                            Text('品牌：${entry.$2.brand} · ${entry.$2.type}'),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: entry.$1 == widget.selected
                              ? Theme.of(context).colorScheme.primary
                              : AppColors.line,
                          width: entry.$1 == widget.selected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: entry.$2.color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.$2.code,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
