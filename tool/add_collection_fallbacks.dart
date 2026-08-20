import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length < 2) throw ArgumentError('source and output are required');
  final source = Directory(args[0]);
  final output = Directory(args[1]);
  final manifestFile = File('${output.path}${Platform.pathSeparator}manifest.json');
  final manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
  final categories = (manifest['categories'] as List).cast<Map<String, dynamic>>();
  final indexed = <String>{
    for (final category in categories)
      for (final item in (category['items'] as List).cast<Map<String, dynamic>>())
        item['relativePath'] as String,
  };
  var nextIndex = manifest['previewFileCount'] as int;
  final files = await source
      .list(recursive: true)
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
  for (final file in files) {
    final relative = _relative(source.path, file.path);
    if (indexed.contains(relative)) continue;
    final parts = relative.split(RegExp(r'[/\\]'));
    if (parts.length < 2) continue;
    final categoryName = parts.first;
    final category = categories.firstWhere(
      (item) => item['name'] == categoryName,
      orElse: () {
        final value = <String, dynamic>{'name': categoryName, 'items': <Map<String, dynamic>>[]};
        categories.add(value);
        return value;
      },
    );
    final assetName = 'preview_${nextIndex.toString().padLeft(4, '0')}.heic';
    final bytes = await file.readAsBytes();
    await File('${output.path}${Platform.pathSeparator}$assetName').writeAsBytes(bytes, flush: true);
    (category['items'] as List).add({
      'name': parts.last,
      'relativePath': relative,
      'asset': 'assets/pindou_collection/$assetName',
      'width': 0,
      'height': 0,
      'bytes': bytes.length,
      'extension': _extension(parts.last),
    });
    nextIndex++;
  }
  manifest['previewFileCount'] = nextIndex;
  await manifestFile.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest), flush: true);
  stdout.writeln('catalog now contains $nextIndex files');
}

String _relative(String root, String path) {
  final normalizedRoot = root.replaceAll('\\', '/').replaceFirst(RegExp(r'/$'), '');
  final normalizedPath = path.replaceAll('\\', '/');
  return normalizedPath.substring(normalizedRoot.length + 1);
}

String _extension(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot);
}
