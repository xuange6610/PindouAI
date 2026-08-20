import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceBackupResult {
  const DeviceBackupResult({required this.files, required this.preferences});

  final int files;
  final int preferences;
}

enum DeviceBackupSection {
  works('作品'),
  trash('回收站'),
  processing('处理历史'),
  customBoard('自定义画板'),
  collection('图纸合集'),
  aiHistory('AI 记录'),
  music('本地音乐'),
  settings('软件设置');

  const DeviceBackupSection(this.label);
  final String label;
}

class DeviceBackupSelection {
  const DeviceBackupSelection(this.sections);

  static const all = DeviceBackupSelection({...DeviceBackupSection.values});
  final Set<DeviceBackupSection> sections;

  bool get isEmpty => sections.isEmpty;
  bool includes(DeviceBackupSection section) => sections.contains(section);
}

class DeviceBackupService {
  const DeviceBackupService();

  static const _format = 'bead-ai-device-backup';
  static const _version = 2;
  static const _mediaChannel = MethodChannel(
    'com.xuan.bead_ai_designer/media',
  );

  Future<File> createBackup({
    DeviceBackupSelection selection = DeviceBackupSelection.all,
  }) async {
    if (selection.isEmpty) throw ArgumentError('请至少选择一项备份内容');
    final documents = await getApplicationDocumentsDirectory();
    final entries = <Map<String, Object?>>[];
    if (await documents.exists()) {
      await for (final entity in documents.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = _relativePath(documents.path, entity.path);
        if (!_isSafeRelativePath(relative)) continue;
        if (!selection.includes(_sectionForPath(relative))) continue;
        entries.add({
          'path': relative.replaceAll(Platform.pathSeparator, '/'),
          'modifiedAt': (await entity.lastModified()).toIso8601String(),
          'data': base64Encode(await entity.readAsBytes()),
        });
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final preferences = <String, Object?>{};
    for (final key in prefs.getKeys()) {
      if (_isSecretPreference(key)) continue;
      if (!selection.includes(_sectionForPreference(key))) continue;
      final value = prefs.get(key);
      if (value is bool || value is int || value is double || value is String) {
        preferences[key] = value;
      } else if (value is List<String>) {
        preferences[key] = value;
      }
    }
    final payload = utf8.encode(
      jsonEncode({
        'format': _format,
        'version': _version,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'sections': selection.sections.map((section) => section.name).toList(),
        'documentsRoot': documents.path,
        'preferences': preferences,
        'files': entries,
      }),
    );
    final compressed = gzip.encode(payload);
    final temporary = await getTemporaryDirectory();
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final target = File(
      '${temporary.path}${Platform.pathSeparator}拼豆AI_一键换机_$stamp.beaddevice',
    );
    return target.writeAsBytes(compressed, flush: true);
  }

  Future<void> shareBackup({
    DeviceBackupSelection selection = DeviceBackupSelection.all,
  }) async {
    final file = await createBackup(selection: selection);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/octet-stream')],
        text: '拼豆 AI 一键换机备份。请妥善保管，文件中可能包含你的作品和个人设置。',
      ),
    );
  }

  Future<DeviceBackupResult?> pickAndImport() async {
    Uint8List? bytes;
    if (Platform.isAndroid) {
      bytes = await _mediaChannel.invokeMethod<Uint8List>('pickBackup');
    } else {
      final selected = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: '拼豆 AI 换机备份', extensions: ['beaddevice']),
        ],
      );
      if (selected != null) bytes = await selected.readAsBytes();
    }
    if (bytes == null) return null;
    return importBytes(bytes);
  }

  Future<DeviceBackupResult> importBytes(Uint8List bytes) async {
    Map<String, dynamic> payload;
    try {
      payload =
          jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    } on Object catch (error) {
      throw FormatException('备份文件已损坏或格式不正确：$error');
    }
    if (payload['format'] != _format || payload['version'] != _version) {
      throw const FormatException('不是受支持的拼豆 AI 换机备份');
    }
    final documents = await getApplicationDocumentsDirectory();
    final oldRoot = payload['documentsRoot'] as String? ?? '';
    var restoredFiles = 0;
    for (final raw in payload['files'] as List? ?? const []) {
      final entry = (raw as Map).cast<String, dynamic>();
      final relative = (entry['path'] as String? ?? '').replaceAll(
        '/',
        Platform.pathSeparator,
      );
      if (!_isSafeRelativePath(relative)) {
        throw FormatException('备份中包含不安全的文件路径：$relative');
      }
      final file = File('${documents.path}${Platform.pathSeparator}$relative');
      await file.parent.create(recursive: true);
      var data = base64Decode(entry['data'] as String);
      data = _rewriteTextPaths(data, oldRoot, documents.path);
      await file.writeAsBytes(data, flush: true);
      final modified = DateTime.tryParse(entry['modifiedAt'] as String? ?? '');
      if (modified != null) await file.setLastModified(modified.toLocal());
      restoredFiles++;
    }
    final prefs = await SharedPreferences.getInstance();
    var restoredPreferences = 0;
    final rawPreferences =
        (payload['preferences'] as Map? ?? const <String, Object?>{})
            .cast<String, dynamic>();
    for (final entry in rawPreferences.entries) {
      if (_isSecretPreference(entry.key)) continue;
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      } else if (value is double) {
        await prefs.setDouble(entry.key, value);
      } else if (value is String) {
        await prefs.setString(
          entry.key,
          oldRoot.isEmpty ? value : value.replaceAll(oldRoot, documents.path),
        );
      } else if (value is List) {
        await prefs.setStringList(
          entry.key,
          value
              .map((item) => item.toString())
              .map(
                (item) => oldRoot.isEmpty
                    ? item
                    : item.replaceAll(oldRoot, documents.path),
              )
              .toList(),
        );
      } else {
        continue;
      }
      restoredPreferences++;
    }
    return DeviceBackupResult(
      files: restoredFiles,
      preferences: restoredPreferences,
    );
  }

  static bool _isSecretPreference(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('api_key') ||
        normalized.contains('apikey') ||
        normalized.contains('access_token') ||
        normalized.contains('secret');
  }

  static DeviceBackupSection _sectionForPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('patterns/')) return DeviceBackupSection.works;
    if (normalized.startsWith('patterns_trash/')) {
      return DeviceBackupSection.trash;
    }
    if (normalized.startsWith('processing_tasks/')) {
      return DeviceBackupSection.processing;
    }
    if (normalized.startsWith('custom_board')) {
      return DeviceBackupSection.customBoard;
    }
    if (normalized.startsWith('collection_uploads')) {
      return DeviceBackupSection.collection;
    }
    if (normalized.startsWith('ai_')) {
      return DeviceBackupSection.aiHistory;
    }
    if (normalized.startsWith('local_music')) return DeviceBackupSection.music;
    return DeviceBackupSection.settings;
  }

  static DeviceBackupSection _sectionForPreference(String key) {
    final normalized = key.toLowerCase();
    if (normalized.startsWith('collection_')) {
      return DeviceBackupSection.collection;
    }
    if (normalized.startsWith('local_music')) return DeviceBackupSection.music;
    if (normalized.startsWith('ai_')) return DeviceBackupSection.aiHistory;
    return DeviceBackupSection.settings;
  }

  static bool _isSafeRelativePath(String value) {
    if (value.isEmpty) return false;
    final normalized = value.replaceAll('\\', '/');
    if (normalized.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(value)) {
      return false;
    }
    return normalized
        .split('/')
        .every(
          (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
        );
  }

  static String _relativePath(String root, String target) {
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    if (!target.startsWith(prefix)) return '';
    return target.substring(prefix.length);
  }

  static Uint8List _rewriteTextPaths(
    Uint8List data,
    String oldRoot,
    String newRoot,
  ) {
    if (oldRoot.isEmpty || oldRoot == newRoot) return data;
    try {
      final text = utf8.decode(data);
      if (!text.contains(oldRoot)) return data;
      return Uint8List.fromList(utf8.encode(text.replaceAll(oldRoot, newRoot)));
    } on FormatException {
      return data;
    }
  }
}
