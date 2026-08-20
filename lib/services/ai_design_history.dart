import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class AiDesignHistoryEntry {
  const AiDesignHistoryEntry({
    required this.id,
    required this.prompt,
    required this.content,
    required this.model,
    required this.createdAt,
    this.imagePath,
    this.deletedAt,
    this.styleId,
  });

  final String id;
  final String prompt;
  final String content;
  final String model;
  final DateTime createdAt;
  final String? imagePath;
  final DateTime? deletedAt;
  final String? styleId;

  bool get hasImage => imagePath != null;
  bool get isDeleted => deletedAt != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'prompt': prompt,
    'content': content,
    'model': model,
    'createdAt': createdAt.toIso8601String(),
    if (imagePath != null) 'imagePath': imagePath,
    if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
    if (styleId != null) 'styleId': styleId,
  };

  factory AiDesignHistoryEntry.fromJson(Map<String, dynamic> json) =>
      AiDesignHistoryEntry(
        id: json['id'] as String,
        prompt: json['prompt'] as String? ?? '',
        content: json['content'] as String? ?? '',
        model: json['model'] as String? ?? 'gpt-5.6-sol',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        imagePath: json['imagePath'] as String?,
        deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
        styleId: json['styleId'] as String?,
      );
}

class AiDesignHistoryStore {
  const AiDesignHistoryStore();

  static Future<void> _mutationQueue = Future<void>.value();

  Future<File> _file() async {
    final documents = await getApplicationDocumentsDirectory();
    return File(
      '${documents.path}${Platform.pathSeparator}ai_design_history.json',
    );
  }

  Future<List<AiDesignHistoryEntry>> load() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      return list
          .cast<Map<String, dynamic>>()
          .map(AiDesignHistoryEntry.fromJson)
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> save(AiDesignHistoryEntry entry) =>
      _mutate(() => _saveUnlocked(entry));

  Future<void> _saveUnlocked(AiDesignHistoryEntry entry) async {
    final entries = await load();
    entries.removeWhere((item) => item.id == entry.id);
    entries.insert(0, entry);
    final file = await _file();
    await file.writeAsString(
      jsonEncode(entries.take(100).map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<AiDesignHistoryEntry> saveImage(
    AiDesignHistoryEntry entry,
    Uint8List bytes,
  ) => _mutate(() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}ai_design_images',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    final path = '${directory.path}${Platform.pathSeparator}${entry.id}.png';
    await File(path).writeAsBytes(bytes, flush: true);
    final imageEntry = AiDesignHistoryEntry(
      id: entry.id,
      prompt: entry.prompt,
      content: entry.content,
      model: entry.model,
      createdAt: entry.createdAt,
      imagePath: path,
      styleId: entry.styleId,
    );
    await _saveUnlocked(imageEntry);
    return imageEntry;
  });

  Future<void> delete(String id) async {
    await deleteMany([id]);
  }

  Future<void> deleteMany(Iterable<String> ids) => _mutate(() async {
    final deleting = ids.toSet();
    if (deleting.isEmpty) return;
    final entries = await load();
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      if (!deleting.contains(entry.id)) continue;
      entries[index] = AiDesignHistoryEntry(
        id: entry.id,
        prompt: entry.prompt,
        content: entry.content,
        model: entry.model,
        createdAt: entry.createdAt,
        imagePath: entry.imagePath,
        deletedAt: DateTime.now(),
        styleId: entry.styleId,
      );
    }
    await _write(entries);
  });

  Future<void> deletePermanently(Iterable<String> ids) => _mutate(() async {
    final deleting = ids.toSet();
    if (deleting.isEmpty) return;
    final entries = await load();
    final documents = await getApplicationDocumentsDirectory();
    final imageDirectory = Directory(
      '${documents.path}${Platform.pathSeparator}ai_design_images',
    ).absolute.path;
    for (final entry in entries.where((item) => deleting.contains(item.id))) {
      final path = entry.imagePath;
      if (path == null) continue;
      final file = File(path).absolute;
      if (file.parent.path == imageDirectory && await file.exists()) {
        await file.delete();
      }
    }
    entries.removeWhere((item) => deleting.contains(item.id));
    await _write(entries);
  });

  Future<void> _write(List<AiDesignHistoryEntry> entries) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(entries.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> restore(String id) => _mutate(() async {
    final entries = await load();
    final index = entries.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final entry = entries[index];
    entries[index] = AiDesignHistoryEntry(
      id: entry.id,
      prompt: entry.prompt,
      content: entry.content,
      model: entry.model,
      createdAt: entry.createdAt,
      imagePath: entry.imagePath,
      styleId: entry.styleId,
    );
    await _write(entries);
  });

  Future<T> _mutate<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _mutationQueue = _mutationQueue.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }
}
