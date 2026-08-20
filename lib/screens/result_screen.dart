import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/bead_palettes.dart';
import '../models/bead_pattern.dart';
import '../services/ai_design_service.dart';
import '../services/app_notice_center.dart';
import '../services/export_service.dart';
import '../services/project_repository.dart';
import '../services/processing_center.dart';
import '../services/pattern_processor.dart';
import '../theme/app_theme.dart';
import '../widgets/bead_pattern_view.dart';
import '../widgets/favorite_category_picker.dart';
import 'custom_board_screen.dart';
import 'editor_screen.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.pattern, this.isNew = false});

  final BeadPattern pattern;
  final bool isNew;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _exporter = ExportService();
  final _projects = ProjectRepository();
  var _exporting = false;
  var _saving = false;
  var _aiRepairing = false;
  var _favorite = false;
  late String _title;

  @override
  void initState() {
    super.initState();
    _title = widget.pattern.title;
    unawaited(_loadFavorite());
  }

  Future<void> _loadFavorite() async {
    final favorite = await _projects.isFavorite(widget.pattern.id);
    if (mounted) setState(() => _favorite = favorite);
  }

  Future<void> _toggleFavorite() async {
    final next = !_favorite;
    if (!next) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.heart_broken_outlined),
          title: const Text('取消收藏？'),
          content: const Text('作品会保留在“我的作品”中，只从收藏分类移除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留收藏'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('取消收藏'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    String? category;
    if (next) {
      category = await showFavoriteCategoryPicker(
        context,
        repository: _projects,
      );
      if (category == null) return;
    }
    setState(() => _favorite = next);
    await _projects.setFavorite(widget.pattern.id, next, category: category);
    if (!mounted) return;
    AppNoticeCenter.instance.showSnackBar(
      SnackBar(
        content: Text(next ? '已加入“$category”' : '已取消收藏'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  ProcessingOptions _currentOptions({int? variantSeed}) => ProcessingOptions(
    size: widget.pattern.width,
    height: widget.pattern.height,
    maxColors: widget.pattern.requestedColorCount,
    portraitMode: widget.pattern.portraitMode,
    smoothing: widget.pattern.smoothing,
    removeBackground: widget.pattern.backgroundRemoved,
    template: widget.pattern.template,
    variantSeed: variantSeed ?? widget.pattern.variantSeed,
    paletteId: widget.pattern.paletteId,
  );

  Future<void> _resetParameters() async {
    final taskId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          imageBytes: widget.pattern.sourceBytes,
          sourceName: widget.pattern.sourceName ?? widget.pattern.title,
          overwriteProjectId: widget.pattern.id,
          initialOptions: _currentOptions(),
        ),
      ),
    );
    if (taskId != null && mounted) {
      AppNoticeCenter.instance.showSnackBar(
        const SnackBar(content: Text('新参数已加入处理中心')),
      );
    }
  }

  Future<void> _generateVariant() async {
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.auto_awesome_motion_rounded),
        title: const Text('生成不同方案'),
        content: const Text('请选择保留原作品并新增方案，还是用新方案覆盖当前作品。覆盖前的原作品会自动放入回收站。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'new'),
            child: const Text('保留原图并新增'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'overwrite'),
            child: const Text('覆盖当前作品'),
          ),
        ],
      ),
    );
    if (decision == null || !mounted) return;
    final previousPreview = await _exporter.renderPreview(widget.pattern);
    final task = await ProcessingCenter.instance.enqueue(
      imageBytes: widget.pattern.sourceBytes,
      originalImageBytes: widget.pattern.sourceBytes,
      comparisonImageBytes: previousPreview,
      sourceName: widget.pattern.sourceName ?? widget.pattern.title,
      replaceProjectId: decision == 'overwrite' ? widget.pattern.id : null,
      options: _currentOptions(
        variantSeed: DateTime.now().microsecondsSinceEpoch,
      ),
    );
    if (!mounted) return;
    AppNoticeCenter.instance.showSnackBar(
      SnackBar(
        content: Text(
          '不同方案已加入处理中心（任务 ${task.id.substring(math.max(0, task.id.length - 6))}）',
        ),
      ),
    );
  }

  Future<void> _customModify() async {
    await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CustomBoardScreen(initialPattern: widget.pattern),
      ),
    );
  }

  Future<void> _aiRepair() async {
    if (_aiRepairing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.auto_fix_high_rounded),
        title: const Text('用 AI 修复模糊画面？'),
        content: const Text(
          '这会调用当前图片模型，在不改变主体、构图和色彩关系的前提下提高清晰度，再沿用原作品的画板、色库、颜色数和模板生成一个新作品。原作品不会被覆盖。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始修复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _aiRepairing = true);
    try {
      final previousPreview = await _exporter.renderPreview(widget.pattern);
      final result = await AiDesignService.instance.generateImage(
        imageBytes: widget.pattern.sourceBytes,
        prompt:
            '修复参考图中的模糊、压缩噪点、锯齿和不清晰边缘，提高主体细节和像素边界的清晰度。'
            '必须保持原画布比例、主体身份、主体位置、构图、颜色关系、背景和全部已有元素，不添加或删除内容，'
            '不要改变为另一幅画，输出适合再次生成拼豆编号图的清晰原图。',
      );
      final task = await ProcessingCenter.instance.enqueue(
        imageBytes: result.bytes,
        originalImageBytes: result.bytes,
        comparisonImageBytes: previousPreview,
        sourceName:
            '${widget.pattern.sourceName ?? widget.pattern.title}_AI修复.png',
        options: _currentOptions(),
      );
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(
          content: Text(
            'AI 修复图已按原参数加入处理中心（任务 ${task.id.substring(math.max(0, task.id.length - 6))}）',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('AI 修复失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _aiRepairing = false);
    }
  }

  Future<void> _export(bool pdf) async {
    setState(() => _exporting = true);
    try {
      if (pdf) {
        await _exporter.sharePdf(widget.pattern);
      } else {
        await _exporter.sharePreview(widget.pattern);
      }
    } on Object catch (error) {
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('导出失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCodeGrid() async {
    setState(() => _exporting = true);
    try {
      await _exporter.shareCodeGrid(widget.pattern);
    } on Object catch (error) {
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('导出失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _chooseShare() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                '选择分享方式',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.grid_on_rounded),
              title: const Text('分享带颜色编号 PNG'),
              subtitle: const Text('每个豆子格显示实际品牌色号'),
              onTap: () => Navigator.pop(context, 'codes'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('分享效果图 PNG'),
              onTap: () => Navigator.pop(context, 'preview'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('分享单页完整 PDF'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
          ],
        ),
      ),
    );
    if (type == 'codes') await _exportCodeGrid();
    if (type == 'preview') await _export(false);
    if (type == 'pdf') await _export(true);
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名作品'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '作品名称',
            prefixIcon: Icon(Icons.edit_outlined),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('保存名称'),
          ),
        ],
      ),
    );
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 350),
        controller.dispose,
      ),
    );
    if (title == null || title == _title) return;
    try {
      await _projects.rename(widget.pattern.id, title);
      widget.pattern.title = title;
      if (mounted) setState(() => _title = title);
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('重命名失败：$error')),
      );
    }
  }

  Future<void> _chooseLocalSave() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .82,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              const ListTile(
                title: Text(
                  '选择保存方式',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text('图片会保存到“图片/拼豆AI”'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: const Text('保存原图'),
                subtitle: const Text('保存生成像素图时使用的原始图片'),
                onTap: () => Navigator.pop(context, 'original'),
              ),
              ListTile(
                leading: const Icon(Icons.crop_square_rounded),
                title: const Text('保存预览图'),
                subtitle: const Text('方形像素色块，不显示格子和编号'),
                onTap: () => Navigator.pop(context, 'pixelPreview'),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('保存效果预览图'),
                subtitle: const Text('圆形拼豆效果，不显示编号'),
                onTap: () => Navigator.pop(context, 'effectPreview'),
              ),
              ListTile(
                leading: const Icon(Icons.grid_on_rounded),
                title: const Text('保存带格子编号的图片'),
                subtitle: Text(
                  '每一格包含 ${BeadPalettes.byId(widget.pattern.paletteId).shortName} 色号',
                ),
                onTap: () => Navigator.pop(context, 'grid'),
              ),
            ],
          ),
        ),
      ),
    );
    if (type == null || !mounted) return;
    setState(() => _saving = true);
    try {
      switch (type) {
        case 'original':
          await _exporter.saveOriginal(widget.pattern);
        case 'pixelPreview':
          await _exporter.savePixelPreview(widget.pattern);
        case 'effectPreview':
          await _exporter.savePreview(widget.pattern);
        case 'grid':
          await _exporter.saveCodeGrid(widget.pattern);
      }
      if (!mounted) return;
      final savedLabel = switch (type) {
        'original' => '原图',
        'pixelPreview' => '预览图',
        'effectPreview' => '效果预览图',
        _ => '编号格子图',
      };
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('$savedLabel已保存到“图片/拼豆AI”')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _handleMenu(String value) {
    switch (value) {
      case 'rename':
        unawaited(_rename());
        return;
      case 'save':
        unawaited(_chooseLocalSave());
        return;
      case 'sharePreview':
        unawaited(_export(false));
        return;
      case 'shareGrid':
        unawaited(_exportCodeGrid());
        return;
      case 'pdf':
        unawaited(_export(true));
        return;
      case 'flipHorizontal':
        unawaited(_flip(horizontal: true));
        return;
      case 'flipVertical':
        unawaited(_flip(horizontal: false));
        return;
      case 'removeWhite':
        unawaited(_removeWhiteBackground());
        return;
    }
  }

  Future<void> _flip({required bool horizontal}) async {
    final source = List<int>.from(widget.pattern.cells);
    final transformed = List<int>.filled(source.length, -1);
    for (var y = 0; y < widget.pattern.height; y++) {
      for (var x = 0; x < widget.pattern.width; x++) {
        final targetX = horizontal ? widget.pattern.width - 1 - x : x;
        final targetY = horizontal ? y : widget.pattern.height - 1 - y;
        transformed[targetY * widget.pattern.width + targetX] =
            source[y * widget.pattern.width + x];
      }
    }
    widget.pattern.cells
      ..clear()
      ..addAll(transformed);
    await _projects.save(widget.pattern);
    if (!mounted) return;
    setState(() {});
    AppNoticeCenter.instance.showSnackBar(
      SnackBar(content: Text(horizontal ? '已完成左右镜像' : '已完成上下反转')),
    );
  }

  Future<void> _removeWhiteBackground() async {
    var removed = 0;
    for (var i = 0; i < widget.pattern.cells.length; i++) {
      final index = widget.pattern.cells[i];
      if (index < 0 || index >= widget.pattern.colors.length) continue;
      final color = widget.pattern.colors[index];
      final argb = color.color.toARGB32();
      if (color.color.computeLuminance() > 0.9 &&
          ((argb >> 16) & 0xFF) > 220 &&
          ((argb >> 8) & 0xFF) > 220 &&
          (argb & 0xFF) > 220) {
        widget.pattern.cells[i] = -1;
        removed++;
      }
    }
    await _projects.save(widget.pattern);
    if (!mounted) return;
    setState(() {});
    AppNoticeCenter.instance.showSnackBar(
      SnackBar(
        content: Text(removed == 0 ? '未发现可去除的白底' : '已去除 $removed 个白色背景豆位'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: PopScope(
        onPopInvokedWithResult: (didPop, result) {},
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                Text(
                  '${BeadPalettes.byId(widget.pattern.paletteId).specification} · 点击菜单可重命名',
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: _toggleFavorite,
                tooltip: _favorite ? '取消收藏' : '收藏作品',
                color: _favorite ? const Color(0xFFE85584) : AppColors.ink,
                icon: Icon(
                  _favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_exporting && !_saving,
                tooltip: '作品操作',
                onSelected: _handleMenu,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('重命名作品'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'save',
                    child: ListTile(
                      leading: Icon(Icons.download_outlined),
                      title: Text('保存图片到本地'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'shareGrid',
                    child: ListTile(
                      leading: Icon(Icons.grid_on_rounded),
                      title: Text('分享带颜色编号 PNG'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'sharePreview',
                    child: ListTile(
                      leading: Icon(Icons.image_outlined),
                      title: Text('分享效果图 PNG'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'pdf',
                    child: ListTile(
                      leading: Icon(Icons.picture_as_pdf_outlined),
                      title: Text('导出单页完整 PDF'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'flipHorizontal',
                    child: ListTile(
                      leading: Icon(Icons.flip_rounded),
                      title: Text('左右镜像'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'flipVertical',
                    child: ListTile(
                      leading: Icon(Icons.flip_camera_android_outlined),
                      title: Text('上下反转'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'removeWhite',
                    child: ListTile(
                      leading: Icon(Icons.auto_fix_normal_rounded),
                      title: Text('去除白底'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                icon: _exporting || _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_rounded),
              ),
              const SizedBox(width: 7),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              tabs: [
                Tab(text: '效果预览'),
                Tab(text: '编号格子'),
                Tab(text: '颜色统计'),
                Tab(text: '购买清单'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _PreviewTab(
                pattern: widget.pattern,
                onExport: _chooseShare,
                onSave: _chooseLocalSave,
                onReset: _resetParameters,
                onVariant: _generateVariant,
                onModify: _customModify,
                onAiRepair: _aiRepair,
                aiRepairing: _aiRepairing,
              ),
              _CodeGridTab(pattern: widget.pattern),
              _StatisticsTab(pattern: widget.pattern),
              _PurchaseTab(
                pattern: widget.pattern,
                onExport: () => _export(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewTab extends StatelessWidget {
  const _PreviewTab({
    required this.pattern,
    required this.onExport,
    required this.onSave,
    required this.onReset,
    required this.onVariant,
    required this.onModify,
    required this.onAiRepair,
    required this.aiRepairing,
  });
  final BeadPattern pattern;
  final VoidCallback onExport;
  final VoidCallback onSave;
  final VoidCallback onReset;
  final VoidCallback onVariant;
  final VoidCallback onModify;
  final VoidCallback onAiRepair;
  final bool aiRepairing;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
    children: [
      _ComparisonHeader(
        index: '01',
        title: pattern.variantSeed == 0 ? '生成效果预览' : '刷新后方案',
        badge: pattern.backgroundRemoved ? 'AI 已抠图' : null,
      ),
      const SizedBox(height: 10),
      GestureDetector(
        onDoubleTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _FullscreenCodeGrid(pattern: pattern),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.line),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BeadPatternView(
              pattern: pattern,
              showCodes: true,
              padding: 13,
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),
      _ComparisonHeader(
        index: '02',
        title: pattern.variantSeed == 0 ? '原图' : '刷新前方案',
      ),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.memory(
            pattern.referenceBytes ?? pattern.sourceBytes,
            width: double.infinity,
            fit: BoxFit.contain,
            cacheWidth: 2000,
            filterQuality: pattern.sourceName?.startsWith('文字拼豆_') == true
                ? FilterQuality.none
                : FilterQuality.high,
            errorBuilder: (_, _, _) => const SizedBox(
              height: 180,
              child: Center(child: Icon(Icons.broken_image_outlined, size: 42)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 15),
      Row(
        children: [
          Expanded(
            child: _MetricCard(
              value: '${pattern.width}×${pattern.height}',
              label: '画板尺寸',
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _MetricCard(
              value: '${pattern.colors.length}',
              label: '实际颜色',
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _MetricCard(value: '${pattern.totalBeads}', label: '豆子总数'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.mint,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.straighten_rounded, color: AppColors.teal),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '制作本图至少预留 ${pattern.minimumBoardSize} 的连续画板区域',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.teal,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('saveResultToLocalButton'),
              onPressed: onSave,
              icon: const Icon(Icons.download_outlined),
              label: const Text('保存到本地'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.image_outlined),
              label: const Text('分享图纸'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('重新设置参数'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: onVariant,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新不同方案'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onModify,
          icon: const Icon(Icons.colorize_rounded),
          label: Text(
            pattern.isCustomBoard ? '继续编辑，可保存为新作品或覆盖当前' : '自定义修改颜色并保存',
          ),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: aiRepairing ? null : onAiRepair,
          icon: aiRepairing
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_fix_high_rounded),
          label: Text(aiRepairing ? 'AI 正在修复画面…' : 'AI 修复模糊画面并按原参数重制'),
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        '显示色基于屏幕与工程预置值，实体豆颜色会受批次、光源与屏幕校准影响。',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, color: AppColors.muted),
      ),
    ],
  );
}

class _ComparisonHeader extends StatelessWidget {
  const _ComparisonHeader({
    required this.index,
    required this.title,
    this.badge,
  });

  final String index;
  final String title;
  final String? badge;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.coral,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          index,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 11,
          ),
        ),
      ),
      const SizedBox(width: 9),
      Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      ),
      const Spacer(),
      if (badge != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.mint,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            badge!,
            style: const TextStyle(
              color: AppColors.teal,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
    ],
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 7),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _CodeGridTab extends StatefulWidget {
  const _CodeGridTab({required this.pattern});
  final BeadPattern pattern;

  @override
  State<_CodeGridTab> createState() => _CodeGridTabState();
}

class _CodeGridTabState extends State<_CodeGridTab> {
  final _exporter = ExportService();
  var _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _exporter.saveCodeGrid(widget.pattern);
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        const SnackBar(content: Text('编号格子图已保存到“图片/拼豆AI”')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
    child: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.mint,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Row(
            children: [
              Icon(Icons.pinch_rounded, size: 18, color: AppColors.teal),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  '双指缩放、拖动画布查看每一格色号',
                  style: TextStyle(
                    color: AppColors.teal,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (widget.pattern.template != PatternTemplate.none) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0EA),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: AppColors.coralDark,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '导出时使用“${widget.pattern.template.label}”模板，包含标题、坐标和用量清单',
                    style: const TextStyle(
                      color: AppColors.coralDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.mint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '本图最少需要 ${widget.pattern.minimumBoardSize} 的连续格子区域',
            style: const TextStyle(
              color: AppColors.teal,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) =>
                        _FullscreenCodeGrid(pattern: widget.pattern),
                  ),
                ),
                icon: const Icon(Icons.fullscreen_rounded),
                label: const Text('全屏预览'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(_saving ? '正在生成…' : '保存到本地'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: BeadPatternView(
            pattern: widget.pattern,
            showCodes: true,
            interactive: true,
            padding: 0,
          ),
        ),
      ],
    ),
  );
}

class _FullscreenCodeGrid extends StatelessWidget {
  const _FullscreenCodeGrid({required this.pattern});

  final BeadPattern pattern;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF171515),
    appBar: AppBar(
      backgroundColor: const Color(0xFF171515),
      foregroundColor: Colors.white,
      title: const Text(
        '编号格子 · 全屏预览',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close),
        tooltip: '关闭全屏',
      ),
    ),
    body: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: BeadPatternView(
          pattern: pattern,
          showCodes: true,
          interactive: true,
          padding: 0,
        ),
      ),
    ),
  );
}

class _StatisticsTab extends StatelessWidget {
  const _StatisticsTab({required this.pattern});
  final BeadPattern pattern;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
    itemCount: pattern.sortedCounts.length + 1,
    separatorBuilder: (_, index) =>
        index == 0 ? const SizedBox(height: 14) : const SizedBox(height: 8),
    itemBuilder: (context, index) {
      if (index == 0) {
        return _SummaryBanner(pattern: pattern);
      }
      final entry = pattern.sortedCounts[index - 1];
      final color = pattern.colors[entry.key];
      final percentage = entry.value / pattern.totalBeads;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _BeadSwatch(color: color.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          color.code,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            color.nameCn,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: percentage,
                        minHeight: 5,
                        color: color.color,
                        backgroundColor: AppColors.line,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${entry.value} 颗',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${(percentage * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.pattern});
  final BeadPattern pattern;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.teal, Color(0xFF44A596)],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        const Icon(Icons.donut_large_rounded, color: Colors.white, size: 36),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${pattern.colors.length} 种颜色',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const Text(
                '用量已按色号从高到低排列',
                style: TextStyle(color: Color(0xFFD9F4EF), fontSize: 11),
              ),
            ],
          ),
        ),
        Text(
          '${pattern.totalBeads}\n颗',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
      ],
    ),
  );
}

class _PurchaseTab extends StatelessWidget {
  const _PurchaseTab({required this.pattern, required this.onExport});
  final BeadPattern pattern;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pattern.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              _KeyValue(
                label: '品牌规格',
                value: BeadPalettes.byId(pattern.paletteId).specification,
              ),
              _KeyValue(
                label: '画板尺寸',
                value: '${pattern.width} × ${pattern.height}',
              ),
              _KeyValue(label: '最少预留格子', value: pattern.minimumBoardSize),
              _KeyValue(label: '豆子总量', value: '${pattern.totalBeads} 颗'),
              _KeyValue(
                label: '建议余量',
                value: '${(pattern.totalBeads * 1.08).ceil()} 颗（含 8% 备用）',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Padding(
        padding: EdgeInsets.only(left: 2, bottom: 9),
        child: Text(
          '按色号采购',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
      ),
      Card(
        child: Column(
          children: [
            for (
              var index = 0;
              index < pattern.sortedCounts.length;
              index++
            ) ...[
              Builder(
                builder: (context) {
                  final entry = pattern.sortedCounts[index];
                  final color = pattern.colors[entry.key];
                  return ListTile(
                    leading: _BeadSwatch(color: color.color, size: 36),
                    title: Text(
                      '${color.code} · ${color.nameCn}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(color.hex),
                    trailing: Text(
                      '${(entry.value * 1.08).ceil()} 颗',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.coral,
                      ),
                    ),
                  );
                },
              ),
              if (index < pattern.sortedCounts.length - 1)
                const Divider(height: 1, indent: 66),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: onExport,
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('导出单页完整 PDF 图纸'),
      ),
      const SizedBox(height: 8),
      const Text(
        '清单数量已自动增加 8% 损耗备用量。',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, color: AppColors.muted),
      ),
    ],
  );
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _BeadSwatch extends StatelessWidget {
  const _BeadSwatch({required this.color, this.size = 44});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.black12),
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 6),
      ],
    ),
    child: Center(
      child: Container(
        width: size * 0.27,
        height: size * 0.27,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
}
