import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_strings.dart';
import '../services/collection_library.dart';
import '../services/export_service.dart';
import '../services/app_notice_center.dart';
import '../theme/app_theme.dart';
import 'ai_design_screen.dart';
import 'editor_screen.dart';
import 'embedded_browser_screen.dart';

class PatternCollectionScreen extends StatefulWidget {
  const PatternCollectionScreen({super.key});

  @override
  State<PatternCollectionScreen> createState() =>
      _PatternCollectionScreenState();
}

class _PatternCollectionScreenState extends State<PatternCollectionScreen> {
  final _library = CollectionLibrary.instance;
  final _searchController = TextEditingController();
  String? _selectedCategory;
  var _query = '';
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _library.initialize();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _showCategorySortActions(String name) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text('选择这个分类的排序位置'),
            ),
            ListTile(
              leading: const Icon(Icons.vertical_align_top_rounded),
              title: const Text('一键排到最前'),
              onTap: () => Navigator.pop(context, 'front'),
            ),
            ListTile(
              leading: const Icon(Icons.vertical_align_bottom_rounded),
              title: const Text('一键排到最后'),
              onTap: () => Navigator.pop(context, 'back'),
            ),
          ],
        ),
      ),
    );
    if (action == 'front') await _library.moveCategoryToFront(name);
    if (action == 'back') await _library.moveCategoryToBack(name);
  }

  Future<void> _resetCollection() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restart_alt_rounded),
        title: const Text('恢复默认拼豆图合集？'),
        content: const Text(
          '内置图纸会恢复原名称和完整列表，收藏、排序、合集地址记录及自己上传的图纸会被清除。上传图纸删除后无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认一键重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await _library.resetToDefaults();
      if (!mounted) return;
      setState(() {
        _selectedCategory = null;
        _query = '';
        _searchController.clear();
      });
      AppNoticeCenter.instance.show(
        '拼豆图合集已恢复为软件初始状态',
        kind: AppNoticeKind.success,
      );
    } on Object catch (error) {
      AppNoticeCenter.instance.showError(error, operation: '重置拼豆图合集');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _library,
    builder: (context, _) {
      final allItems = _library.items;
      final categories = _library.categoryOrder;
      final items = allItems
          .where(
            (item) =>
                _selectedCategory == null || item.category == _selectedCategory,
          )
          .where(
            (item) =>
                _query.isEmpty ||
                item.name.toLowerCase().contains(_query.toLowerCase()),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: Text(
            AppStrings.ui(context, '拼豆图合集'),
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            TextButton.icon(
              key: const ValueKey('resetPatternCollectionButton'),
              onPressed: _loading ? null : _resetCollection,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('一键重置'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const CollectionManagementScreen(),
                ),
              ),
              icon: const Icon(Icons.tune_rounded),
              label: Text(AppStrings.ui(context, '管理')),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 14, right: 7),
                          child: ChoiceChip(
                            label: Text(
                              '${AppStrings.ui(context, '全部')} ${allItems.length}',
                            ),
                            selected: _selectedCategory == null,
                            onSelected: (_) =>
                                setState(() => _selectedCategory = null),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(
                              right: 14,
                              top: 5,
                              bottom: 5,
                            ),
                            scrollDirection: Axis.horizontal,
                            itemCount: categories.length,
                            itemBuilder: (context, index) {
                              final name = categories[index];
                              return Padding(
                                key: ValueKey('collectionCategory_$name'),
                                padding: const EdgeInsets.only(right: 7),
                                child: GestureDetector(
                                  onLongPress: () =>
                                      _showCategorySortActions(name),
                                  child: Semantics(
                                    button: true,
                                    hint: '长按分类可排到最前或最后',
                                    onLongPress: () =>
                                        _showCategorySortActions(name),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surface,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: ChoiceChip(
                                        label: Text(name),
                                        selected: _selectedCategory == name,
                                        onSelected: (_) => setState(
                                          () => _selectedCategory = name,
                                        ),
                                      ),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: AppStrings.ui(context, '按原文件名搜索'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Text(AppStrings.ui(context, '没有符合条件的拼豆图')),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 190,
                                  crossAxisSpacing: 9,
                                  mainAxisSpacing: 9,
                                  childAspectRatio: 0.82,
                                ),
                            itemCount: items.length,
                            itemBuilder: (context, index) =>
                                CollectionPatternCard(item: items[index]),
                          ),
                  ),
                ],
              ),
      );
    },
  );
}

class CollectionPatternCard extends StatelessWidget {
  const CollectionPatternCard({super.key, required this.item});

  final CollectionPatternItem item;

  Future<void> _saveToLocal(BuildContext context) async {
    await saveCollectionPatternToLocal(context, item);
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: item.name);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          item.isUserUpload ? '重命名上传图纸' : AppStrings.ui(context, '重命名内置图纸'),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: AppStrings.ui(context, '显示名称'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.ui(context, '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(AppStrings.ui(context, '保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.isNotEmpty) {
      if (item.isUserUpload) {
        await CollectionLibrary.instance.updateUpload(
          item,
          name: value,
          category: item.category,
        );
      } else {
        await CollectionLibrary.instance.renameBuiltIn(item, value);
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.isUserUpload ? '删除上传图纸？' : '从合集隐藏内置图纸？'),
        content: Text(
          item.isUserUpload
              ? '“${item.name}”及本机文件将永久删除。'
              : '“${item.name}”将从合集中隐藏，可随时使用顶部“一键重置”恢复。',
        ),
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
    if (confirmed == true) {
      await CollectionLibrary.instance.deleteItem(item);
    }
  }

  Future<void> _manage(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text('选择要执行的操作'),
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('保存到本地'),
              onTap: () => Navigator.pop(context, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('重命名'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(item.isUserUpload ? '永久删除' : '从合集删除（可重置恢复）'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'save') {
      await _saveToLocal(context);
      return;
    }
    if (action == 'rename') {
      await _rename(context);
      return;
    }
    if (action == 'delete' && context.mounted) await _delete(context);
  }

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CollectionPatternDetail(itemId: item.id),
        ),
      ),
      onLongPress: () => _manage(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _CollectionImage(item: item, fit: BoxFit.cover),
                Positioned(
                  top: 4,
                  left: 4,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _saveToLocal(context),
                    tooltip: '保存到本地',
                    icon: const Icon(Icons.download_rounded),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        CollectionLibrary.instance.toggleFavorite(item),
                    tooltip: AppStrings.ui(
                      context,
                      item.isFavorite ? '取消收藏' : '收藏到我的收藏',
                    ),
                    icon: Icon(
                      item.isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: item.isFavorite ? const Color(0xFFE85584) : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  item.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<bool> saveCollectionPatternToLocal(
  BuildContext context,
  CollectionPatternItem item,
) async {
  try {
    Uint8List bytes;
    var isOriginal = true;
    try {
      bytes = await CollectionLibrary.instance.readOriginal(item);
    } on Object {
      bytes = await CollectionLibrary.instance.readPreview(item);
      isOriginal = false;
    }
    final requestedName = isOriginal
        ? item.name
        : '${item.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}_内置预览.jpg';
    final path = await ExportService().saveImageBytes(bytes, requestedName);
    if (!context.mounted) return true;
    AppNoticeCenter.instance.showSnackBar(
      SnackBar(
        content: Text(
          isOriginal
              ? '“${item.name}”已保存到本地：$path'
              : '原图库未连接，已将“${item.name}”的内置清晰预览保存到本地',
        ),
      ),
    );
    return true;
  } on Object catch (error) {
    if (context.mounted) {
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('保存“${item.name}”失败：$error')),
      );
    }
    return false;
  }
}

class CollectionPatternDetail extends StatefulWidget {
  const CollectionPatternDetail({super.key, required this.itemId});

  final String itemId;

  @override
  State<CollectionPatternDetail> createState() =>
      _CollectionPatternDetailState();
}

class _CollectionPatternDetailState extends State<CollectionPatternDetail> {
  final _library = CollectionLibrary.instance;
  var _busy = false;
  var _originalLoading = false;
  Uint8List? _originalBytes;
  Object? _originalError;

  @override
  void initState() {
    super.initState();
    _loadOriginalPreview();
  }

  CollectionPatternItem? get _item {
    for (final item in _library.items) {
      if (item.id == widget.itemId) return item;
    }
    return null;
  }

  Future<Uint8List> _loadOriginal({bool force = false}) async {
    final cached = _originalBytes;
    if (cached != null && !force) return cached;
    final item = _item;
    if (item == null) throw StateError('这张拼豆图已被删除');
    final bytes = await _library.readOriginal(item);
    if (mounted) {
      setState(() {
        _originalBytes = bytes;
        _originalError = null;
      });
    }
    return bytes;
  }

  Future<void> _loadOriginalPreview({bool force = false}) async {
    if (_originalLoading) return;
    setState(() {
      _originalLoading = true;
      _originalError = null;
    });
    try {
      await _loadOriginal(force: force);
    } on Object catch (error) {
      if (mounted) setState(() => _originalError = error);
    } finally {
      if (mounted) setState(() => _originalLoading = false);
    }
  }

  Future<T?> _run<T>(
    Future<T> Function(CollectionPatternItem item) action,
  ) async {
    final item = _item;
    if (item == null || _busy) return null;
    setState(() => _busy = true);
    try {
      return await action(item);
    } on Object catch (error) {
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('${AppStrings.ui(context, '操作失败')}：$error')),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    await _run((item) async {
      final available = await _readBestAvailable(item);
      final name = available.isOriginal
          ? item.name
          : '${item.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}_内置预览.jpg';
      await ExportService().saveImageBytes(available.bytes, name);
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(
            content: Text(
              available.isOriginal
                  ? AppStrings.ui(context, '原图已按原文件名保存到“图片/拼豆AI”')
                  : AppStrings.ui(context, '原图库未连接，已保存内置清晰预览；配置合集地址后可下载原图'),
            ),
          ),
        );
      }
    });
  }

  Future<void> _share() async {
    await _run((item) async {
      final available = await _readBestAvailable(item);
      final directory = await getTemporaryDirectory();
      final requestedName = available.isOriginal
          ? item.name
          : '${item.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}_内置预览.jpg';
      final safeName = requestedName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${directory.path}${Platform.pathSeparator}$safeName');
      await file.writeAsBytes(available.bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: item.name),
      );
      if (mounted && !available.isOriginal) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text(AppStrings.ui(context, '原图库未连接，已分享内置清晰预览'))),
        );
      }
    });
  }

  Future<void> _editColors() async {
    await _run((item) async {
      final available = await _readBestAvailable(item);
      if (!available.isOriginal && mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.ui(context, '原图库暂时不可用，已使用内置预览图继续转换；下载原图仍需先配置可用的合集地址。'),
            ),
          ),
        );
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              EditorScreen(imageBytes: available.bytes, sourceName: item.name),
        ),
      );
    });
  }

  Future<void> _aiReplicate() async {
    await _run((item) async {
      final available = await _readBestAvailable(item);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AiDesignScreen(
            initialImage: available.bytes,
            replicationMode: true,
            initialRequest: '保持原图内容不变，并允许我继续说明要修改的颜色、细节或背景。',
          ),
        ),
      );
    });
  }

  Future<({Uint8List bytes, bool isOriginal})> _readBestAvailable(
    CollectionPatternItem item,
  ) async {
    try {
      return (bytes: await _loadOriginal(), isOriginal: true);
    } on Object {
      final preview = await _library.readPreview(item);
      if (mounted) {
        setState(
          () => _originalError = StateError(
            AppStrings.ui(context, '原图库未连接，正在使用内置预览'),
          ),
        );
      }
      return (bytes: preview, isOriginal: false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _library,
    builder: (context, _) {
      final item = _item;
      if (item == null) {
        return Scaffold(
          appBar: AppBar(title: Text(AppStrings.ui(context, '拼豆图'))),
          body: Center(child: Text(AppStrings.ui(context, '这张拼豆图已被删除'))),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              onPressed: () => _library.toggleFavorite(item),
              tooltip: AppStrings.ui(
                context,
                item.isFavorite ? '取消收藏' : '收藏到我的收藏',
              ),
              icon: Icon(
                item.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
            ),
            IconButton(
              onPressed: _busy ? null : _share,
              tooltip: AppStrings.ui(context, '一键分享'),
              icon: const Icon(Icons.share_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Container(
                color: const Color(0xFF202020),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 12,
                      child: Center(
                        child: _originalBytes == null
                            ? _CollectionImage(item: item, fit: BoxFit.contain)
                            : Image.memory(
                                _originalBytes!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.high,
                              ),
                      ),
                    ),
                    if (_originalLoading)
                      const Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: LinearProgressIndicator(),
                      ),
                    if (_originalError != null && !_originalLoading)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Card(
                          color: Colors.black87,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    AppStrings.ui(
                                      context,
                                      '当前显示内置预览。配置可用合集地址后可在软件内查看和缩放原图。',
                                    ),
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _loadOriginalPreview(force: true),
                                  child: Text(AppStrings.ui(context, '重试')),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${item.width} × ${item.height} · ${item.category} · 原格式 ${item.extension} · ${(item.bytes / 1024 / 1024).toStringAsFixed(1)}MB',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _download,
                            icon: const Icon(Icons.download_rounded),
                            label: Text(AppStrings.ui(context, '下载原图')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _editColors,
                            icon: const Icon(Icons.palette_outlined),
                            label: Text(AppStrings.ui(context, '编辑颜色')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _aiReplicate,
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: const Text('AI 一比一复刻并修改'),
                      ),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class CollectionManagementScreen extends StatefulWidget {
  const CollectionManagementScreen({super.key});

  @override
  State<CollectionManagementScreen> createState() =>
      _CollectionManagementScreenState();
}

enum _CollectionViewMode {
  extraLarge('超大图标'),
  large('大图标'),
  medium('中图标'),
  small('小图标'),
  list('列表'),
  details('详细信息'),
  tiles('平铺'),
  content('内容');

  const _CollectionViewMode(this.label);
  final String label;
}

class _CollectionManagementScreenState
    extends State<CollectionManagementScreen> {
  final _library = CollectionLibrary.instance;
  var _category = '我的上传';
  String? _filterCategory;
  var _importing = false;
  var _viewMode = _CollectionViewMode.list;

  Future<void> _addSourceAddress() async {
    final controller = TextEditingController();
    String? errorText;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.ui(context, '添加自己的合集地址')),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: AppStrings.ui(context, '原图库服务或静态目录地址'),
              hintText: '例如 https://example.com/v1',
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.ui(context, '取消')),
            ),
            FilledButton(
              onPressed: () async {
                final address = controller.text.trim();
                try {
                  await _library.addSourceAddress(address, activate: false);
                  if (context.mounted) Navigator.pop(context, address);
                } on Object catch (error) {
                  setDialogState(() => errorText = error.toString());
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value != null && mounted) {
      AppNoticeCenter.instance.showSnackBar(
        const SnackBar(content: Text('合集地址已添加')),
      );
    }
  }

  Future<void> _openSourceAddress(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      AppNoticeCenter.instance.show(
        '这条内容不是可打开的 HTTP/HTTPS 网页链接。',
        kind: AppNoticeKind.warning,
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EmbeddedBrowserScreen(initialUrl: uri.toString()),
      ),
    );
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.ui(context, '新增图纸分类')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: InputDecoration(
            labelText: AppStrings.ui(context, '分类名称'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.ui(context, '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(AppStrings.ui(context, '新增')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    await _library.addCategory(value);
    if (mounted) setState(() => _category = value);
  }

  Future<void> _upload() async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '图片',
          extensions: [
            'jpg',
            'jpeg',
            'png',
            'webp',
            'gif',
            'bmp',
            'tif',
            'tiff',
          ],
          mimeTypes: ['image/*'],
          webWildCards: ['image/*'],
        ),
      ],
      confirmButtonText: '上传自己的拼豆图',
    );
    if (files.isEmpty || !mounted) return;
    setState(() => _importing = true);
    final count = await _library.importFiles(files, category: _category);
    if (!mounted) return;
    setState(() => _importing = false);
    AppNoticeCenter.instance.showSnackBar(
      SnackBar(
        content: Text(
          '已上传 $count 张拼豆图${count < files.length ? '，不支持的图片已跳过' : ''}',
        ),
      ),
    );
  }

  Future<void> _edit(CollectionPatternItem item) async {
    final controller = TextEditingController(text: item.name);
    var category = item.category;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('修改上传的拼豆图'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLength: 80,
                decoration: const InputDecoration(labelText: '图片名称'),
              ),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: '所属分类'),
                items: [
                  for (final value in _library.userCategories)
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: (value) =>
                    setDialogState(() => category = value ?? category),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存修改'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await _library.updateUpload(
        item,
        name: controller.text,
        category: category,
      );
    }
    controller.dispose();
  }

  Future<void> _delete(CollectionPatternItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除上传的拼豆图？'),
        content: Text('“${item.name}”将从本机图纸库永久删除。'),
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
    if (confirmed == true) await _library.deleteUpload(item);
  }

  Future<void> _manageCategory(String category) async {
    final controller = TextEditingController(text: category);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('管理分类：$category'),
        content: TextField(
          controller: controller,
          maxLength: 30,
          decoration: const InputDecoration(labelText: '分类名称'),
        ),
        actions: [
          if (category != '我的上传')
            TextButton(
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text('删除空分类'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'rename'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    try {
      if (action == 'rename') {
        await _library.renameCategory(category, controller.text);
        if (_category == category && mounted) {
          setState(() => _category = controller.text.trim());
        }
      } else if (action == 'delete') {
        await _library.deleteCategory(category);
        if (_filterCategory == category && mounted) {
          setState(() => _filterCategory = null);
        }
      }
    } on Object catch (error) {
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('分类操作失败：$error')),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _moveItem(
    List<CollectionPatternItem> items,
    int from,
    int to,
  ) async {
    if (from < 0 || from >= items.length || to < 0 || to >= items.length) {
      return;
    }
    final ids = items.map((item) => item.id).toList();
    final id = ids.removeAt(from);
    ids.insert(to, id);
    await _library.reorderUploads(ids);
  }

  Widget _itemMenu(CollectionPatternItem item, int index, int count) =>
      PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'pin') _library.togglePin(item);
          if (value == 'edit') _edit(item);
          if (value == 'favorite') _library.toggleFavorite(item);
          if (value == 'up') _moveItem(_visibleUploads(), index, index - 1);
          if (value == 'down') _moveItem(_visibleUploads(), index, index + 1);
          if (value == 'delete') _delete(item);
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'pin',
            child: Text(item.isPinned ? '取消置顶' : '置顶'),
          ),
          const PopupMenuItem(value: 'edit', child: Text('修改名称和分类')),
          PopupMenuItem(
            value: 'favorite',
            child: Text(item.isFavorite ? '取消收藏' : '收藏到我的收藏'),
          ),
          if (index > 0) const PopupMenuItem(value: 'up', child: Text('上移')),
          if (index + 1 < count)
            const PopupMenuItem(value: 'down', child: Text('下移')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      );

  List<CollectionPatternItem> _visibleUploads() {
    final uploads = _library.userUploads;
    return _filterCategory == null
        ? uploads
        : uploads
              .where((item) => item.category == _filterCategory)
              .toList(growable: false);
  }

  Widget _buildUploadView(List<CollectionPatternItem> uploads) {
    if (_viewMode == _CollectionViewMode.list ||
        _viewMode == _CollectionViewMode.details) {
      return ReorderableListView.builder(
        padding: const EdgeInsets.all(14),
        buildDefaultDragHandles: false,
        itemCount: uploads.length,
        onReorder: (oldIndex, newIndex) {
          if (newIndex > oldIndex) newIndex--;
          _moveItem(uploads, oldIndex, newIndex);
        },
        itemBuilder: (context, index) {
          final item = uploads[index];
          return ListTile(
            key: ValueKey(item.id),
            contentPadding: const EdgeInsets.symmetric(vertical: 3),
            leading: SizedBox.square(
              dimension: _viewMode == _CollectionViewMode.details ? 72 : 52,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _CollectionImage(item: item, fit: BoxFit.cover),
              ),
            ),
            title: Row(
              children: [
                if (item.isPinned)
                  const Padding(
                    padding: EdgeInsets.only(right: 5),
                    child: Icon(Icons.push_pin_rounded, size: 16),
                  ),
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              _viewMode == _CollectionViewMode.details
                  ? '${item.category} · ${item.width}×${item.height} · ${item.extension} · ${(item.bytes / 1024).round()}KB'
                  : '${item.category} · ${item.width}×${item.height}',
            ),
            onLongPress: () => _edit(item),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => CollectionPatternDetail(itemId: item.id),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.drag_handle_rounded),
                  ),
                ),
                _itemMenu(item, index, uploads.length),
              ],
            ),
          );
        },
      );
    }

    final maxExtent = switch (_viewMode) {
      _CollectionViewMode.extraLarge => 360.0,
      _CollectionViewMode.large => 270.0,
      _CollectionViewMode.medium => 200.0,
      _CollectionViewMode.small => 135.0,
      _CollectionViewMode.tiles => 230.0,
      _CollectionViewMode.content => 310.0,
      _ => 200.0,
    };
    final aspect = switch (_viewMode) {
      _CollectionViewMode.tiles => 1.15,
      _CollectionViewMode.content => 0.76,
      _CollectionViewMode.small => 0.82,
      _ => 0.88,
    };
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        crossAxisSpacing: 9,
        mainAxisSpacing: 9,
        childAspectRatio: aspect,
      ),
      itemCount: uploads.length,
      itemBuilder: (context, index) {
        final item = uploads[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onLongPress: () => _edit(item),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => CollectionPatternDetail(itemId: item.id),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _CollectionImage(item: item, fit: BoxFit.cover),
                      if (item.isPinned)
                        const Positioned(
                          top: 5,
                          left: 5,
                          child: Icon(Icons.push_pin_rounded),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 2, 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: _viewMode == _CollectionViewMode.content
                              ? 2
                              : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _itemMenu(item, index, uploads.length),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _library,
    builder: (context, _) {
      final categories = _library.userCategories;
      if (!categories.contains(_category)) _category = categories.first;
      final uploads = _visibleUploads();
      return Scaffold(
        appBar: AppBar(
          title: Text(
            AppStrings.ui(context, '图纸管理'),
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            PopupMenuButton<_CollectionViewMode>(
              tooltip: '显示方式',
              initialValue: _viewMode,
              onSelected: (value) => setState(() => _viewMode = value),
              itemBuilder: (_) => [
                for (final mode in _CollectionViewMode.values)
                  PopupMenuItem(value: mode, child: Text(mode.label)),
              ],
              icon: const Icon(Icons.view_module_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _addSourceAddress,
                    icon: const Icon(Icons.add_link_rounded),
                    label: Text(AppStrings.ui(context, '添加自己的合集地址')),
                  ),
                  if (_library.sourceAddresses.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final address in _library.sourceAddresses)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.link_rounded),
                        title: Text(
                          address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: '浏览器打开',
                              onPressed: () => _openSourceAddress(address),
                              icon: const Icon(Icons.open_in_new_rounded),
                            ),
                            IconButton(
                              tooltip: '删除此地址',
                              onPressed: () =>
                                  _library.removeSourceAddress(address),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                        onTap: () => _openSourceAddress(address),
                      ),
                    const Divider(),
                  ],
                  Text(
                    AppStrings.ui(context, '分类管理'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: Text('全部 ${_library.userUploads.length}'),
                          selected: _filterCategory == null,
                          onSelected: (_) =>
                              setState(() => _filterCategory = null),
                        ),
                        for (final value in categories) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onLongPress: () => _manageCategory(value),
                            child: ChoiceChip(
                              label: Text(
                                '$value ${_library.userUploads.where((item) => item.category == value).length}',
                              ),
                              selected: _filterCategory == value,
                              onSelected: (_) =>
                                  setState(() => _filterCategory = value),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '长按分类可重命名或删除空分类。选择分类后只显示该分类图纸。',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _category,
                          decoration: InputDecoration(
                            labelText: AppStrings.ui(context, '上传到分类'),
                            prefixIcon: Icon(Icons.folder_outlined),
                          ),
                          items: [
                            for (final value in categories)
                              DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _category = value ?? _category),
                        ),
                      ),
                      IconButton(
                        onPressed: _addCategory,
                        tooltip: '新增分类',
                        icon: const Icon(Icons.create_new_folder_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _importing ? null : _upload,
                    icon: _importing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_rounded),
                    label: Text(AppStrings.ui(context, '上传自己的拼豆图')),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: uploads.isEmpty
                  ? Center(
                      child: Text(
                        AppStrings.ui(
                          context,
                          _filterCategory == null
                              ? '还没有上传自己的拼豆图'
                              : '这个分类还没有拼豆图',
                        ),
                      ),
                    )
                  : _buildUploadView(uploads),
            ),
          ],
        ),
      );
    },
  );
}

class _CollectionImage extends StatelessWidget {
  const _CollectionImage({required this.item, required this.fit});

  final CollectionPatternItem item;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final Widget image = item.localPath != null
        ? Image.file(
            File(item.localPath!),
            fit: fit,
            filterQuality: FilterQuality.high,
          )
        : Image.asset(item.asset!, fit: fit, filterQuality: FilterQuality.high);
    return image;
  }
}
