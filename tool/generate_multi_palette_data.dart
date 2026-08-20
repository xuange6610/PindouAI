import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/generate_multi_palette_data.dart <palette.ts> <output.dart>',
    );
    exitCode = 64;
    return;
  }

  final source = File(arguments[0]).readAsStringSync();
  final arrays = <String, String>{
    'perlerPaletteData': 'PERLER_COLORS',
    'mard291PaletteData': 'MARD291_COLORS',
    'coco291PaletteData': 'COCO291_COLORS',
    'hamaPaletteData': 'HAMA_COLORS',
    'artkalSPaletteData': 'ARTKAL_S_COLORS',
    'artkalMiniPaletteData': 'ARTKAL_MINI_COLORS',
  };
  final output = StringBuffer()
    ..writeln('// GENERATED FILE - do not edit by hand.')
    ..writeln('// Source: real-jiakai/perler-studio palette.ts; its generator')
    ..writeln('// documents Perler beadcolors measurements and bitbead charts.')
    ..writeln('class RawPaletteColorData {')
    ..writeln(
      '  const RawPaletteColorData(this.code, this.name, this.argb, this.family);',
    )
    ..writeln()
    ..writeln('  final String code;')
    ..writeln('  final String name;')
    ..writeln('  final int argb;')
    ..writeln('  final String family;')
    ..writeln('}')
    ..writeln();

  for (final array in arrays.entries) {
    final marker = 'export const ${array.value}';
    final start = source.indexOf(marker);
    final end = source.indexOf('];', start);
    if (start < 0 || end < 0) {
      throw FormatException('Missing ${array.value}');
    }
    final body = source.substring(start, end);
    final matches = RegExp(
      r'\{ code: "((?:\\.|[^"\\])*)", name: "((?:\\.|[^"\\])*)", hex: "#([0-9A-Fa-f]{6})", family: "([^"]+)" \}',
    ).allMatches(body);
    output.writeln('const ${array.key} = <RawPaletteColorData>[');
    var count = 0;
    for (final match in matches) {
      String decode(String value) => jsonDecode('"$value"') as String;
      final code = jsonEncode(decode(match.group(1)!));
      final name = jsonEncode(decode(match.group(2)!));
      final hex = match.group(3)!.toUpperCase();
      final family = jsonEncode(match.group(4)!);
      output.writeln('  RawPaletteColorData($code, $name, 0xFF$hex, $family),');
      count++;
    }
    if (count == 0) {
      throw FormatException('No colors parsed for ${array.value}');
    }
    output.writeln('];');
    output.writeln();
  }
  output
    ..writeln('const artkal397PaletteData = <RawPaletteColorData>[')
    ..writeln('  ...artkalSPaletteData,')
    ..writeln('  ...artkalMiniPaletteData,')
    ..writeln('];');
  File(arguments[1]).writeAsStringSync(output.toString());
}
