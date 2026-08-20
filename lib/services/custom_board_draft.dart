import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/bead_palettes.dart';
import '../models/bead_palette.dart';

class CustomBoardDraft {
  const CustomBoardDraft({
    required this.width,
    required this.height,
    required this.cells,
    required this.title,
    required this.selectedColor,
    required this.updatedAt,
    this.paletteId = BeadPaletteId.mard291,
  });

  final int width;
  final int height;
  final List<int> cells;
  final String title;
  final int selectedColor;
  final DateTime updatedAt;
  final BeadPaletteId paletteId;
}

class CustomBoardDraftStore {
  static const _mediaChannel = MethodChannel(
    'com.xuan.bead_ai_designer/media',
  );

  Future<File> _file() async {
    final documents = await getApplicationDocumentsDirectory();
    return File(
      '${documents.path}${Platform.pathSeparator}custom_board_draft.json',
    );
  }

  Future<CustomBoardDraft?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final width = json['width'] as int;
      final height = json['height'] as int;
      final cells = (json['cells'] as List).cast<int>();
      if (width < 5 ||
          height < 5 ||
          width > 300 ||
          height > 300 ||
          cells.length != width * height) {
        return null;
      }
      return CustomBoardDraft(
        width: width,
        height: height,
        cells: cells,
        title: json['title'] as String? ?? '自定义作品',
        selectedColor: json['selectedColor'] as int? ?? 0,
        paletteId:
            BeadPaletteIdStorage.tryParse(json['paletteId'] as String?) ??
            BeadPaletteId.mard291,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } on Object {
      return null;
    }
  }

  Future<Directory> _trashDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}custom_board_trash',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<void> save(CustomBoardDraft draft) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'schema': 1,
        'paletteId': draft.paletteId.storageId,
        'width': draft.width,
        'height': draft.height,
        'cells': draft.cells,
        'title': draft.title,
        'selectedColor': draft.selectedColor,
        'updatedAt': draft.updatedAt.toIso8601String(),
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<void> archive(CustomBoardDraft draft, {required String reason}) async {
    if (!draft.cells.any((value) => value >= 0)) return;
    final directory = await _trashDirectory();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final file = File('${directory.path}${Platform.pathSeparator}$id.json');
    await file.writeAsString(
      jsonEncode({..._draftToJson(draft), 'trashId': id, 'reason': reason}),
      flush: true,
    );
    final entries = await loadTrash();
    for (final old in entries.skip(20)) {
      await deleteTrash(old.id);
    }
  }

  Future<List<CustomBoardTrashEntry>> loadTrash() async {
    final directory = await _trashDirectory();
    final result = <CustomBoardTrashEntry>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        final draft = _draftFromJson(json);
        if (draft == null) continue;
        result.add(
          CustomBoardTrashEntry(
            id:
                json['trashId'] as String? ??
                entity.uri.pathSegments.last.replaceFirst('.json', ''),
            reason: json['reason'] as String? ?? '临时退出保护',
            draft: draft,
          ),
        );
      } on Object {
        // Keep other recoverable drafts available if one file is damaged.
      }
    }
    result.sort((a, b) => b.draft.updatedAt.compareTo(a.draft.updatedAt));
    return result;
  }

  Future<void> deleteTrash(String id) async {
    final directory = await _trashDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$id.json');
    if (await file.exists()) await file.delete();
  }

  Future<File> createTransferFile(CustomBoardDraft draft) async {
    final payload = <String, Object?>{
      'format': 'bead-ai-custom-board',
      'version': 1,
      'paletteId': draft.paletteId.storageId,
      'width': draft.width,
      'height': draft.height,
      'title': draft.title,
      'selectedColorCode': BeadPalettes.byId(draft.paletteId)
          .colors[draft.selectedColor.clamp(
            0,
            BeadPalettes.byId(draft.paletteId).colors.length - 1,
          )]
          .code,
      'cellCodes': [
        for (final value in draft.cells)
          value < 0
              ? null
              : BeadPalettes.byId(draft.paletteId).colors[value].code,
      ],
      'updatedAt': draft.updatedAt.toIso8601String(),
    };
    final directory = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(
      '${directory.path}${Platform.pathSeparator}自定义画板_$stamp.beadboard',
    );
    return file.writeAsBytes(
      GZipCodec(level: 6).encode(utf8.encode(jsonEncode(payload))),
      flush: true,
    );
  }

  Future<void> share(CustomBoardDraft draft) async {
    final file = await createTransferFile(draft);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/octet-stream')],
        text: '拼豆 AI 自定义画板工程，可导入后继续编辑。',
      ),
    );
  }

  Future<CustomBoardDraft?> pickAndImport() async {
    final Uint8List? bytes;
    if (Platform.isAndroid) {
      bytes = await _mediaChannel.invokeMethod<Uint8List>('pickBackup');
    } else {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: '拼豆 AI 自定义画板', extensions: ['beadboard']),
        ],
      );
      bytes = file == null ? null : await file.readAsBytes();
    }
    return bytes == null ? null : importBytes(bytes);
  }

  CustomBoardDraft importBytes(Uint8List bytes) {
    final json =
        jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    if (json['format'] != 'bead-ai-custom-board' || json['version'] != 1) {
      throw const FormatException('不是受支持的自定义画板工程');
    }
    final width = json['width'] as int;
    final height = json['height'] as int;
    final codes = (json['cellCodes'] as List).cast<String?>();
    if (width < 5 ||
        height < 5 ||
        width > 300 ||
        height > 300 ||
        codes.length != width * height) {
      throw const FormatException('画板尺寸或格子数据不完整');
    }
    final palette = BeadPalettes.byId(
      BeadPaletteIdStorage.tryParse(json['paletteId'] as String?) ??
          BeadPaletteId.mard291,
    );
    final cells = <int>[];
    for (final code in codes) {
      if (code == null) {
        cells.add(-1);
        continue;
      }
      final color = palette.byCode[code];
      if (color == null) throw FormatException('不支持的 Artkal 色号：$code');
      cells.add(palette.colors.indexOf(color));
    }
    final selectedCode = json['selectedColorCode'] as String?;
    final selectedColor = selectedCode == null
        ? 0
        : palette.colors.indexWhere((color) => color.code == selectedCode);
    return CustomBoardDraft(
      width: width,
      height: height,
      cells: cells,
      title: json['title'] as String? ?? '导入的自定义画板',
      selectedColor: selectedColor,
      paletteId: palette.id,
      updatedAt: DateTime.now(),
    );
  }

  static Map<String, Object?> _draftToJson(CustomBoardDraft draft) => {
    'schema': 2,
    'paletteId': draft.paletteId.storageId,
    'width': draft.width,
    'height': draft.height,
    'cells': draft.cells,
    'title': draft.title,
    'selectedColor': draft.selectedColor,
    'updatedAt': draft.updatedAt.toIso8601String(),
  };

  static CustomBoardDraft? _draftFromJson(Map<String, dynamic> json) {
    final width = json['width'] as int?;
    final height = json['height'] as int?;
    final rawCells = json['cells'] as List?;
    if (width == null ||
        height == null ||
        rawCells == null ||
        width < 5 ||
        height < 5 ||
        width > 300 ||
        height > 300 ||
        rawCells.length != width * height) {
      return null;
    }
    return CustomBoardDraft(
      width: width,
      height: height,
      cells: rawCells.cast<int>(),
      title: json['title'] as String? ?? '自定义作品',
      selectedColor: json['selectedColor'] as int? ?? 0,
      paletteId:
          BeadPaletteIdStorage.tryParse(json['paletteId'] as String?) ??
          BeadPaletteId.mard291,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class CustomBoardTrashEntry {
  const CustomBoardTrashEntry({
    required this.id,
    required this.reason,
    required this.draft,
  });

  final String id;
  final String reason;
  final CustomBoardDraft draft;
}
