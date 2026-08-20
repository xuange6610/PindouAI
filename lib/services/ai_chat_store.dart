import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AiChatAttachment {
  const AiChatAttachment({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String path;
  final String name;
  final String mimeType;
  final int bytes;

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isAudio => mimeType.startsWith('audio/');

  Map<String, Object?> toJson() => {
    'path': path,
    'name': name,
    'mimeType': mimeType,
    'bytes': bytes,
  };

  factory AiChatAttachment.fromJson(Map<String, dynamic> json) =>
      AiChatAttachment(
        path: json['path'] as String? ?? '',
        name: json['name'] as String? ?? '附件',
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        bytes: json['bytes'] as int? ?? 0,
      );
}

class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.attachment,
    this.model,
    this.requestMode,
    this.reasoning = '',
    this.elapsedMs = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalTokens = 0,
  });

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final AiChatAttachment? attachment;
  final String? model;

  /// Capability used for this user request: chat, image, or video.
  /// Older history entries omit it and are inferred by the chat screen.
  final String? requestMode;

  /// Reasoning summary explicitly returned by the provider. This is not
  /// synthesized and may be empty when the selected model does not expose it.
  final String reasoning;
  final int elapsedMs;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    if (attachment != null) 'attachment': attachment!.toJson(),
    if (model != null) 'model': model,
    if (requestMode != null) 'requestMode': requestMode,
    if (reasoning.isNotEmpty) 'reasoning': reasoning,
    if (elapsedMs > 0) 'elapsedMs': elapsedMs,
    if (inputTokens > 0) 'inputTokens': inputTokens,
    if (outputTokens > 0) 'outputTokens': outputTokens,
    if (totalTokens > 0) 'totalTokens': totalTokens,
  };

  factory AiChatMessage.fromJson(Map<String, dynamic> json) => AiChatMessage(
    id: json['id'] as String? ?? '',
    role: json['role'] as String? ?? 'user',
    content: json['content'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    attachment: json['attachment'] is Map
        ? AiChatAttachment.fromJson(
            (json['attachment'] as Map).cast<String, dynamic>(),
          )
        : null,
    model: json['model'] as String?,
    requestMode: json['requestMode'] as String?,
    reasoning:
        json['reasoning'] as String? ?? json['thinking'] as String? ?? '',
    elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
    inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
    outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
    totalTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
  );
}

class AiChatConversation {
  const AiChatConversation({
    required this.id,
    required this.title,
    required this.model,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.note = '',
  });

  final String id;
  final String title;
  final String model;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AiChatMessage> messages;
  final String note;

  AiChatConversation copyWith({
    String? title,
    String? model,
    DateTime? updatedAt,
    List<AiChatMessage>? messages,
    String? note,
  }) => AiChatConversation(
    id: id,
    title: title ?? this.title,
    model: model ?? this.model,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    messages: messages ?? this.messages,
    note: note ?? this.note,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'model': model,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((message) => message.toJson()).toList(),
    if (note.isNotEmpty) 'note': note,
  };

  factory AiChatConversation.fromJson(
    Map<String, dynamic> json,
  ) => AiChatConversation(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '新聊天',
    model: json['model'] as String? ?? 'gpt-5.6-sol',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    messages: (json['messages'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (message) => AiChatMessage.fromJson(message.cast<String, dynamic>()),
        )
        .toList(growable: false),
    note: json['note'] as String? ?? '',
  );
}

class AiChatStore {
  static const maxAttachmentBytes = 20 * 1024 * 1024;
  static const _mediaChannel = MethodChannel(
    'com.xuan.bead_ai_designer/media',
  );

  Future<File> _indexFile() async {
    final documents = await getApplicationDocumentsDirectory();
    return File(
      '${documents.path}${Platform.pathSeparator}ai_chat_conversations.json',
    );
  }

  Future<Directory> _attachmentDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}ai_chat_files',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<List<AiChatConversation>> load() async {
    final file = await _indexFile();
    if (!await file.exists()) return [];
    try {
      final payload = jsonDecode(await file.readAsString()) as List;
      final conversations = payload
          .whereType<Map>()
          .map(
            (value) =>
                AiChatConversation.fromJson(value.cast<String, dynamic>()),
          )
          .where((conversation) => conversation.id.isNotEmpty)
          .toList();
      conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return conversations;
    } on Object {
      return [];
    }
  }

  Future<void> save(AiChatConversation conversation) async {
    final conversations = await load();
    conversations.removeWhere((value) => value.id == conversation.id);
    conversations.insert(0, conversation);
    await _write(conversations);
  }

  Future<void> delete(String id) async {
    await deleteMany([id]);
  }

  Future<void> deleteMany(Iterable<String> ids) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final conversations = await load();
    final deleting = conversations
        .where((value) => idSet.contains(value.id))
        .toList();
    conversations.removeWhere((value) => idSet.contains(value.id));
    final directory = (await _attachmentDirectory()).absolute.path;
    for (final message in deleting.expand((value) => value.messages)) {
      final attachment = message.attachment;
      if (attachment == null) continue;
      final file = File(attachment.path).absolute;
      if (file.parent.path == directory && await file.exists()) {
        await file.delete();
      }
    }
    await _write(conversations);
  }

  Future<File> createBackup({Iterable<String>? conversationIds}) async {
    final selectedIds = conversationIds?.toSet();
    final conversations = (await load())
        .where(
          (conversation) =>
              selectedIds == null || selectedIds.contains(conversation.id),
        )
        .toList();
    final payload = <Map<String, Object?>>[];
    for (final conversation in conversations) {
      final json = conversation.toJson();
      final messages = <Map<String, Object?>>[];
      for (final message in conversation.messages) {
        final messageJson = message.toJson();
        final attachment = message.attachment;
        if (attachment != null) {
          final file = File(attachment.path);
          if (await file.exists()) {
            messageJson['attachmentData'] = base64Encode(
              await file.readAsBytes(),
            );
          }
        }
        messages.add(messageJson);
      }
      json['messages'] = messages;
      payload.add(json);
    }
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}AI聊天备份_'
      '${DateTime.now().millisecondsSinceEpoch}.beadchat',
    );
    return file.writeAsBytes(
      gzip.encode(
        utf8.encode(
          jsonEncode({
            'format': 'bead-ai-chat-backup',
            'version': 1,
            'exportedAt': DateTime.now().toIso8601String(),
            'conversations': payload,
          }),
        ),
      ),
      flush: true,
    );
  }

  Future<void> shareBackup({Iterable<String>? conversationIds}) async {
    final file = await createBackup(conversationIds: conversationIds);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/octet-stream')],
        text: '拼豆 AI 聊天历史备份，可在聊天历史中导入。',
      ),
    );
  }

  Future<int?> pickAndImportBackup() async {
    Uint8List? bytes;
    if (Platform.isAndroid) {
      bytes = await _mediaChannel.invokeMethod<Uint8List>('pickBackup');
    } else {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: '拼豆 AI 聊天备份', extensions: ['beadchat']),
        ],
      );
      if (file != null) bytes = await file.readAsBytes();
    }
    if (bytes == null) return null;
    return importBackupBytes(bytes);
  }

  Future<int> importBackupBytes(Uint8List bytes) async {
    Map<String, dynamic> decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    } on Object catch (error) {
      throw FormatException('聊天备份已损坏或格式错误：$error');
    }
    if (decoded['format'] != 'bead-ai-chat-backup' || decoded['version'] != 1) {
      throw const FormatException('不是受支持的拼豆 AI 聊天备份');
    }
    final existing = await load();
    final ids = existing.map((value) => value.id).toSet();
    var imported = 0;
    for (final raw in decoded['conversations'] as List? ?? const []) {
      try {
        final json = (raw as Map).cast<String, dynamic>();
        final messages = <AiChatMessage>[];
        for (final rawMessage in json['messages'] as List? ?? const []) {
          final messageJson = (rawMessage as Map).cast<String, dynamic>();
          var message = AiChatMessage.fromJson(messageJson);
          final attachmentJson = messageJson['attachment'];
          final attachmentData = messageJson['attachmentData'] as String?;
          if (attachmentJson is Map && attachmentData != null) {
            final metadata = AiChatAttachment.fromJson(
              attachmentJson.cast<String, dynamic>(),
            );
            final attachment = await saveAttachmentBytes(
              base64Decode(attachmentData),
              name: metadata.name,
              mimeType: metadata.mimeType,
            );
            message = AiChatMessage(
              id: message.id,
              role: message.role,
              content: message.content,
              createdAt: message.createdAt,
              attachment: attachment,
              model: message.model,
              requestMode: message.requestMode,
              reasoning: message.reasoning,
              elapsedMs: message.elapsedMs,
              inputTokens: message.inputTokens,
              outputTokens: message.outputTokens,
              totalTokens: message.totalTokens,
            );
          }
          messages.add(message);
        }
        var conversation = AiChatConversation.fromJson({
          ...json,
          'messages': messages.map((message) => message.toJson()).toList(),
        });
        while (ids.contains(conversation.id)) {
          conversation = AiChatConversation(
            id: '${DateTime.now().microsecondsSinceEpoch}_$imported',
            title: conversation.title,
            model: conversation.model,
            createdAt: conversation.createdAt,
            updatedAt: DateTime.now(),
            messages: messages,
            note: conversation.note,
          );
        }
        conversation = AiChatConversation(
          id: conversation.id,
          title: conversation.title,
          model: conversation.model,
          createdAt: conversation.createdAt,
          updatedAt: conversation.updatedAt,
          messages: messages,
          note: conversation.note,
        );
        ids.add(conversation.id);
        existing.add(conversation);
        imported++;
      } on Object {
        // Continue restoring other valid conversations.
      }
    }
    existing.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _write(existing);
    return imported;
  }

  Future<AiChatAttachment> importAttachment(XFile source) async {
    final bytes = await source.readAsBytes();
    return saveAttachmentBytes(
      bytes,
      name: source.name,
      mimeType: source.mimeType ?? _mimeForName(source.name),
    );
  }

  Future<AiChatAttachment> saveAttachmentBytes(
    Uint8List bytes, {
    required String name,
    required String mimeType,
  }) async {
    if (bytes.isEmpty) throw const FormatException('附件内容为空');
    if (bytes.length > maxAttachmentBytes) {
      throw const FormatException('单个附件不能超过 20MB');
    }
    final directory = await _attachmentDirectory();
    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final target = File(
      '${directory.path}${Platform.pathSeparator}'
      '${DateTime.now().microsecondsSinceEpoch}_$safeName',
    );
    await target.writeAsBytes(bytes, flush: true);
    return AiChatAttachment(
      path: target.path,
      name: name,
      mimeType: mimeType,
      bytes: bytes.length,
    );
  }

  Future<void> _write(List<AiChatConversation> conversations) async {
    final file = await _indexFile();
    await file.writeAsString(
      jsonEncode(conversations.map((value) => value.toJson()).toList()),
      flush: true,
    );
  }

  static String _mimeForName(String name) {
    final extension = name.toLowerCase().split('.').last;
    return switch (extension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'ogg' || 'oga' => 'audio/ogg',
      'flac' => 'audio/flac',
      'pdf' => 'application/pdf',
      'txt' || 'md' => 'text/plain',
      'html' || 'htm' => 'text/html',
      'css' => 'text/css',
      'js' || 'mjs' || 'cjs' => 'text/javascript',
      'ts' || 'tsx' || 'jsx' => 'text/plain',
      'xml' => 'application/xml',
      'yaml' || 'yml' => 'application/yaml',
      'dart' ||
      'py' ||
      'java' ||
      'kt' ||
      'kts' ||
      'c' ||
      'cc' ||
      'cpp' ||
      'h' ||
      'hpp' ||
      'cs' ||
      'go' ||
      'rs' ||
      'php' ||
      'rb' ||
      'swift' ||
      'sql' ||
      'sh' ||
      'ps1' ||
      'bat' ||
      'toml' ||
      'ini' ||
      'log' => 'text/plain',
      'csv' => 'text/csv',
      'json' => 'application/json',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      _ => 'application/octet-stream',
    };
  }
}
