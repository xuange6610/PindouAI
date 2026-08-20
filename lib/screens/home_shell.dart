import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, MethodChannel, SystemNavigator;
import 'package:image_picker/image_picker.dart';

import '../data/bead_palettes.dart';
import '../l10n/app_strings.dart';
import '../models/bead_color.dart';
import '../models/bead_palette.dart';
import '../models/bead_pattern.dart';
import '../services/project_repository.dart';
import '../services/processing_center.dart';
import '../services/library_backup_service.dart';
import '../services/pattern_processor.dart';
import '../services/app_settings.dart';
import '../services/collection_library.dart';
import '../services/click_sound_service.dart';
import '../services/device_backup_service.dart';
import '../services/factory_reset_service.dart';
import '../services/app_notice_center.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';
import '../widgets/favorite_category_picker.dart';
import 'editor_screen.dart';
import 'custom_board_screen.dart';
import 'processing_center_screen.dart';
import 'result_screen.dart';
import 'photo_project_screen.dart';
import 'text_bead_screen.dart';
import 'color_recognition_screen.dart';
import 'ai_design_screen.dart';
import 'ai_design_history_screen.dart';
import 'pattern_collection_screen.dart';
import 'local_music_screen.dart';
import 'ai_chat_screen.dart';
import 'api_settings_screen.dart';
import 'software_announcement_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _repository = ProjectRepository();
  final _processingCenter = ProcessingCenter.instance;
  final _picker = ImagePicker();
  final _backup = LibraryBackupService();
  var _selectedIndex = 0;
  var _loading = true;
  var _projects = <ProjectSummary>[];
  var _projectRevision = 0;
  var _taskBadgeCount = 0;
  var _backfillingThumbnails = false;
  var _customBoardHasDraft = false;
  var _exitDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _processingCenter.addListener(_onProcessingCenterChanged);
    unawaited(_processingCenter.initialize());
    _reload();
  }

  @override
  void dispose() {
    _processingCenter.removeListener(_onProcessingCenterChanged);
    super.dispose();
  }

  void _onProcessingCenterChanged() {
    final badge =
        _processingCenter.activeCount + _processingCenter.pendingCount;
    final revisionChanged =
        _projectRevision != _processingCenter.projectRevision;
    if (revisionChanged) {
      _projectRevision = _processingCenter.projectRevision;
      unawaited(_reload());
    }
    if (mounted && badge != _taskBadgeCount) {
      setState(() => _taskBadgeCount = badge);
    }
  }

  Future<void> _reload() async {
    final projects = await _repository.loadSummaries();
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _loading = false;
    });
    if (projects.any((project) => project.thumbnailPath == null)) {
      unawaited(_backfillThumbnails(projects));
    }
  }

  Future<void> _backfillThumbnails(List<ProjectSummary> projects) async {
    if (_backfillingThumbnails) return;
    _backfillingThumbnails = true;
    try {
      final created = await _repository.backfillMissingThumbnails(projects);
      if (created > 0 && mounted) await _reload();
    } finally {
      _backfillingThumbnails = false;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: source == ImageSource.camera ? 100 : 96,
        maxWidth: source == ImageSource.camera ? null : 4096,
        maxHeight: source == ImageSource.camera ? null : 4096,
        requestFullMetadata: source == ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final taskId = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => EditorScreen(
            imageBytes: Uint8List.fromList(bytes),
            sourceName: file.name,
          ),
        ),
      );
      if (taskId != null && mounted) {
        setState(() => _selectedIndex = 1);
      }
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('无法读取图片：$error')),
      );
    }
  }

  Future<void> _pickMultipleImages() async {
    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 96,
        maxWidth: 4096,
        maxHeight: 4096,
        requestFullMetadata: false,
      );
      if (files.isEmpty || !mounted) return;
      final inputs = <EditorImageInput>[];
      for (final file in files) {
        inputs.add(
          EditorImageInput(
            bytes: Uint8List.fromList(await file.readAsBytes()),
            name: file.name,
          ),
        );
      }
      if (!mounted) return;
      final first = inputs.removeAt(0);
      final taskId = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => EditorScreen(
            imageBytes: first.bytes,
            sourceName: first.name,
            batchImages: inputs,
          ),
        ),
      );
      if (taskId != null && mounted) setState(() => _selectedIndex = 1);
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('无法批量读取图片：$error')),
      );
    }
  }

  Future<void> _openTextBead() async {
    final projectId = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const TextBeadScreen()));
    if (projectId != null && mounted) {
      await _reload();
      setState(() => _selectedIndex = 2);
    }
  }

  Future<void> _openColorRecognition() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ColorRecognitionScreen()),
    );
  }

  Future<void> _openAiDesign() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const AiDesignScreen()));
  }

  Future<void> _openAiHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const AiDesignHistoryScreen()),
    );
  }

  Future<void> _deleteProjects(List<String> ids) async {
    if (ids.isEmpty) return;
    final favoriteIds = _projects
        .where((project) => ids.contains(project.id) && project.isFavorite)
        .map((project) => project.id)
        .toSet();
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ids.length == 1 ? '移到回收站？' : '批量移到回收站？'),
        content: Text(
          favoriteIds.isEmpty
              ? '选中的 ${ids.length} 个作品将移到回收站，默认保留 30 天，期间可以恢复。'
              : '选中项包含 ${favoriteIds.length} 个收藏作品。可以跳过收藏作品，或将它们一并移到回收站。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          if (favoriteIds.isNotEmpty)
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'skip'),
              child: const Text('跳过收藏'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'all'),
            child: Text(favoriteIds.isEmpty ? '移到回收站' : '全部删除'),
          ),
        ],
      ),
    );
    if (decision == null) return;
    if (!mounted) return;
    if (decision == 'all' && favoriteIds.isNotEmpty) {
      final confirmedAgain = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('再次确认删除收藏作品'),
          content: Text(
            '你选择了“全部删除”，其中 ${favoriteIds.length} 个是收藏作品。确定仍要全部移到回收站吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回检查'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB83A32),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认全部删除'),
            ),
          ],
        ),
      );
      if (confirmedAgain != true) return;
    }
    final deleting = decision == 'skip'
        ? ids.where((id) => !favoriteIds.contains(id)).toList()
        : ids;
    if (deleting.isEmpty) {
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          const SnackBar(content: Text('已跳过全部收藏作品，没有删除任何内容')),
        );
      }
      return;
    }
    await _repository.moveManyToTrash(deleting, deletionSource: '我的作品');
    await _processingCenter.refreshDeletedResults();
    await _reload();
  }

  Future<void> _renameProject(ProjectSummary project) async {
    final controller = TextEditingController(text: project.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名作品'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: '作品名称',
            prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
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
    if (title == null || title == project.title) return;
    await _repository.rename(project.id, title);
    await _reload();
  }

  Future<void> _reorderProject(String movingId, String targetId) async {
    if (movingId == targetId) return;
    final ordered = _projects.map((value) => value.id).toList();
    final from = ordered.indexOf(movingId);
    final to = ordered.indexOf(targetId);
    if (from < 0 || to < 0) return;
    final id = ordered.removeAt(from);
    ordered.insert(to, id);
    await _repository.reorderProjects(ordered);
    await _reload();
  }

  Future<void> _openTrash() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _RecycleBinScreen(
          onChanged: () async {
            await _processingCenter.refreshDeletedResults();
            await _reload();
          },
        ),
      ),
    );
    await _processingCenter.refreshDeletedResults();
    if (mounted) await _reload();
  }

  Future<void> _toggleFavorite(ProjectSummary project) async {
    if (project.isFavorite) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.heart_broken_outlined),
          title: const Text('取消收藏？'),
          content: Text('确定要将“${project.title}”移出收藏吗？作品本身不会被删除。'),
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
      await _repository.setFavorite(project.id, false);
    } else {
      final category = await showFavoriteCategoryPicker(
        context,
        repository: _repository,
        currentCategory: project.favoriteCategory,
      );
      if (category == null) return;
      await _repository.setFavorite(project.id, true, category: category);
    }
    await _reload();
    if (!mounted) return;
    AppNoticeCenter.instance.showSnackBar(
      SnackBar(
        content: Text(project.isFavorite ? '已取消收藏' : '已加入所选分组'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  Future<void> _resetParameters() async {
    if (_projects.isEmpty) return;
    final selected = await showModalBottomSheet<ProjectSummary>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  '选择要重新设置参数的作品',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _projects.length,
                  itemBuilder: (context, index) {
                    final project = _projects[index];
                    return ListTile(
                      leading: SizedBox.square(
                        dimension: 52,
                        child: _ProjectThumbnail(project: project),
                      ),
                      title: Text(
                        project.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        project.isPhotoProject
                            ? 'AI 原图 · 照片'
                            : '${project.width}×${project.height} · ${project.colorCount} 色',
                      ),
                      onTap: () => Navigator.pop(context, project),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final pattern = await _repository.load(selected.id);
    if (pattern == null || !mounted) return;
    final taskId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          imageBytes: pattern.sourceBytes,
          sourceName: pattern.sourceName ?? selected.title,
          overwriteProjectId: selected.id,
          initialOptions: ProcessingOptions(
            size: pattern.width,
            height: pattern.height,
            maxColors: pattern.requestedColorCount,
            portraitMode: pattern.portraitMode,
            smoothing: pattern.smoothing,
            removeBackground: pattern.backgroundRemoved,
            template: pattern.template,
            variantSeed: pattern.variantSeed,
          ),
        ),
      ),
    );
    if (taskId != null && mounted) setState(() => _selectedIndex = 1);
  }

  Future<void> _exportAllWorks() async {
    try {
      await _backup.shareBackup();
    } on Object catch (error) {
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('导出失败：$error')),
        );
      }
    }
  }

  Future<void> _importWorks() async {
    try {
      final result = await _backup.pickAndImport();
      if (result == null || !mounted) return;
      await _reload();
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(
          content: Text(
            '已导入 ${result.imported} 个作品${result.skipped == 0 ? '' : '，跳过 ${result.skipped} 个损坏项目'}',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('导入失败：$error')),
        );
      }
    }
  }

  Future<void> _saveProjectsLocally(List<ProjectSummary> projects) async {
    if (projects.isEmpty || !mounted) return;
    final hasBeadPattern = projects.any((project) => !project.isPhotoProject);
    String? type = 'original';
    if (hasBeadPattern) {
      type = await showModalBottomSheet<String>(
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
                ListTile(
                  title: Text(
                    projects.length == 1
                        ? '保存“${projects.single.title}”到本地'
                        : '批量保存 ${projects.length} 个作品到本地',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    projects.any((project) => project.isPhotoProject)
                        ? 'AI 原图作品会自动按原图保存；其他作品使用下方所选格式'
                        : '图片会保存到“图片/拼豆AI”',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_outlined),
                  title: const Text('保存原图'),
                  subtitle: const Text('生成像素图时使用的原始图片'),
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
                  subtitle: const Text('每一格显示当前品牌的颜色编号'),
                  onTap: () => Navigator.pop(context, 'grid'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (type == null || !mounted) return;
    final exporter = ExportService();
    var saved = 0;
    var failed = 0;
    Object? lastError;
    for (final summary in projects) {
      try {
        final pattern = await _repository.load(summary.id);
        if (pattern == null) throw StateError('作品数据不存在或已损坏');
        if (pattern.isPhotoProject || type == 'original') {
          await exporter.saveOriginal(pattern);
        } else if (type == 'pixelPreview') {
          await exporter.savePixelPreview(pattern);
        } else if (type == 'effectPreview') {
          await exporter.savePreview(pattern);
        } else {
          await exporter.saveCodeGrid(pattern);
        }
        saved++;
      } on Object catch (error) {
        failed++;
        lastError = error;
      }
    }
    if (!mounted) return;
    AppNoticeCenter.instance.showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? '已将 $saved 个作品保存到“图片/拼豆AI”'
              : '已保存 $saved 个，失败 $failed 个${lastError == null ? '' : '：$lastError'}',
        ),
      ),
    );
  }

  Future<void> _confirmExitApp() async {
    if (_exitDialogOpen || !mounted) return;
    _exitDialogOpen = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.exit_to_app_rounded),
        title: const Text('退出拼豆 AI？'),
        content: Text(
          _customBoardHasDraft
              ? '自定义画板还有未保存内容，草稿已经自动保存。确定回到桌面吗？'
              : '确定要退出并回到桌面吗？正在处理的任务会保留在处理中心。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续使用'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出应用'),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (confirmed == true) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _DashboardPage(
        projects: _projects,
        loading: _loading,
        onGallery: () => _pickImage(ImageSource.gallery),
        onBatchGallery: _pickMultipleImages,
        onCamera: () => _pickImage(ImageSource.camera),
        onText: _openTextBead,
        onRecognition: _openColorRecognition,
        onAiDesign: _openAiDesign,
        onShowAiHistory: _openAiHistory,
        onOpenProject: _openProject,
        onShowWorks: () => setState(() => _selectedIndex = 2),
      ),
      ProcessingCenterScreen(onOpenResult: _openProjectId),
      _WorksPage(
        projects: _projects,
        loading: _loading,
        onOpen: _openProject,
        onDeleteMany: _deleteProjects,
        onToggleFavorite: _toggleFavorite,
        onRename: _renameProject,
        onCreate: () => _pickImage(ImageSource.gallery),
        onOpenTrash: _openTrash,
        onResetParameters: _resetParameters,
        onExportAll: _exportAllWorks,
        onImportAll: _importWorks,
        onSaveMany: _saveProjectsLocally,
        onReorder: _reorderProject,
      ),
      _FavoritesPage(
        projects: _projects.where((project) => project.isFavorite).toList(),
        loading: _loading,
        onOpen: _openProject,
        onToggleFavorite: _toggleFavorite,
        onChanged: _reload,
        onSaveMany: _saveProjectsLocally,
        onReorder: _reorderProject,
      ),
      CustomBoardScreen(
        embedded: true,
        onSaved: _reload,
        onDirtyChanged: (value) => _customBoardHasDraft = value,
      ),
      const PatternCollectionScreen(),
      AiChatScreen(onProjectsChanged: _reload),
      const _PalettePage(),
      const _ProfilePage(),
    ];
    final scaffold = Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: AppStrings.text(context, 'home'),
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _taskBadgeCount > 0,
              label: Text('$_taskBadgeCount'),
              child: const Icon(Icons.hourglass_empty_rounded),
            ),
            selectedIcon: Badge(
              isLabelVisible: _taskBadgeCount > 0,
              label: Text('$_taskBadgeCount'),
              child: const Icon(Icons.hourglass_top_rounded),
            ),
            label: AppStrings.text(context, 'processing'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view),
            label: AppStrings.text(context, 'works'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.favorite_border_rounded),
            selectedIcon: const Icon(Icons.favorite_rounded),
            label: AppStrings.text(context, 'favorites'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.draw_outlined),
            selectedIcon: const Icon(Icons.draw_rounded),
            label: AppStrings.text(context, 'custom'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.collections_bookmark_outlined),
            selectedIcon: const Icon(Icons.collections_bookmark_rounded),
            label: AppStrings.text(context, 'collection'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.forum_outlined),
            selectedIcon: const Icon(Icons.forum_rounded),
            label: AppStrings.text(context, 'aiChat'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.palette_outlined),
            selectedIcon: const Icon(Icons.palette),
            label: AppStrings.text(context, 'palette'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: AppStrings.text(context, 'profile'),
          ),
        ],
      ),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmExitApp());
      },
      child: scaffold,
    );
  }

  Future<void> _openProject(ProjectSummary project) =>
      _openProjectId(project.id);

  Future<void> _openProjectId(String id) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final pattern = await _repository.load(id);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (pattern == null) {
      AppNoticeCenter.instance.showSnackBar(
        const SnackBar(content: Text('作品数据已损坏或不存在')),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => pattern.isPhotoProject
            ? PhotoProjectScreen(project: pattern)
            : ResultScreen(pattern: pattern),
      ),
    );
    if (mounted) await _reload();
  }
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({
    required this.projects,
    required this.loading,
    required this.onGallery,
    required this.onBatchGallery,
    required this.onCamera,
    required this.onText,
    required this.onRecognition,
    required this.onAiDesign,
    required this.onShowAiHistory,
    required this.onOpenProject,
    required this.onShowWorks,
  });

  final List<ProjectSummary> projects;
  final bool loading;
  final VoidCallback onGallery;
  final VoidCallback onBatchGallery;
  final VoidCallback onCamera;
  final VoidCallback onText;
  final VoidCallback onRecognition;
  final VoidCallback onAiDesign;
  final VoidCallback onShowAiHistory;
  final ValueChanged<ProjectSummary> onOpenProject;
  final VoidCallback onShowWorks;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
          sliver: SliverList.list(
            children: [
              const _BrandHeader(),
              const SizedBox(height: 26),
              Text(
                '把照片变成\n真正能做的拼豆图',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 10),
              const Text(
                '分析原图色彩，可选 MARD、Artkal、COCO、Perler 或 Hama 色号，连同格子图和购买数量一次生成。',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              _CreateCard(
                onGallery: onGallery,
                onBatchGallery: onBatchGallery,
                onCamera: onCamera,
                onText: onText,
                onRecognition: onRecognition,
                onAiDesign: onAiDesign,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('homeAiHistoryButton'),
                onPressed: onShowAiHistory,
                icon: const Icon(Icons.auto_awesome_motion_rounded),
                label: const Text('AI 制图记录（全部 AI 图片）'),
              ),
              const SizedBox(height: 28),
              _SectionTitle(title: '最近作品', action: '查看全部', onTap: onShowWorks),
              const SizedBox(height: 13),
              if (loading)
                const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (projects.isEmpty)
                const _EmptyRecent()
              else
                SizedBox(
                  height: 184,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: projects.take(6).length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      return _ProjectTile(
                        project: project,
                        onTap: () => onOpenProject(project),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 22),
              const Center(
                child: Text(
                  '版权所有 © 2026 xuan',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.blur_circular_rounded,
            color: Colors.white,
            size: 29,
          ),
        ),
        const SizedBox(width: 11),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '拼豆 AI',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            Text(
              'BEAD DESIGN STUDIO',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.4,
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.mint,
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Row(
            children: [
              Icon(Icons.offline_bolt_rounded, size: 15, color: AppColors.teal),
              SizedBox(width: 4),
              Text(
                '离线可用',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.teal,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CreateCard extends StatelessWidget {
  const _CreateCard({
    required this.onGallery,
    required this.onBatchGallery,
    required this.onCamera,
    required this.onText,
    required this.onRecognition,
    required this.onAiDesign,
  });

  final VoidCallback onGallery;
  final VoidCallback onBatchGallery;
  final VoidCallback onCamera;
  final VoidCallback onText;
  final VoidCallback onRecognition;
  final VoidCallback onAiDesign;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, Color.lerp(accent, Colors.black, 0.07)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30),
          const SizedBox(height: 15),
          const Text(
            '开始一个新作品',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '选择一张清晰照片，约 10 秒生成',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onGallery,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: accent,
                  ),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('从相册选择'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: onCamera,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(54, 54),
                ),
                icon: const Icon(Icons.photo_camera_rounded),
                tooltip: '拍摄照片',
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onBatchGallery,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              icon: const Icon(Icons.collections_rounded),
              label: const Text('批量选择图片'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onText,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              icon: const Icon(Icons.text_fields_rounded),
              label: const Text('文字拼豆'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRecognition,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              icon: const Icon(Icons.colorize_rounded),
              label: const Text('图片色号识别'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAiDesign,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('AI 拼豆图纸对话'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const Spacer(),
      if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
    ],
  );
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) => Container(
    height: 132,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.line),
    ),
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            color: AppColors.muted,
            size: 34,
          ),
          SizedBox(height: 7),
          Text('第一件作品，从一张照片开始', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    ),
  );
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, required this.onTap});
  final ProjectSummary project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 145,
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ProjectThumbnail(project: project),
                  if (project.isFavorite)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFE85584),
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 7, 11, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    project.isPhotoProject
                        ? 'AI 原图 · 照片'
                        : '${project.width}×${project.height} · ${project.colorCount} 色',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
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

class _ProjectThumbnail extends StatelessWidget {
  const _ProjectThumbnail({required this.project});

  final ProjectSummary project;

  @override
  Widget build(BuildContext context) {
    final path = project.thumbnailPath;
    if (path == null) return const _ThumbnailPlaceholder();
    return RepaintBoundary(
      child: Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 320,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => const _ThumbnailPlaceholder(),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.peach,
    child: const Center(
      child: Icon(Icons.grid_on_rounded, color: AppColors.coral, size: 38),
    ),
  );
}

class _WorksPage extends StatefulWidget {
  const _WorksPage({
    required this.projects,
    required this.loading,
    required this.onOpen,
    required this.onDeleteMany,
    required this.onToggleFavorite,
    required this.onRename,
    required this.onCreate,
    required this.onOpenTrash,
    required this.onResetParameters,
    required this.onExportAll,
    required this.onImportAll,
    required this.onSaveMany,
    required this.onReorder,
  });
  final List<ProjectSummary> projects;
  final bool loading;
  final ValueChanged<ProjectSummary> onOpen;
  final Future<void> Function(List<String>) onDeleteMany;
  final ValueChanged<ProjectSummary> onToggleFavorite;
  final ValueChanged<ProjectSummary> onRename;
  final VoidCallback onCreate;
  final VoidCallback onOpenTrash;
  final VoidCallback onResetParameters;
  final VoidCallback onExportAll;
  final VoidCallback onImportAll;
  final Future<void> Function(List<ProjectSummary>) onSaveMany;
  final Future<void> Function(String movingId, String targetId) onReorder;

  @override
  State<_WorksPage> createState() => _WorksPageState();
}

class _WorksPageState extends State<_WorksPage> {
  final Set<String> _selected = {};
  var _selecting = false;

  @override
  void didUpdateWidget(covariant _WorksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.projects.map((project) => project.id).toSet();
    _selected.removeWhere((id) => !ids.contains(id));
    if (_selected.isEmpty && widget.projects.isEmpty) _selecting = false;
  }

  void _toggle(ProjectSummary project) {
    setState(() {
      _selecting = true;
      if (!_selected.add(project.id)) _selected.remove(project.id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList(growable: false);
    if (ids.isEmpty) return;
    await widget.onDeleteMany(ids);
    if (mounted) _exitSelection();
  }

  Future<void> _saveSelected() async {
    final selected = widget.projects
        .where((project) => _selected.contains(project.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    await widget.onSaveMany(selected);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      leading: _selecting
          ? IconButton(
              onPressed: _exitSelection,
              icon: const Icon(Icons.close),
              tooltip: '退出批量管理',
            )
          : null,
      title: Text(
        _selecting ? '已选择 ${_selected.length} 项' : '我的作品',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        if (!_selecting)
          PopupMenuButton<String>(
            tooltip: '导入或导出作品',
            onSelected: (value) {
              if (value == 'export') widget.onExportAll();
              if (value == 'import') widget.onImportAll();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.file_upload_outlined),
                  title: Text('导出全部作品'),
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.file_download_outlined),
                  title: Text('导入作品备份'),
                ),
              ),
            ],
          ),
        if (!_selecting)
          IconButton(
            onPressed: widget.onOpenTrash,
            tooltip: '回收站',
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        if (!_selecting && widget.projects.isNotEmpty)
          TextButton.icon(
            onPressed: () => setState(() => _selecting = true),
            icon: const Icon(Icons.checklist_rounded),
            label: const Text('批量管理'),
          ),
        if (_selecting)
          TextButton(
            onPressed: () => setState(() {
              if (_selected.length == widget.projects.length) {
                _selected.clear();
              } else {
                _selected.addAll(widget.projects.map((project) => project.id));
              }
            }),
            child: Text(
              _selected.length == widget.projects.length ? '取消全选' : '全选',
            ),
          ),
      ],
    ),
    floatingActionButton: _selecting
        ? null
        : FloatingActionButton.extended(
            onPressed: widget.onCreate,
            icon: const Icon(Icons.add),
            label: const Text('新作品'),
          ),
    bottomNavigationBar: _selecting
        ? SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selected.isEmpty ? null : _saveSelected,
                      icon: const Icon(Icons.download_rounded),
                      label: Text('保存 ${_selected.length} 个'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _selected.isEmpty ? null : _deleteSelected,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB83A32),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: Text('删除 ${_selected.length} 个'),
                    ),
                  ),
                ],
              ),
            ),
          )
        : null,
    body: widget.loading
        ? const Center(child: CircularProgressIndicator())
        : widget.projects.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.grid_view_rounded,
                    size: 58,
                    color: AppColors.muted,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '还没有保存的作品',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '完成一次图片转换后，作品会自动保存在本机。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          )
        : CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final project = widget.projects[index];
                    final selected = _selected.contains(project.id);
                    final card = Card(
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: selected ? AppColors.coral : AppColors.line,
                          width: selected ? 3 : 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () => _selecting
                            ? _toggle(project)
                            : widget.onOpen(project),
                        onDoubleTap: _selecting
                            ? null
                            : () => widget.onRename(project),
                        onLongPress: _selecting ? () => _toggle(project) : null,
                        child: Column(
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _ProjectThumbnail(project: project),
                                  if (!_selecting)
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: IconButton.filledTonal(
                                        onPressed: () =>
                                            widget.onSaveMany([project]),
                                        tooltip: '保存到本地',
                                        icon: const Icon(
                                          Icons.download_rounded,
                                        ),
                                      ),
                                    ),
                                  if (_selecting)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Checkbox(
                                        value: selected,
                                        onChanged: (_) => _toggle(project),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            ListTile(
                              dense: true,
                              title: GestureDetector(
                                onLongPress: _selecting
                                    ? null
                                    : () => widget.onRename(project),
                                child: Text(
                                  project.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              subtitle: Text(
                                project.isPhotoProject
                                    ? 'AI 原图 · 照片'
                                    : '${project.width}×${project.height} · ${project.totalBeads} 颗',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: _selecting
                                  ? null
                                  : IconButton(
                                      onPressed: () {
                                        widget.onToggleFavorite(project);
                                      },
                                      color: project.isFavorite
                                          ? const Color(0xFFE85584)
                                          : AppColors.muted,
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size(38, 38),
                                        padding: EdgeInsets.zero,
                                      ),
                                      icon: Icon(
                                        project.isFavorite
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                      ),
                                      tooltip: project.isFavorite
                                          ? '取消收藏'
                                          : '收藏作品',
                                    ),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (_selecting) return card;
                    return DragTarget<ProjectSummary>(
                      onWillAcceptWithDetails: (details) =>
                          details.data.id != project.id,
                      onAcceptWithDetails: (details) =>
                          widget.onReorder(details.data.id, project.id),
                      builder: (context, candidates, rejects) =>
                          LongPressDraggable<ProjectSummary>(
                            data: project,
                            feedback: Material(
                              elevation: 14,
                              borderRadius: BorderRadius.circular(18),
                              child: SizedBox(
                                width: 170,
                                height: 220,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: _ProjectThumbnail(project: project),
                                ),
                              ),
                            ),
                            child: AnimatedScale(
                              scale: candidates.isEmpty ? 1 : .94,
                              duration: const Duration(milliseconds: 120),
                              child: card,
                            ),
                          ),
                    );
                  }, childCount: widget.projects.length),
                ),
              ),
              if (!_selecting)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 110),
                    child: OutlinedButton.icon(
                      onPressed: widget.onResetParameters,
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('重新设置参数'),
                    ),
                  ),
                ),
            ],
          ),
  );
}

class _RecycleBinScreen extends StatefulWidget {
  const _RecycleBinScreen({required this.onChanged});

  final Future<void> Function() onChanged;

  @override
  State<_RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<_RecycleBinScreen> {
  final _repository = ProjectRepository();
  var _projects = <ProjectSummary>[];
  var _retentionDays = ProjectRepository.defaultTrashRetentionDays;
  var _loading = true;
  final Set<String> _selected = {};
  var _selecting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final values = await Future.wait<Object>([
      _repository.loadTrashSummaries(),
      _repository.getTrashRetentionDays(),
    ]);
    if (!mounted) return;
    setState(() {
      _projects = values[0] as List<ProjectSummary>;
      _retentionDays = values[1] as int;
      _loading = false;
    });
  }

  Future<void> _restore(ProjectSummary project) async {
    try {
      await _repository.restoreFromTrash(project.id);
      await widget.onChanged();
      await _reload();
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('“${project.title}”已恢复')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('恢复失败：$error')),
      );
    }
  }

  Future<void> _deletePermanently(ProjectSummary project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除作品？'),
        content: Text('“${project.title}”删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB83A32),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.deletePermanently(project.id);
    await _reload();
  }

  void _toggleTrash(ProjectSummary project) {
    setState(() {
      _selecting = true;
      if (!_selected.add(project.id)) _selected.remove(project.id);
    });
  }

  Future<void> _deleteSelectedPermanently() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量永久删除？'),
        content: Text('选中的 ${_selected.length} 个作品删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB83A32),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final id in _selected) {
      await _repository.deletePermanently(id);
    }
    _selected.clear();
    _selecting = false;
    await _reload();
  }

  Future<void> _restoreSelected() async {
    for (final id in _selected) {
      await _repository.restoreFromTrash(id);
    }
    _selected.clear();
    _selecting = false;
    await widget.onChanged();
    await _reload();
  }

  Future<void> _emptyTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空回收站？'),
        content: Text('回收站中的 ${_projects.length} 个作品将被永久删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB83A32),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.emptyTrash();
    await _reload();
  }

  Future<void> _setRetention() async {
    final controller = TextEditingController(text: '$_retentionDays');
    String? errorText;
    final days = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('设置回收站保留时间'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '默认保留 30 天，可设置 1–3650 天（最长约 10 年）。到期的作品会自动永久删除。',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '保留天数',
                  suffixText: '天',
                  errorText: errorText,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value == null ||
                    value < 1 ||
                    value > ProjectRepository.maxTrashRetentionDays) {
                  setDialogState(() => errorText = '请输入 1–3650 之间的整数');
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('保存'),
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
    if (days == null) return;
    await _repository.setTrashRetentionDays(days);
    await _reload();
  }

  String _remainingText(ProjectSummary project) {
    final deletedAt = project.deletedAt;
    if (deletedAt == null) return '等待自动清理';
    final expiresAt = deletedAt.add(Duration(days: _retentionDays));
    final remaining = expiresAt.difference(DateTime.now()).inDays + 1;
    return remaining <= 1 ? '将在今天自动删除' : '约 $remaining 天后自动删除';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: _selecting
          ? IconButton(
              onPressed: () => setState(() {
                _selecting = false;
                _selected.clear();
              }),
              icon: const Icon(Icons.close),
            )
          : null,
      title: Text(
        _selecting ? '已选择 ${_selected.length} 项' : '回收站',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        if (!_selecting)
          IconButton(
            onPressed: _setRetention,
            tooltip: '设置保留时间',
            icon: const Icon(Icons.timer_outlined),
          ),
        if (!_selecting && _projects.isNotEmpty)
          TextButton.icon(
            onPressed: () => setState(() => _selecting = true),
            icon: const Icon(Icons.checklist_rounded),
            label: const Text('多选'),
          ),
        if (_selecting)
          TextButton(
            onPressed: () => setState(() {
              if (_selected.length == _projects.length) {
                _selected.clear();
              } else {
                _selected.addAll(_projects.map((item) => item.id));
              }
            }),
            child: Text(_selected.length == _projects.length ? '取消全选' : '全选'),
          ),
        if (!_selecting && _projects.isNotEmpty)
          IconButton(
            onPressed: _emptyTrash,
            tooltip: '清空回收站',
            icon: const Icon(Icons.delete_forever_outlined),
          ),
        const SizedBox(width: 6),
      ],
    ),
    bottomNavigationBar: _selecting
        ? SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selected.isEmpty ? null : _restoreSelected,
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('批量恢复'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : _deleteSelectedPermanently,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB83A32),
                      ),
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('永久删除'),
                    ),
                  ),
                ],
              ),
            ),
          )
        : null,
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _projects.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.delete_outline_rounded,
                    size: 62,
                    color: AppColors.muted,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '回收站是空的',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '删除的作品会在这里保留 $_retentionDays 天',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            itemCount: _projects.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.mint,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, color: AppColors.teal),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '当前保留 $_retentionDays 天，共 ${_projects.length} 个作品',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                );
              }
              final project = _projects[index - 1];
              final selected = _selected.contains(project.id);
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : AppColors.line,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: InkWell(
                  onLongPress: () => _toggleTrash(project),
                  onTap: _selecting ? () => _toggleTrash(project) : null,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 82,
                          height: 82,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: _ProjectThumbnail(project: project),
                          ),
                        ),
                        if (_selecting)
                          Checkbox(
                            value: selected,
                            onChanged: (_) => _toggleTrash(project),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                project.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                project.isPhotoProject
                                    ? 'AI 原图 · 照片'
                                    : '${project.width}×${project.height} · ${project.totalBeads} 颗',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _remainingText(project),
                                style: const TextStyle(
                                  color: AppColors.coralDark,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '删除来源：${project.deletedFrom ?? '我的作品'}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 7),
                              if (!_selecting)
                                Row(
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: () => _restore(project),
                                      icon: const Icon(
                                        Icons.restore_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('恢复'),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          _deletePermanently(project),
                                      tooltip: '永久删除',
                                      icon: const Icon(
                                        Icons.delete_forever_outlined,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
  );
}

class _FavoritesPage extends StatefulWidget {
  const _FavoritesPage({
    required this.projects,
    required this.loading,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onChanged,
    required this.onSaveMany,
    required this.onReorder,
  });

  final List<ProjectSummary> projects;
  final bool loading;
  final ValueChanged<ProjectSummary> onOpen;
  final Future<void> Function(ProjectSummary) onToggleFavorite;
  final Future<void> Function() onChanged;
  final Future<void> Function(List<ProjectSummary>) onSaveMany;
  final Future<void> Function(String movingId, String targetId) onReorder;

  @override
  State<_FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<_FavoritesPage> {
  final _repository = ProjectRepository();
  final _collection = CollectionLibrary.instance;
  var _categories = <String>['未分类'];
  var _selectedCategory = '全部';
  final _selected = <String>{};
  var _selecting = false;

  @override
  void initState() {
    super.initState();
    _collection.addListener(_onCollectionChanged);
    unawaited(_collection.initialize());
    unawaited(_loadCategories());
  }

  void _onCollectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _collection.removeListener(_onCollectionChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _FavoritesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_loadCategories());
  }

  Future<void> _loadCategories() async {
    final values = await _repository.loadFavoriteCategories();
    if (!mounted) return;
    setState(() {
      _categories = values;
      if (_selectedCategory != '全部' && !values.contains(_selectedCategory)) {
        _selectedCategory = '全部';
      }
    });
  }

  Future<String?> _askCategoryName(String title, [String initial = '']) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(labelText: '分类名称'),
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
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _createCategory() async {
    final value = await _askCategoryName('新建收藏分类');
    if (value == null) return;
    await _repository.saveFavoriteCategories([..._categories, value]);
    await _loadCategories();
  }

  Future<void> _manageCategories() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '分类管理',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        final value = await _askCategoryName('新建收藏分类');
                        if (value == null) return;
                        await _repository.saveFavoriteCategories([
                          ..._categories,
                          value,
                        ]);
                        await _loadCategories();
                        setSheetState(() {});
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('新建'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final category in _categories)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(category),
                    subtitle: Text(
                      '${widget.projects.where((item) => (item.favoriteCategory ?? '未分类') == category).length} 个作品',
                    ),
                    trailing: category == '未分类'
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () async {
                                  final value = await _askCategoryName(
                                    '重命名分类',
                                    category,
                                  );
                                  if (value == null) return;
                                  await _repository.renameFavoriteCategory(
                                    category,
                                    value,
                                  );
                                  await widget.onChanged();
                                  await _loadCategories();
                                  setSheetState(() {});
                                },
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: '重命名分类',
                              ),
                              IconButton(
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('删除分类？'),
                                      content: const Text(
                                        '分类中的作品不会取消收藏，将自动移动到“未分类”。',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('取消'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('删除分类'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true) return;
                                  await _repository.deleteFavoriteCategory(
                                    category,
                                  );
                                  await widget.onChanged();
                                  await _loadCategories();
                                  setSheetState(() {});
                                },
                                icon: const Icon(Icons.delete_outline),
                                tooltip: '删除分类',
                              ),
                            ],
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _assignCategory(ProjectSummary project) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: [
            const ListTile(
              title: Text(
                '移动到分类',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            for (final category in _categories)
              ListTile(
                leading: Icon(
                  (project.favoriteCategory ?? '未分类') == category
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                ),
                title: Text(category),
                onTap: () => Navigator.pop(context, category),
              ),
          ],
        ),
      ),
    );
    if (value == null) return;
    await _repository.assignFavoriteCategory(project.id, value);
    await widget.onChanged();
    await _loadCategories();
  }

  String _favoriteId(Object value) => switch (value) {
    ProjectSummary project => 'project:${project.id}',
    CollectionPatternItem item => 'collection:${item.id}',
    _ => '',
  };

  void _toggleSelected(Object value) {
    final id = _favoriteId(value);
    if (id.isEmpty) return;
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _exitFavoriteSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  List<ProjectSummary> get _selectedProjects => widget.projects
      .where((project) => _selected.contains('project:${project.id}'))
      .toList();

  List<CollectionPatternItem> get _selectedCollectionItems => _collection
      .favorites
      .where((item) => _selected.contains('collection:${item.id}'))
      .toList();

  Future<void> _batchMoveFavorites() async {
    if (_selectedProjects.isEmpty) {
      AppNoticeCenter.instance.show(
        '合集图纸收藏不支持作品分组；请选择“我的作品”中的收藏。',
        kind: AppNoticeKind.warning,
      );
      return;
    }
    final category = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                '批量移动到分类',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            for (final value in _categories)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(value),
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (category == null) return;
    for (final project in _selectedProjects) {
      await _repository.assignFavoriteCategory(project.id, category);
    }
    await widget.onChanged();
    await _loadCategories();
    _exitFavoriteSelection();
  }

  Future<void> _batchRenameFavorites() async {
    final count = _selectedProjects.length + _selectedCollectionItems.length;
    if (count == 0) return;
    final controller = TextEditingController();
    final prefix = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '统一名称前缀',
            helperText: '多项会自动追加 01、02…，不会产生同名覆盖',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('重命名'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (prefix == null || prefix.isEmpty) return;
    var index = 1;
    String nextName() {
      if (count == 1) return prefix;
      final suffix = (index++).toString().padLeft(2, '0');
      return '$prefix $suffix';
    }

    for (final project in _selectedProjects) {
      await _repository.rename(project.id, nextName());
    }
    for (final item in _selectedCollectionItems) {
      if (item.isUserUpload) {
        await _collection.updateUpload(
          item,
          name: nextName(),
          category: item.category,
        );
      } else {
        await _collection.renameBuiltIn(item, nextName());
      }
    }
    await widget.onChanged();
    _exitFavoriteSelection();
  }

  Future<void> _batchCancelFavorites() async {
    if (_selected.isEmpty) return;
    for (final project in _selectedProjects) {
      await _repository.setFavorite(project.id, false);
    }
    for (final item in _selectedCollectionItems) {
      if (item.isFavorite) await _collection.toggleFavorite(item);
    }
    await widget.onChanged();
    await _loadCategories();
    _exitFavoriteSelection();
  }

  Future<void> _batchSaveFavorites() async {
    if (_selected.isEmpty) return;
    if (_selectedProjects.isNotEmpty) {
      await widget.onSaveMany(_selectedProjects);
    }
    for (final item in _selectedCollectionItems) {
      if (!mounted) return;
      await saveCollectionPatternToLocal(context, item);
    }
  }

  Future<void> _batchDeleteFavorites() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量删除收藏内容？'),
        content: const Text('选中的“我的作品”会移入作品回收站；用户上传图会从图纸库永久删除；内置图纸只会取消收藏。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.moveManyToTrash(
      _selectedProjects.map((value) => value.id),
      deletionSource: '我的收藏',
    );
    for (final item in _selectedCollectionItems) {
      if (item.isUserUpload) {
        await _collection.deleteUpload(item);
      } else if (item.isFavorite) {
        await _collection.toggleFavorite(item);
      }
    }
    await widget.onChanged();
    _exitFavoriteSelection();
  }

  Future<void> _renameFavoriteProject(ProjectSummary project) async {
    final controller = TextEditingController(text: project.title);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名收藏作品'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
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
    if (value == null || value.isEmpty) return;
    await _repository.rename(project.id, value);
    await widget.onChanged();
  }

  Widget _categoryStrip() => SizedBox(
    height: 50,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      itemCount: _categories.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 7),
      itemBuilder: (context, index) {
        final category = index == 0 ? '全部' : _categories[index - 1];
        final count = category == '全部'
            ? widget.projects.length + _collection.favorites.length
            : widget.projects
                  .where((item) => (item.favoriteCategory ?? '未分类') == category)
                  .length;
        return ChoiceChip(
          label: Text('$category ($count)'),
          selected: _selectedCategory == category,
          onSelected: (_) => setState(() => _selectedCategory = category),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final visible = widget.projects.where((project) {
      return _selectedCategory == '全部' ||
          (project.favoriteCategory ?? '未分类') == _selectedCategory;
    }).toList();
    final visibleEntries = <Object>[
      ...visible,
      if (_selectedCategory == '全部') ..._collection.favorites,
    ];
    final totalFavorites =
        widget.projects.length + _collection.favorites.length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                onPressed: _exitFavoriteSelection,
                tooltip: '退出批量管理',
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: _selecting
            ? Text(
                '已选择 ${_selected.length} 项',
                style: const TextStyle(fontWeight: FontWeight.w900),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '我的收藏',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '$totalFavorites 个珍藏作品',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
        actions: [
          if (_selecting)
            TextButton(
              onPressed: () => setState(() {
                final all = visibleEntries
                    .map(_favoriteId)
                    .where((id) => id.isNotEmpty)
                    .toSet();
                if (_selected.containsAll(all)) {
                  _selected.removeAll(all);
                } else {
                  _selected.addAll(all);
                }
              }),
              child: const Text('全选'),
            )
          else ...[
            IconButton(
              onPressed: _createCategory,
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: '新建分类',
            ),
            IconButton(
              onPressed: _manageCategories,
              icon: const Icon(Icons.folder_copy_outlined),
              tooltip: '分类管理',
            ),
            TextButton.icon(
              onPressed: totalFavorites == 0
                  ? null
                  : () => setState(() => _selecting = true),
              icon: const Icon(Icons.checklist_rounded),
              label: const Text('批量'),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 10),
                child: Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 6,
                  children: [
                    TextButton.icon(
                      onPressed: _selected.isEmpty ? null : _batchSaveFavorites,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('保存'),
                    ),
                    TextButton.icon(
                      onPressed: _selected.isEmpty ? null : _batchMoveFavorites,
                      icon: const Icon(Icons.drive_file_move_outline),
                      label: const Text('移动'),
                    ),
                    TextButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : _batchRenameFavorites,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('重命名'),
                    ),
                    TextButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : _batchCancelFavorites,
                      icon: const Icon(Icons.heart_broken_outlined),
                      label: const Text('取消收藏'),
                    ),
                    TextButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : _batchDeleteFavorites,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('删除'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: widget.loading
          ? const Center(child: CircularProgressIndicator())
          : totalFavorites == 0
          ? Column(
              children: [
                _categoryStrip(),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 82,
                            height: 82,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFE4ED),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.favorite_border_rounded,
                              color: Color(0xFFE85584),
                              size: 43,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            '还没有收藏作品',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '分类已经准备好。收藏作品时可直接选择分组，\n新建的分组也会立即显示在这里。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.muted,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                _categoryStrip(),
                Expanded(
                  child: visibleEntries.isEmpty
                      ? const Center(
                          child: Text(
                            '这个分类还没有作品',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 260,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.82,
                              ),
                          itemCount: visibleEntries.length,
                          itemBuilder: (context, index) {
                            final entry = visibleEntries[index];
                            if (entry is CollectionPatternItem) {
                              final selected = _selected.contains(
                                _favoriteId(entry),
                              );
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _selecting
                                    ? () => _toggleSelected(entry)
                                    : null,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        ignoring: _selecting,
                                        child: CollectionPatternCard(
                                          item: entry,
                                        ),
                                      ),
                                    ),
                                    if (_selecting)
                                      Positioned(
                                        right: 7,
                                        top: 7,
                                        child: Checkbox(
                                          value: selected,
                                          onChanged: (_) =>
                                              _toggleSelected(entry),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }
                            final project = entry as ProjectSummary;
                            final selected = _selected.contains(
                              _favoriteId(project),
                            );
                            final card = Card(
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: selected
                                      ? AppColors.coral
                                      : AppColors.line,
                                  width: selected ? 3 : 1,
                                ),
                              ),
                              child: InkWell(
                                onTap: () => _selecting
                                    ? _toggleSelected(project)
                                    : widget.onOpen(project),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          _ProjectThumbnail(project: project),
                                          if (!_selecting)
                                            Positioned(
                                              left: 7,
                                              top: 7,
                                              child: IconButton.filledTonal(
                                                onPressed: () => widget
                                                    .onSaveMany([project]),
                                                tooltip: '保存到本地',
                                                icon: const Icon(
                                                  Icons.download_rounded,
                                                ),
                                              ),
                                            ),
                                          if (_selecting)
                                            Positioned(
                                              right: 7,
                                              top: 7,
                                              child: Checkbox(
                                                value: selected,
                                                onChanged: (_) =>
                                                    _toggleSelected(project),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    ListTile(
                                      dense: true,
                                      title: GestureDetector(
                                        onLongPress: _selecting
                                            ? null
                                            : () => _renameFavoriteProject(
                                                project,
                                              ),
                                        child: Text(
                                          project.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      subtitle: Text(
                                        project.isPhotoProject
                                            ? 'AI 原图 · 照片'
                                            : '${project.width}×${project.height} · ${project.colorCount}色',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      trailing: PopupMenuButton<String>(
                                        tooltip: '收藏操作',
                                        onSelected: (value) async {
                                          if (value == 'category') {
                                            await _assignCategory(project);
                                          }
                                          if (value == 'save') {
                                            await widget.onSaveMany([project]);
                                          }
                                          if (value == 'remove') {
                                            await widget.onToggleFavorite(
                                              project,
                                            );
                                            await _loadCategories();
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'save',
                                            child: Text('保存到本地'),
                                          ),
                                          PopupMenuItem(
                                            value: 'category',
                                            child: Text('移动分类'),
                                          ),
                                          PopupMenuItem(
                                            value: 'remove',
                                            child: Text('取消收藏'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            if (_selecting) return card;
                            return DragTarget<ProjectSummary>(
                              onWillAcceptWithDetails: (details) =>
                                  details.data.id != project.id,
                              onAcceptWithDetails: (details) =>
                                  widget.onReorder(details.data.id, project.id),
                              builder: (context, candidates, rejects) =>
                                  LongPressDraggable<ProjectSummary>(
                                    data: project,
                                    feedback: Material(
                                      elevation: 14,
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        width: 170,
                                        height: 220,
                                        child: _ProjectThumbnail(
                                          project: project,
                                        ),
                                      ),
                                    ),
                                    child: AnimatedScale(
                                      scale: candidates.isEmpty ? 1 : .94,
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      child: card,
                                    ),
                                  ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _PalettePage extends StatefulWidget {
  const _PalettePage();

  @override
  State<_PalettePage> createState() => _PalettePageState();
}

class _PalettePageState extends State<_PalettePage> {
  var _query = '';
  var _paletteQuery = '';
  var _series = '全部';
  var _paletteId = BeadPaletteId.mard291;

  BeadPalette get _palette => BeadPalettes.byId(_paletteId);

  Future<void> _savePaletteColors(List<BeadColor> colors, String name) async {
    if (colors.isEmpty) {
      AppNoticeCenter.instance.show(
        '当前筛选没有可保存的色卡',
        kind: AppNoticeKind.warning,
      );
      return;
    }
    try {
      final bytes = await _renderPaletteSheet(colors, name);
      final path = await ExportService().saveImageBytes(bytes, '$name.png');
      AppNoticeCenter.instance.show(
        '色卡大图已保存：$path',
        kind: AppNoticeKind.success,
      );
    } on Object catch (error) {
      AppNoticeCenter.instance.showError(error, operation: '保存色卡图片');
    }
  }

  void _showAllColors() {
    final palette = _palette;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(
              '${palette.shortName} 全部 ${palette.colors.length} 色预览',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
              IconButton(
                onPressed: () => _savePaletteColors(
                  palette.colors,
                  '${palette.shortName}_全色预览',
                ),
                tooltip: '保存全色预览大图',
                icon: const Icon(Icons.download_rounded),
              ),
            ],
          ),
          body: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 92,
              crossAxisSpacing: 5,
              mainAxisSpacing: 5,
              childAspectRatio: 0.82,
            ),
            itemCount: palette.colors.length,
            itemBuilder: (context, index) {
              final color = palette.colors[index];
              final luminance = color.color.computeLuminance();
              return Tooltip(
                message: '${color.code} · ${color.nameCn} · ${color.hex}',
                child: ColoredBox(
                  color: color.color,
                  child: Center(
                    child: Text(
                      color.code,
                      style: TextStyle(
                        color: luminance > 0.48 ? Colors.black : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final visiblePalettes = BeadPalettes.all
        .where((item) => item.matchesQuery(_paletteQuery))
        .toList(growable: false);
    final colors = palette.colors.where((color) {
      final seriesMatches = _series == '全部' || color.series == _series;
      final q = _query.trim().toLowerCase();
      return seriesMatches && color.matchesQuery(q);
    }).toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              palette.displayName,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              palette.description,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showAllColors,
            icon: const Icon(Icons.apps_rounded),
            tooltip: '一次预览全部色块',
          ),
          PopupMenuButton<String>(
            tooltip: '保存色卡到本地',
            onSelected: (value) {
              if (value == 'series') {
                final selected = _series == '全部'
                    ? palette.colors
                    : palette.colors
                          .where((color) => color.series == _series)
                          .toList();
                _savePaletteColors(selected, '${palette.shortName}_$_series系列');
              }
              if (value == 'all') {
                _savePaletteColors(palette.colors, '${palette.shortName}_全色卡');
              }
              if (value == 'visible') {
                _savePaletteColors(colors, '${palette.shortName}_当前筛选');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'visible', child: Text('批量保存当前筛选')),
              PopupMenuItem(value: 'series', child: Text('保存当前系列')),
              PopupMenuItem(value: 'all', child: Text('保存全部色卡')),
            ],
            icon: const Icon(Icons.save_alt_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: TextField(
              onChanged: (value) => setState(() => _paletteQuery = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.manage_search_rounded),
                hintText: '模糊搜索拼豆品牌或系列',
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
              scrollDirection: Axis.horizontal,
              itemCount: visiblePalettes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final item = visiblePalettes[index];
                return ChoiceChip(
                  label: Text('${item.shortName} ${item.colors.length}'),
                  selected: item.id == _paletteId,
                  onSelected: (_) => setState(() {
                    _paletteId = item.id;
                    _series = '全部';
                  }),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 5, 18, 10),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索色号或颜色名称',
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              itemCount: palette.seriesNames.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final value = index == 0
                    ? '全部'
                    : palette.seriesNames.keys.elementAt(index - 1);
                return ChoiceChip(
                  label: Text(
                    value == '全部' ? value : palette.seriesNames[value] ?? value,
                  ),
                  selected: _series == value,
                  labelStyle: TextStyle(
                    color: _series == value
                        ? AppColors.coralDark
                        : AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  checkmarkColor: AppColors.coralDark,
                  onSelected: (_) => setState(() => _series = value),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                crossAxisSpacing: 9,
                mainAxisSpacing: 9,
                childAspectRatio: 0.88,
              ),
              itemCount: colors.length,
              itemBuilder: (context, index) => _ColorCard(
                color: colors[index],
                onSave: () => _savePaletteColors([
                  colors[index],
                ], '${colors[index].brand}_${colors[index].code}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorCard extends StatelessWidget {
  const _ColorCard({required this.color, required this.onSave});
  final BeadColor color;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onDoubleTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${color.code} · ${color.nameCn}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: color.color,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.black12),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${color.brand} · ${color.code}\n${color.hex} · ${color.nameEn}',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.pop(context);
                onSave();
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('保存本色卡'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black12),
                    boxShadow: [
                      BoxShadow(
                        color: color.color.withValues(alpha: 0.34),
                        blurRadius: 9,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: color.color.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Text(
              color.code,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            Text(
              color.nameCn,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
            Text(
              color.hex,
              style: const TextStyle(fontSize: 9, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<Uint8List> _renderPaletteSheet(
  List<BeadColor> colors,
  String title,
) async {
  const columns = 5;
  const tileWidth = 190.0;
  const tileHeight = 122.0;
  const header = 82.0;
  final rows = (colors.length / columns).ceil();
  final width = (columns * tileWidth).round();
  final height = (header + rows * tileHeight).round();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawColor(const Color(0xFFF7F5F1), BlendMode.src);

  void text(
    String value,
    Offset offset, {
    required Color color,
    double size = 22,
    FontWeight weight = FontWeight.w700,
    double maxWidth = tileWidth - 20,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  text(
    title,
    const Offset(20, 18),
    color: const Color(0xFF292321),
    size: 31,
    weight: FontWeight.w900,
    maxWidth: width - 40,
  );
  text(
    '${colors.length} 色 · 可保存全系列与单个色号',
    const Offset(20, 53),
    color: const Color(0xFF6E625D),
    size: 16,
    maxWidth: width - 40,
  );
  for (var index = 0; index < colors.length; index++) {
    final color = colors[index];
    final column = index % columns;
    final row = index ~/ columns;
    final rect = Rect.fromLTWH(
      column * tileWidth,
      header + row * tileHeight,
      tileWidth,
      tileHeight,
    );
    canvas.drawRect(rect, Paint()..color = color.color);
    canvas.drawRect(
      rect.deflate(.5),
      Paint()
        ..color = Colors.black.withValues(alpha: .18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final foreground = color.color.computeLuminance() > .46
        ? Colors.black
        : Colors.white;
    text(
      color.code,
      Offset(rect.left + 10, rect.top + 11),
      color: foreground,
      size: 26,
      weight: FontWeight.w900,
    );
    text(
      color.nameCn,
      Offset(rect.left + 10, rect.top + 45),
      color: foreground,
      size: 17,
    );
    text(
      '${color.series} · ${color.hex}',
      Offset(rect.left + 10, rect.top + 75),
      color: foreground,
      size: 14,
    );
    text(
      color.brand,
      Offset(rect.left + 10, rect.top + 96),
      color: foreground.withValues(alpha: .85),
      size: 12,
    );
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('无法生成色卡图片');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

String _colorHex(Color color) =>
    '#${((color.toARGB32() >> 16) & 0xFF).toRadixString(16).padLeft(2, '0')}'
            '${((color.toARGB32() >> 8) & 0xFF).toRadixString(16).padLeft(2, '0')}'
            '${(color.toARGB32() & 0xFF).toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();

int _colorChannel(Color color, int shift) => (color.toARGB32() >> shift) & 0xFF;

class _ProfilePage extends StatelessWidget {
  const _ProfilePage();

  Future<void> _chooseLanguage(BuildContext context) async {
    final selected = await showDialog<Locale>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.text(context, 'chooseLanguage')),
        content: SizedBox(
          width: 360,
          child: RadioGroup<Locale>(
            groupValue: AppSettings.instance.locale,
            onChanged: (value) => Navigator.pop(context, value),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final locale in supportedAppLocales)
                  RadioListTile<Locale>(
                    value: locale,
                    title: Text(AppStrings.localeName(locale)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.text(context, 'cancel')),
          ),
        ],
      ),
    );
    if (selected != null) await AppSettings.instance.setLocale(selected);
  }

  Future<void> _exportDeviceBackup(BuildContext context) async {
    final selected = <DeviceBackupSection>{...DeviceBackupSection.values};
    final selection = await showDialog<DeviceBackupSelection>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('选择换机备份内容'),
          content: SizedBox(
            width: 380,
            child: ListView(
              shrinkWrap: true,
              children: [
                CheckboxListTile(
                  value: selected.length == DeviceBackupSection.values.length,
                  tristate: true,
                  title: const Text('全部导出'),
                  onChanged: (value) => setDialogState(() {
                    selected.clear();
                    if (value == true) {
                      selected.addAll(DeviceBackupSection.values);
                    }
                  }),
                ),
                const Divider(),
                for (final section in DeviceBackupSection.values)
                  CheckboxListTile(
                    value: selected.contains(section),
                    title: Text(section.label),
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        selected.add(section);
                      } else {
                        selected.remove(section);
                      }
                    }),
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
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      DeviceBackupSelection({...selected}),
                    ),
              child: const Text('开始导出'),
            ),
          ],
        ),
      ),
    );
    if (selection == null || !context.mounted) return;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 18),
              Expanded(child: Text('正在收集全部作品、设置和历史记录…')),
            ],
          ),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    try {
      await const DeviceBackupService().shareBackup(selection: selection);
    } on Object catch (error) {
      if (context.mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('换机备份导出失败：$error')),
        );
      }
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _importDeviceBackup(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入换机备份？'),
        content: const Text(
          '备份内的作品、收藏、画板、回收站、处理历史、合集设置和本地音乐将恢复到本机；同名文件和设置会以备份内容为准。API 密钥受系统安全存储保护，需要在新手机重新填写。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('选择备份并导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final result = await const DeviceBackupService().pickAndImport();
      if (result == null || !context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: Colors.green),
          title: const Text('换机数据已恢复'),
          content: Text(
            '已恢复 ${result.files} 个数据文件和 ${result.preferences} 项设置。软件将安全退出，请重新打开后使用全部恢复内容。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('重新打开后生效'),
            ),
          ],
        ),
      );
      await SystemNavigator.pop();
    } on Object catch (error) {
      if (context.mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('换机备份导入失败：$error')),
        );
      }
    }
  }

  Future<void> _factoryReset(BuildContext context) async {
    const phrase = '我已经确认恢复出厂的风险';
    final controller = TextEditingController();
    var matches = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFB3261E),
          ),
          title: const Text('恢复出厂设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '此操作会永久清空：全部作品与收藏、回收站、画板草稿、用户上传图及分类、处理任务与历史、AI 聊天/生成历史/用量统计、本地音乐列表、界面和 API 配置（包括安全存储中的密钥）。完成后软件与新安装状态一致，无法撤销。',
                  style: TextStyle(height: 1.55, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                const Text('请输入以下文字确认：'),
                const SelectableText(
                  phrase,
                  style: TextStyle(
                    color: Color(0xFFB3261E),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '风险确认文字'),
                  onChanged: (value) =>
                      setDialogState(() => matches = value.trim() == phrase),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      controller.text = phrase;
                      controller.selection = const TextSelection.collapsed(
                        offset: phrase.length,
                      );
                      setDialogState(() => matches = true);
                    },
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('一键填写'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: matches
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB3261E),
              ),
              child: const Text('执行恢复出厂'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true || !context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('正在安全清空全部本机数据…')),
          ],
        ),
      ),
    );
    try {
      await const FactoryResetService().reset();
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      await SystemNavigator.pop();
    } on Object catch (error) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      AppNoticeCenter.instance.showError(error, operation: '恢复出厂设置');
    }
  }

  Future<void> _contactAuthor(
    BuildContext context, {
    required String value,
    required String appUrl,
    required String appName,
  }) async {
    await Clipboard.setData(ClipboardData(text: value));
    var opened = false;
    try {
      opened =
          await const MethodChannel(
            'com.xuan.bead_ai_designer/media',
          ).invokeMethod<bool>('openExternalUrl', {'url': appUrl}) ??
          false;
    } on Object {
      opened = false;
    }
    AppNoticeCenter.instance.show(
      opened
          ? '已复制 $value，并为你打开$appName，请粘贴或搜索后添加作者。'
          : '已复制 $value。未检测到$appName，请打开$appName搜索并添加作者。',
      kind: opened ? AppNoticeKind.success : AppNoticeKind.warning,
    );
  }

  Future<void> _showAppearance(BuildContext context) async {
    var red = _colorChannel(AppSettings.instance.accent, 16);
    var green = _colorChannel(AppSettings.instance.accent, 8);
    var blue = _colorChannel(AppSettings.instance.accent, 0);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final color = Color.fromARGB(255, red, green, blue);
          void update() {
            setDialogState(() {});
            unawaited(
              AppSettings.instance.setAccent(
                Color.fromARGB(255, red, green, blue),
              ),
            );
          }

          return AlertDialog(
            title: const Text('界面风格'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 72,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '#${red.toRadixString(16).padLeft(2, '0')}${green.toRadixString(16).padLeft(2, '0')}${blue.toRadixString(16).padLeft(2, '0')}'
                          .toUpperCase(),
                      style: TextStyle(
                        color: color.computeLuminance() > 0.45
                            ? Colors.black
                            : Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RgbSlider(
                    label: 'R',
                    value: red,
                    color: Colors.red,
                    onChanged: (value) {
                      red = value;
                      update();
                    },
                  ),
                  _RgbSlider(
                    label: 'G',
                    value: green,
                    color: Colors.green,
                    onChanged: (value) {
                      green = value;
                      update();
                    },
                  ),
                  _RgbSlider(
                    label: 'B',
                    value: blue,
                    color: Colors.blue,
                    onChanged: (value) {
                      blue = value;
                      update();
                    },
                  ),
                  const Divider(),
                  const Text(
                    '拖动滑块时会立即应用并自动保存；界面会自动调整明暗，避免浅色导致文字看不清。',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: AppSettings.instance.soundEnabled,
                    onChanged: (value) {
                      setDialogState(() {});
                      unawaited(AppSettings.instance.setSoundEnabled(value));
                    },
                    title: const Text(
                      '按钮点击声音',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text('遵循设备媒体音量，可在下方选择十种内置音效'),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('clickSoundSelector'),
                    initialValue: AppSettings.instance.clickSoundId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '经典按钮音效（选择后立即试听）',
                      prefixIcon: Icon(Icons.music_note_rounded),
                    ),
                    items: [
                      for (final option in ClickSoundService.options)
                        DropdownMenuItem(
                          value: option.id,
                          child: Text(
                            '${option.label} · ${option.description}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      unawaited(AppSettings.instance.setClickSoundId(value));
                      unawaited(
                        ClickSoundService.instance.play(
                          soundId: value,
                          force: true,
                        ),
                      );
                      setDialogState(() {});
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  red = 233;
                  green = 99;
                  blue = 84;
                  update();
                },
                child: const Text('恢复默认'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      title: Text(
        AppStrings.text(context, 'profile'),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.teal, Color(0xFF3FA494)],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white24,
                child: Icon(Icons.blur_circular, color: Colors.white, size: 34),
              ),
              SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '拼豆 AI 设计',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '专业拼豆设计工具 · v2.8.8',
                    style: TextStyle(color: Color(0xFFD9F4EF), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _InfoTile(
          icon: Icons.science_outlined,
          title: '颜色匹配算法',
          subtitle: 'sRGB → CIE LAB → CIEDE2000 最近色',
        ),
        const SizedBox(height: 9),
        Card(
          child: ListTile(
            onTap: () => _chooseLanguage(context),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 7,
            ),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF2E5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.language_rounded,
                color: Colors.deepOrange,
              ),
            ),
            title: Text(
              AppStrings.text(context, 'language'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${AppStrings.localeName(AppSettings.instance.locale)} · '
              '${AppStrings.text(context, 'languageHint')}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
        const SizedBox(height: 9),
        Card(
          child: ExpansionTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF7F2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.phone_android_rounded,
                color: AppColors.teal,
              ),
            ),
            title: const Text(
              '一键换机备份',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('完整导出或恢复作品、配置、画板、回收站与历史'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _exportDeviceBackup(context),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('一键导出全部数据'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _importDeviceBackup(context),
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  label: const Text('一键导入换机备份'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Card(
          child: ListTile(
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const LocalMusicScreen()),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 7,
            ),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.library_music_rounded,
                color: Color(0xFF2E6DA4),
              ),
            ),
            title: const Text(
              '本地音乐',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('批量添加、循环播放与音乐管理'),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
        const SizedBox(height: 9),
        Card(
          child: AnimatedBuilder(
            animation: AppSettings.instance,
            builder: (context, _) => ListTile(
              onTap: () => _showAppearance(context),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 7,
              ),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              title: const Text(
                '界面风格与声音',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '当前 ${_colorHex(AppSettings.instance.accent)} · '
                'RGB ${_colorChannel(AppSettings.instance.accent, 16)},'
                '${_colorChannel(AppSettings.instance.accent, 8)},'
                '${_colorChannel(AppSettings.instance.accent, 0)} · '
                '声音${AppSettings.instance.soundEnabled ? '开' : '关'}'
                ' · ${ClickSoundService.optionFor(AppSettings.instance.clickSoundId).label}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppSettings.instance.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black12),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Card(
          child: ListTile(
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ApiSettingsScreen()),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 7,
            ),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF7F2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.api_rounded, color: AppColors.teal),
            ),
            title: const Text(
              'API 设置',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('服务地址、密钥、模型与连接测试'),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
        const SizedBox(height: 9),
        Card(
          child: ListTile(
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => const SoftwareAnnouncementScreen(),
              ),
            ),
            leading: const Icon(
              Icons.campaign_outlined,
              color: AppColors.coral,
            ),
            title: const Text(
              '软件公告与 AI 兼容清单',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('已实现协议、模型家族及图片/视频中转条件'),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
        const SizedBox(height: 9),
        Card(
          child: ListTile(
            onTap: () => _factoryReset(context),
            leading: const Icon(
              Icons.restart_alt_rounded,
              color: Color(0xFFB3261E),
            ),
            title: const Text(
              '一键恢复出厂设置',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFFB3261E),
              ),
            ),
            subtitle: const Text('永久清空所有配置、作品和记录，恢复新安装状态'),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
        const SizedBox(height: 9),
        const _InfoTile(
          icon: Icons.shield_outlined,
          title: '隐私保护',
          subtitle: '核心转换在本机完成，不上传你的照片',
        ),
        const SizedBox(height: 9),
        const _InfoTile(
          icon: Icons.palette_outlined,
          title: '色卡数据说明',
          subtitle: 'Artkal、MARD、COCO、Perler、Hama 多品牌色卡；实体材料建议同批次校准',
        ),
        const SizedBox(height: 9),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.contact_support_outlined, color: AppColors.teal),
                    SizedBox(width: 9),
                    Text(
                      '联系作者',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                const Text(
                  '欢迎交流拼豆创作与软件使用心得。如果你发现问题、希望优化某项功能，或有新的设计建议，都可以联系作者共同学习交流。点击下方联系方式会先复制账号，再尝试打开对应应用。',
                  style: TextStyle(height: 1.55),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Text('QQ')),
                  title: const Text('作者 QQ'),
                  subtitle: const SelectableText('2590813506'),
                  trailing: const Icon(Icons.copy_rounded),
                  onTap: () => _contactAuthor(
                    context,
                    value: '2590813506',
                    appUrl: 'mqqwpa://im/chat?chat_type=wpa&uin=2590813506',
                    appName: 'QQ',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Text('微信')),
                  title: const Text('作者微信'),
                  subtitle: const SelectableText('love_020804'),
                  trailing: const Icon(Icons.copy_rounded),
                  onTap: () => _contactAuthor(
                    context,
                    value: 'love_020804',
                    appUrl: 'weixin://',
                    appName: '微信',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(
                  Icons.copyright_rounded,
                  color: AppColors.coral,
                  size: 30,
                ),
                const SizedBox(height: 10),
                Text(
                  '版权归xuan所有',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                const Text(
                  'Copyright © 2026 xuan\nAll rights reserved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _RgbSlider extends StatelessWidget {
  const _RgbSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 24,
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ),
      Expanded(
        child: Slider(
          value: value.toDouble(),
          min: 0,
          max: 255,
          divisions: 255,
          activeColor: color,
          onChanged: (next) => onChanged(next.round()),
        ),
      ),
      SizedBox(width: 32, child: Text('$value', textAlign: TextAlign.right)),
    ],
  );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.peach,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: AppColors.coral),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
    ),
  );
}
