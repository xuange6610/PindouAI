import 'dart:io';

import 'package:flutter/material.dart';

import '../services/ai_design_history.dart';
import '../services/ai_design_styles.dart';
import '../services/app_notice_center.dart';
import '../theme/app_theme.dart';

class AiDesignHistoryScreen extends StatefulWidget {
  const AiDesignHistoryScreen({
    super.key,
    this.store = const AiDesignHistoryStore(),
  });

  final AiDesignHistoryStore store;

  @override
  State<AiDesignHistoryScreen> createState() => _AiDesignHistoryScreenState();
}

class _AiDesignHistoryScreenState extends State<AiDesignHistoryScreen> {
  var _entries = <AiDesignHistoryEntry>[];
  final _selected = <String>{};
  var _loading = true;
  var _managing = false;

  bool get _allSelected =>
      _entries.isNotEmpty && _selected.length == _entries.length;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final entries = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _selected.removeWhere((id) => !_entries.any((entry) => entry.id == id));
      _loading = false;
    });
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_entries.map((entry) => entry.id));
      }
    });
  }

  Future<bool> _confirmDelete({
    required int count,
    required bool permanently,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            permanently
                ? Icons.delete_forever_rounded
                : Icons.delete_sweep_outlined,
          ),
          title: Text(permanently ? '永久删除 $count 条记录？' : '删除 $count 条记录？'),
          content: Text(
            permanently ? '记录和对应本地图片将永久删除，无法恢复。' : '记录会进入已删除状态，之后仍可恢复或永久清除。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(permanently ? '永久删除' : '确认删除'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _deleteSelected({required bool permanently}) async {
    if (_selected.isEmpty ||
        !await _confirmDelete(
          count: _selected.length,
          permanently: permanently,
        )) {
      return;
    }
    if (permanently) {
      await widget.store.deletePermanently(_selected);
    } else {
      await widget.store.deleteMany(_selected);
    }
    _selected.clear();
    await _reload();
  }

  Future<void> _deleteOne(
    AiDesignHistoryEntry entry, {
    required bool permanently,
  }) async {
    if (!await _confirmDelete(count: 1, permanently: permanently)) return;
    if (permanently) {
      await widget.store.deletePermanently([entry.id]);
    } else {
      await widget.store.delete(entry.id);
    }
    await _reload();
  }

  Future<void> _restore(AiDesignHistoryEntry entry) async {
    await widget.store.restore(entry.id);
    await _reload();
  }

  Future<void> _preview(AiDesignHistoryEntry entry) async {
    final path = entry.imagePath;
    if (path == null || !await File(path).exists() || !mounted) {
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          const SnackBar(content: Text('历史图片文件已不存在')),
        );
      }
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(entry.prompt, maxLines: 1),
          ),
          body: InteractiveViewer(
            minScale: 0.25,
            maxScale: 12,
            child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        _managing ? '已选择 ${_selected.length} 项' : 'AI 生成图片记录',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        if (_managing)
          TextButton.icon(
            key: const ValueKey('aiHistorySelectAll'),
            onPressed: _toggleAll,
            icon: Icon(
              _allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
            ),
            label: Text(_allSelected ? '取消全选' : '全选'),
          ),
        TextButton(
          onPressed: _entries.isEmpty
              ? null
              : () => setState(() {
                  _managing = !_managing;
                  _selected.clear();
                }),
          child: Text(_managing ? '完成' : '管理'),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _entries.isEmpty
        ? const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_motion_outlined,
                  size: 52,
                  color: AppColors.muted,
                ),
                SizedBox(height: 10),
                Text('还没有 AI 制图记录'),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
            itemCount: _entries.length,
            itemBuilder: (context, index) {
              final entry = _entries[index];
              final style = AiBeadDesignStyles.byId(entry.styleId ?? '');
              final sourceLabel = switch (entry.styleId) {
                'ai_chat' => 'AI 聊天',
                'color_recognition' => '图片色号识别',
                _ => style.title,
              };
              final selected = _selected.contains(entry.id);
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _managing
                      ? () => _toggle(entry.id)
                      : () => _preview(entry),
                  onLongPress: () {
                    if (!_managing) setState(() => _managing = true);
                    _toggle(entry.id);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        if (_managing)
                          Checkbox(
                            value: selected,
                            onChanged: (_) => _toggle(entry.id),
                          ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 88,
                            height: 88,
                            child: entry.imagePath == null
                                ? const ColoredBox(
                                    color: Color(0xFFF0EEEB),
                                    child: Icon(Icons.notes_rounded),
                                  )
                                : Image.file(
                                    File(entry.imagePath!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.prompt,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (entry.isDeleted)
                                    const Text(
                                      '已删除',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$sourceLabel · ${entry.model}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.teal,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                '${entry.createdAt.month}月${entry.createdAt.day}日 '
                                '${entry.createdAt.hour.toString().padLeft(2, '0')}:'
                                '${entry.createdAt.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!_managing)
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'preview') _preview(entry);
                              if (value == 'use') Navigator.pop(context, entry);
                              if (value == 'restore') _restore(entry);
                              if (value == 'delete') {
                                _deleteOne(entry, permanently: false);
                              }
                              if (value == 'permanent') {
                                _deleteOne(entry, permanently: true);
                              }
                            },
                            itemBuilder: (_) => [
                              if (entry.hasImage)
                                const PopupMenuItem(
                                  value: 'preview',
                                  child: Text('打开预览'),
                                ),
                              if (entry.hasImage && !entry.isDeleted)
                                const PopupMenuItem(
                                  value: 'use',
                                  child: Text('回到制图页使用'),
                                ),
                              if (entry.isDeleted)
                                const PopupMenuItem(
                                  value: 'restore',
                                  child: Text('恢复记录'),
                                )
                              else
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除（可恢复）'),
                                ),
                              const PopupMenuItem(
                                value: 'permanent',
                                child: Text('永久删除'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
    bottomNavigationBar: !_managing
        ? null
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => _deleteSelected(permanently: false),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('批量删除'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => _deleteSelected(permanently: true),
                      icon: const Icon(Icons.delete_forever_rounded),
                      label: const Text('永久删除'),
                    ),
                  ),
                ],
              ),
            ),
          ),
  );
}
