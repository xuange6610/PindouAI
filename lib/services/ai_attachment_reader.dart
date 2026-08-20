import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'ai_chat_store.dart';

abstract final class AiAttachmentReader {
  static const maxExtractedCharacters = 120000;

  static Future<String?> extractText(AiChatAttachment attachment) async {
    final file = File(attachment.path);
    if (!await file.exists()) return null;
    final extension = attachment.name.toLowerCase().split('.').last;
    if (_textExtensions.contains(extension) ||
        attachment.mimeType.startsWith('text/') ||
        attachment.mimeType == 'application/json' ||
        attachment.mimeType == 'application/xml') {
      return _limit(await file.readAsString());
    }
    final bytes = await file.readAsBytes();
    if (extension == 'docx') return _extractDocx(bytes);
    if (extension == 'xlsx') return _extractXlsx(bytes);
    if (extension == 'pptx') return _extractPptx(bytes);
    return null;
  }

  static const _textExtensions = {
    'txt',
    'md',
    'csv',
    'json',
    'xml',
    'html',
    'htm',
    'css',
    'js',
    'ts',
    'jsx',
    'tsx',
    'dart',
    'py',
    'java',
    'kt',
    'kts',
    'c',
    'cc',
    'cpp',
    'h',
    'hpp',
    'cs',
    'go',
    'rs',
    'php',
    'rb',
    'swift',
    'sql',
    'sh',
    'ps1',
    'bat',
    'yaml',
    'yml',
    'toml',
    'ini',
    'log',
  };

  static String _extractDocx(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final document = archive.findFile('word/document.xml');
    if (document == null) throw const FormatException('Word 文件缺少 document.xml');
    var xml = utf8.decode(document.content, allowMalformed: true);
    xml = xml
        .replaceAll(RegExp(r'</w:p>'), '\n')
        .replaceAll(RegExp(r'<w:tab[^>]*/>'), '\t');
    return _limit(_plainXml(xml));
  }

  static String _extractPptx(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final slides =
        archive.files
            .where(
              (file) =>
                  RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(file.name),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    if (slides.isEmpty) throw const FormatException('PPT 文件中没有幻灯片');
    final output = <String>[];
    for (var index = 0; index < slides.length; index++) {
      final xml = utf8.decode(slides[index].content, allowMalformed: true);
      output.add('第 ${index + 1} 页\n${_plainXml(xml)}');
    }
    return _limit(output.join('\n\n'));
  }

  static String _extractXlsx(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final shared = <String>[];
    final sharedFile = archive.findFile('xl/sharedStrings.xml');
    if (sharedFile != null) {
      final xml = utf8.decode(sharedFile.content, allowMalformed: true);
      for (final match in RegExp(r'<si[^>]*>([\s\S]*?)</si>').allMatches(xml)) {
        shared.add(_plainXml(match.group(1) ?? ''));
      }
    }
    final sheets =
        archive.files
            .where(
              (file) =>
                  RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(file.name),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    if (sheets.isEmpty) throw const FormatException('Excel 文件中没有工作表');
    final output = <String>[];
    for (var sheetIndex = 0; sheetIndex < sheets.length; sheetIndex++) {
      final xml = utf8.decode(sheets[sheetIndex].content, allowMalformed: true);
      output.add('工作表 ${sheetIndex + 1}');
      for (final row in RegExp(r'<row[^>]*>([\s\S]*?)</row>').allMatches(xml)) {
        final values = <String>[];
        for (final cell in RegExp(
          r'<c([^>]*)>([\s\S]*?)</c>',
        ).allMatches(row.group(1) ?? '')) {
          final attributes = cell.group(1) ?? '';
          final body = cell.group(2) ?? '';
          final raw =
              RegExp(r'<v[^>]*>([\s\S]*?)</v>').firstMatch(body)?.group(1) ??
              RegExp(r'<t[^>]*>([\s\S]*?)</t>').firstMatch(body)?.group(1) ??
              '';
          if (attributes.contains('t="s"')) {
            final index = int.tryParse(raw);
            values.add(
              index != null && index < shared.length ? shared[index] : raw,
            );
          } else {
            values.add(_decodeEntities(raw));
          }
        }
        output.add(values.join('\t'));
      }
      output.add('');
    }
    return _limit(output.join('\n'));
  }

  static String _plainXml(String xml) => _decodeEntities(
    xml
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n'),
  ).trim();

  static String _decodeEntities(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");

  static String _limit(String value) => value.length <= maxExtractedCharacters
      ? value
      : '${value.substring(0, maxExtractedCharacters)}\n\n[内容过长，已截取前 $maxExtractedCharacters 个字符]';
}
