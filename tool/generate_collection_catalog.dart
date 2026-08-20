import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('Usage: dart run tool/generate_collection_catalog.dart <source> <output>');
    exitCode = 2;
    return;
  }
  final source = Directory(args[0]);
  final output = Directory(args[1]);
  if (!await source.exists()) throw ArgumentError('Source directory not found');
  await output.create(recursive: true);
  final files = await source
      .list(recursive: true, followLinks: false)
      .where((entity) => entity is File)
      .cast<File>()
      .where((file) => _isImage(file.path))
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  final categories = <String, List<Map<String, Object?>>>{};
  var index = 0;
  for (final file in files) {
    final relative = _relative(source.path, file.path);
    final parts = relative.split(RegExp(r'[/\\]'));
    final category = parts.length > 1 ? parts.first : '未分类';
    final name = parts.last;
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) continue;
    final scale = (decoded.width > decoded.height ? decoded.width : decoded.height) > 384
        ? 384 / (decoded.width > decoded.height ? decoded.width : decoded.height)
        : 1.0;
    final preview = scale < 1
        ? img.copyResize(
            decoded,
            width: (decoded.width * scale).round(),
            height: (decoded.height * scale).round(),
            interpolation: img.Interpolation.average,
          )
        : decoded;
    final previewName = 'preview_${index.toString().padLeft(4, '0')}.jpg';
    await File('${output.path}${Platform.pathSeparator}$previewName')
        .writeAsBytes(img.encodeJpg(preview, quality: 72), flush: true);
    (categories[category] ??= <Map<String, Object?>>[]).add({
      'name': name,
      'relativePath': relative,
      'asset': 'assets/pindou_collection/$previewName',
      'width': decoded.width,
      'height': decoded.height,
      'bytes': bytes.length,
      'extension': _extension(name),
    });
    index++;
    if (index % 50 == 0) stdout.writeln('processed $index/${files.length}');
  }
  final manifest = {
    'version': 1,
    'sourceFileCount': files.length,
    'previewFileCount': index,
    'categories': [
      for (final entry in categories.entries)
        {'name': entry.key, 'items': entry.value},
    ],
  };
  await File('${output.path}${Platform.pathSeparator}manifest.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(manifest), flush: true);
  stdout.writeln('generated $index previews in ${output.path}');
}

bool _isImage(String path) =>
    const {'.png', '.jpg', '.jpeg', '.webp', '.bmp'}
        .contains(_extension(path).toLowerCase());

String _extension(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot);
}

String _relative(String root, String path) {
  final normalizedRoot = root.replaceAll('\\', '/').replaceFirst(RegExp(r'/$'), '');
  final normalizedPath = path.replaceAll('\\', '/');
  return normalizedPath.startsWith('$normalizedRoot/')
      ? normalizedPath.substring(normalizedRoot.length + 1)
      : normalizedPath;
}
