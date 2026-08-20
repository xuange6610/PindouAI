import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalMusicTrack {
  const LocalMusicTrack({
    required this.id,
    required this.name,
    required this.path,
  });

  final String id;
  final String name;
  final String path;

  Map<String, String> toJson() => {'id': id, 'name': name, 'path': path};

  factory LocalMusicTrack.fromJson(Map<String, dynamic> json) =>
      LocalMusicTrack(
        id: json['id'] as String,
        name: json['name'] as String,
        path: json['path'] as String,
      );
}

enum LocalMusicLoopMode { list, single, shuffle }

class LocalMusicService extends ChangeNotifier {
  LocalMusicService._() {
    _player.onPlayerComplete.listen((_) {
      unawaited(_advanceAfterComplete());
    });
    _player.onPlayerStateChanged.listen((state) {
      _playing = state == PlayerState.playing;
      notifyListeners();
    });
  }

  static final LocalMusicService instance = LocalMusicService._();
  static const _playlistKey = 'local_music_playlist';
  static const _indexKey = 'local_music_index';
  static const _loopModeKey = 'local_music_loop_mode';

  final AudioPlayer _player = AudioPlayer();
  final List<LocalMusicTrack> _tracks = [];
  Future<void>? _initializing;
  int _currentIndex = 0;
  bool _playing = false;
  String? _lastError;
  LocalMusicLoopMode _loopMode = LocalMusicLoopMode.list;

  List<LocalMusicTrack> get tracks => List.unmodifiable(_tracks);
  int get currentIndex => _currentIndex;
  bool get isPlaying => _playing;
  String? get lastError => _lastError;
  LocalMusicLoopMode get loopMode => _loopMode;
  LocalMusicTrack? get currentTrack => _tracks.isEmpty
      ? null
      : _tracks[_currentIndex.clamp(0, _tracks.length - 1)];

  Future<void> initialize({bool autoPlay = true}) =>
      _initializing ??= _load(autoPlay: autoPlay);

  Future<void> _load({required bool autoPlay}) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_playlistKey);
    if (encoded != null) {
      try {
        for (final raw in jsonDecode(encoded) as List) {
          final track = LocalMusicTrack.fromJson(
            (raw as Map).cast<String, dynamic>(),
          );
          if (await File(track.path).exists()) _tracks.add(track);
        }
      } on Object catch (error) {
        debugPrint('Unable to load local music playlist: $error');
      }
    }
    _currentIndex = (prefs.getInt(_indexKey) ?? 0).clamp(
      0,
      _tracks.isEmpty ? 0 : _tracks.length - 1,
    );
    _loopMode = LocalMusicLoopMode.values.firstWhere(
      (value) => value.name == prefs.getString(_loopModeKey),
      orElse: () => LocalMusicLoopMode.list,
    );
    await _player.setReleaseMode(ReleaseMode.stop);
    notifyListeners();
    if (autoPlay && _tracks.isNotEmpty) {
      await _startPlayback(_currentIndex);
    }
  }

  Future<Directory> _musicDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}local_music',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<int> importFiles(List<XFile> files) async {
    await initialize(autoPlay: false);
    if (files.isEmpty) return 0;
    final directory = await _musicDirectory();
    final wasEmpty = _tracks.isEmpty;
    var imported = 0;
    for (final source in files) {
      try {
        final bytes = await source.readAsBytes();
        if (bytes.isEmpty) continue;
        final extension = source.name.contains('.')
            ? '.${source.name.split('.').last}'
            : '';
        final id = '${DateTime.now().microsecondsSinceEpoch}_$imported';
        final target = File(
          '${directory.path}${Platform.pathSeparator}$id$extension',
        );
        await target.writeAsBytes(bytes, flush: true);
        _tracks.add(
          LocalMusicTrack(id: id, name: source.name, path: target.path),
        );
        imported++;
      } on Object catch (error) {
        debugPrint('Unable to import music ${source.name}: $error');
      }
    }
    await _save();
    notifyListeners();
    if (wasEmpty && _tracks.isNotEmpty) await play(0);
    return imported;
  }

  Future<int> importNetworkSource(String source) async {
    await initialize(autoPlay: false);
    final uri = Uri.tryParse(source.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('请输入完整的 HTTP 或 HTTPS 公开音频链接');
    }
    final knownShareHosts = <String>[
      'qq.com',
      'music.163.com',
      'kugou.com',
      'kuwo.cn',
      'miguvideo.com',
      'migu.cn',
      'douyin.com',
      'kuaishou.com',
      'bilibili.com',
      'ximalaya.com',
      'lizhi.fm',
      'qingting.fm',
      '5sing.kugou.com',
      'changba.com',
    ];
    if (knownShareHosts.any((host) => uri.host.endsWith(host)) &&
        !_looksLikeMedia(uri.path)) {
      throw UnsupportedError(
        '该平台分享页需要官方授权或登录，软件不会绕过版权、DRM 或登录限制。请使用平台导出的公开音频直链或公开 M3U 播放列表。',
      );
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('网络服务器返回 ${response.statusCode}', uri: uri);
      }
      final contentType = response.headers.contentType?.mimeType ?? '';
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 300 * 1024 * 1024) {
          throw const HttpException('网络音频超过 300MB，已停止导入');
        }
      }
      if (bytes.isEmpty) throw const HttpException('网络链接返回空文件');
      if (contentType.contains('mpegurl') ||
          uri.path.toLowerCase().endsWith('.m3u')) {
        final urls = utf8
            .decode(bytes, allowMalformed: false)
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where(
              (line) =>
                  line.startsWith('http://') || line.startsWith('https://'),
            )
            .toList();
        var imported = 0;
        for (final entry in urls.take(100)) {
          imported += await importNetworkSource(entry);
        }
        return imported;
      }
      if (!contentType.startsWith('audio/') && !_looksLikeMedia(uri.path)) {
        throw const FormatException('链接不是公开音频文件或 M3U 播放列表');
      }
      final directory = await _musicDirectory();
      final name = _nameFromUri(
        uri,
        response.headers.value('content-disposition'),
      );
      final extension = _extensionFromName(
        name,
        fallback: _extensionFromMime(contentType),
      );
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final target = File(
        '${directory.path}${Platform.pathSeparator}$id$extension',
      );
      await target.writeAsBytes(bytes, flush: true);
      final wasEmpty = _tracks.isEmpty;
      _tracks.add(LocalMusicTrack(id: id, name: name, path: target.path));
      await _save();
      notifyListeners();
      if (wasEmpty) await _startPlayback(0);
      return 1;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> play(int index) async {
    await initialize(autoPlay: false);
    await _startPlayback(index);
  }

  Future<void> _startPlayback(int index) async {
    if (_tracks.isEmpty) return;
    _currentIndex = index.clamp(0, _tracks.length - 1);
    _lastError = null;
    notifyListeners();
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(_tracks[_currentIndex].path));
      await _save();
    } on Object catch (error) {
      _playing = false;
      _lastError = '“${_tracks[_currentIndex].name}”无法播放，设备可能不支持该格式：$error';
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (_tracks.isEmpty) return;
    if (_playing) {
      await _player.pause();
    } else {
      try {
        await _player.resume();
      } on Object {
        await _startPlayback(_currentIndex);
      }
    }
  }

  Future<void> next() => _playRelative(1);
  Future<void> previous() => _playRelative(-1);

  Future<void> setLoopMode(LocalMusicLoopMode value) async {
    _loopMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_loopModeKey, value.name);
    notifyListeners();
  }

  Future<void> _advanceAfterComplete() async {
    try {
      if (_loopMode == LocalMusicLoopMode.single) {
        await _startPlayback(_currentIndex);
      } else if (_loopMode == LocalMusicLoopMode.shuffle) {
        if (_tracks.length < 2) {
          await _startPlayback(_currentIndex);
        } else {
          var next = _currentIndex;
          while (next == _currentIndex) {
            next = Random().nextInt(_tracks.length);
          }
          await _startPlayback(next);
        }
      } else {
        await _playRelative(1);
      }
    } on Object catch (error) {
      _lastError = '自动切歌失败：$error';
      notifyListeners();
    }
  }

  Future<void> _playRelative(int delta) async {
    if (_tracks.isEmpty) return;
    try {
      final nextIndex = (_currentIndex + delta) % _tracks.length < 0
          ? (_currentIndex + delta) % _tracks.length + _tracks.length
          : (_currentIndex + delta) % _tracks.length;
      await play(nextIndex);
    } on Object catch (error) {
      _lastError = '切换音乐失败：$error';
      notifyListeners();
    }
  }

  Future<void> delete(LocalMusicTrack track) async {
    final index = _tracks.indexWhere((value) => value.id == track.id);
    if (index < 0) return;
    final deletingCurrent = index == _currentIndex;
    if (deletingCurrent) await _player.stop();
    _tracks.removeAt(index);
    final file = File(track.path);
    if (await file.exists()) await file.delete();
    if (_tracks.isEmpty) {
      _currentIndex = 0;
      _playing = false;
    } else {
      _currentIndex = _currentIndex.clamp(0, _tracks.length - 1);
    }
    await _save();
    notifyListeners();
    if (deletingCurrent && _tracks.isNotEmpty) await play(_currentIndex);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _playlistKey,
      jsonEncode(_tracks.map((track) => track.toJson()).toList()),
    );
    await prefs.setInt(_indexKey, _currentIndex);
  }

  static bool _looksLikeMedia(String path) => RegExp(
    r'\.(mp3|m4a|aac|wav|flac|ogg|opus|amr|wma)$',
    caseSensitive: false,
  ).hasMatch(path);

  static String _extensionFromMime(String mime) => switch (mime) {
    'audio/mpeg' => '.mp3',
    'audio/mp4' || 'audio/x-m4a' => '.m4a',
    'audio/aac' => '.aac',
    'audio/wav' || 'audio/x-wav' => '.wav',
    'audio/flac' || 'audio/x-flac' => '.flac',
    'audio/ogg' => '.ogg',
    _ => '.mp3',
  };

  static String _extensionFromName(String value, {required String fallback}) {
    final match = RegExp(r'\.[A-Za-z0-9]{1,8}$').firstMatch(value);
    return match?.group(0)?.toLowerCase() ?? fallback;
  }

  static String _nameFromUri(Uri uri, String? disposition) {
    final nameMatch = RegExp(
      r'filename="?([^";]+)',
    ).firstMatch(disposition ?? '');
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final decoded = Uri.decodeComponent(nameMatch?.group(1) ?? last);
    return decoded.trim().isEmpty
        ? '网络音乐_${DateTime.now().millisecondsSinceEpoch}.mp3'
        : decoded;
  }
}
