import 'dart:convert';
import 'dart:typed_data';

class AiGeneratedArtifact {
  const AiGeneratedArtifact({
    required this.name,
    required this.language,
    required this.content,
  });

  final String name;
  final String language;
  final String content;

  Uint8List get bytes => Uint8List.fromList(utf8.encode(content));
}

abstract final class AiGeneratedArtifactParser {
  static AiGeneratedArtifact? first(String message) {
    final values = all(message);
    return values.isEmpty ? null : values.first;
  }

  static List<AiGeneratedArtifact> all(String message) {
    final matches = RegExp(r'```([^\n`]*)\n([\s\S]*?)```').allMatches(message);
    final result = <AiGeneratedArtifact>[];
    var unnamedIndex = 0;
    for (final match in matches) {
      final language = match.group(1)?.trim().toLowerCase() ?? '';
      var content = match.group(2) ?? '';
      String? name;
      final firstLine = RegExp(
        r'^\s*(?:filename|file|文件名)\s*[:：]\s*([^\r\n]+)\r?\n',
        caseSensitive: false,
      ).firstMatch(content);
      if (firstLine != null) {
        name = firstLine.group(1)?.trim();
        content = content.substring(firstLine.end);
      }
      if (name?.isNotEmpty != true) unnamedIndex++;
      final fallback = unnamedIndex <= 1
          ? 'AI生成.${_extension(language)}'
          : 'AI生成_$unnamedIndex.${_extension(language)}';
      final safeName = (name?.isNotEmpty == true ? name! : fallback).replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '_',
      );
      result.add(
        AiGeneratedArtifact(
          name: safeName,
          language: language.isEmpty ? 'text' : language,
          content: content,
        ),
      );
    }
    return result;
  }

  static String _extension(String language) => switch (language) {
    'html' => 'html',
    'css' => 'css',
    'javascript' || 'js' => 'js',
    'typescript' || 'ts' => 'ts',
    'python' || 'py' => 'py',
    'dart' => 'dart',
    'java' => 'java',
    'kotlin' || 'kt' => 'kt',
    'csharp' || 'cs' => 'cs',
    'cpp' || 'c++' => 'cpp',
    'go' => 'go',
    'rust' || 'rs' => 'rs',
    'sql' => 'sql',
    'json' => 'json',
    'xml' => 'xml',
    'yaml' || 'yml' => 'yaml',
    'csv' => 'csv',
    'markdown' || 'md' => 'md',
    _ => 'txt',
  };
}
