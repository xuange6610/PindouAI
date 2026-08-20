import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/app_notice_center.dart';
import '../services/local_music_service.dart';
import '../theme/app_theme.dart';

class LocalMusicScreen extends StatefulWidget {
  const LocalMusicScreen({super.key});

  @override
  State<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends State<LocalMusicScreen> {
  final _music = LocalMusicService.instance;
  var _importing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_music.initialize());
  }

  Future<void> _import() async {
    try {
      final files = await openFiles(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: '本地音乐',
            extensions: [
              'mp3',
              'm4a',
              'aac',
              'wav',
              'flac',
              'ogg',
              'opus',
              'amr',
              'wma',
            ],
            mimeTypes: ['audio/*'],
            webWildCards: ['audio/*'],
          ),
        ],
        confirmButtonText: '批量添加音乐',
      );
      if (files.isEmpty || !mounted) return;
      setState(() => _importing = true);
      final count = await _music.importFiles(files);
      if (!mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('已添加 $count 首音乐')),
      );
    } on Object catch (error) {
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('导入本地音乐失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importNetwork() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入网络音乐'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '公开音频或 M3U 播放列表链接',
            hintText: '粘贴 HTTP/HTTPS 公开直链',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty || !mounted) return;
    setState(() => _importing = true);
    try {
      final count = await _music.importNetworkSource(url);
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('已导入 $count 首公开网络音乐')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        AppNoticeCenter.instance.showSnackBar(
          SnackBar(content: Text('网络导入失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _delete(LocalMusicTrack track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本地音乐？'),
        content: Text('“${track.name}”将从应用音乐目录中删除。'),
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
    if (confirmed == true) await _music.delete(track);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _music,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text(
          '本地音乐',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          PopupMenuButton<LocalMusicLoopMode>(
            tooltip: '设置循环模式',
            initialValue: _music.loopMode,
            onSelected: _music.setLoopMode,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: LocalMusicLoopMode.list,
                child: Text('列表循环'),
              ),
              PopupMenuItem(
                value: LocalMusicLoopMode.single,
                child: Text('单曲循环'),
              ),
              PopupMenuItem(
                value: LocalMusicLoopMode.shuffle,
                child: Text('随机播放'),
              ),
            ],
            icon: Icon(switch (_music.loopMode) {
              LocalMusicLoopMode.list => Icons.repeat_rounded,
              LocalMusicLoopMode.single => Icons.repeat_one_rounded,
              LocalMusicLoopMode.shuffle => Icons.shuffle_rounded,
            }),
          ),
          IconButton(
            onPressed: _importing ? null : _importNetwork,
            tooltip: '导入公开网络音乐或 M3U',
            icon: const Icon(Icons.add_link_rounded),
          ),
          IconButton(
            onPressed: _importing ? null : _import,
            tooltip: '批量添加音乐',
            icon: const Icon(Icons.library_music_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
            child: Row(
              children: [
                IconButton.filledTonal(
                  onPressed: _music.tracks.isEmpty ? null : _music.previous,
                  tooltip: '上一首',
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _music.tracks.isEmpty ? null : _music.toggle,
                  tooltip: _music.isPlaying ? '暂停' : '播放',
                  icon: Icon(
                    _music.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _music.tracks.isEmpty ? null : _music.next,
                  tooltip: '下一首',
                  icon: const Icon(Icons.skip_next_rounded),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _music.currentTrack?.name ?? '未添加音乐',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        _music.tracks.isEmpty
                            ? '批量添加本地音乐或公开网络音乐'
                            : '${switch (_music.loopMode) {
                                LocalMusicLoopMode.list => '列表循环',
                                LocalMusicLoopMode.single => '单曲循环',
                                LocalMusicLoopMode.shuffle => '随机播放',
                              }} · 下次启动自动播放',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_importing)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          if (_music.lastError != null)
            MaterialBanner(
              content: Text(_music.lastError!),
              actions: [
                TextButton(onPressed: _music.next, child: const Text('播放下一首')),
              ],
            ),
          const Divider(height: 1),
          Expanded(
            child: _music.tracks.isEmpty
                ? Center(
                    child: FilledButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('批量添加音乐'),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _music.tracks.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final track = _music.tracks[index];
                      final selected = index == _music.currentIndex;
                      return ListTile(
                        leading: Icon(
                          selected && _music.isPlaying
                              ? Icons.graphic_eq_rounded
                              : Icons.music_note_rounded,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: selected ? const Text('正在播放') : null,
                        onTap: () => _music.play(index),
                        trailing: IconButton(
                          onPressed: () => _delete(track),
                          tooltip: '删除音乐',
                          icon: const Icon(Icons.delete_outline_rounded),
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
