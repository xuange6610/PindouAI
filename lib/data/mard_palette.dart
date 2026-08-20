import 'dart:math' as math;

import '../models/bead_color.dart';
import '../services/color_science.dart';
import 'artkal_palette_data.dart';

/// The historical class name is retained so old project backups and imports
/// continue to compile. New generation always uses the 300-color Artkal set.
abstract final class MardPalette {
  static final List<BeadColor> colors = List.unmodifiable(
    artkalPaletteData.indexed.map((entry) {
      final data = entry.$2;
      final red = (data.argb >> 16) & 0xFF;
      final green = (data.argb >> 8) & 0xFF;
      final blue = data.argb & 0xFF;
      final slash = data.name.indexOf('/');
      final nameCn = slash < 0
          ? data.name
          : data.name.substring(0, slash).trim();
      final nameEn = slash < 0
          ? data.name
          : data.name.substring(slash + 1).trim();
      return BeadColor(
        id: entry.$1 + 1,
        brand: 'Artkal',
        series: _seriesOf(data.code),
        code: data.code,
        nameCn: nameCn,
        nameEn: nameEn,
        red: red,
        green: green,
        blue: blue,
        lab: _boundedLab(red, green, blue),
        sizeMm: data.code.startsWith('M') ? 2.6 : 5,
        type: _typeName(data.family),
      );
    }),
  );

  static final Map<String, BeadColor> _actualByCode = {
    for (final color in colors) color.code: color,
  };

  /// Legacy MARD codes remain readable so previous works/backups are not lost.
  static final Map<String, BeadColor> byCode = Map.unmodifiable({
    ..._actualByCode,
    for (final color in _buildLegacyColors()) color.code: color,
  });

  static final Map<String, String> seriesNames = Map.unmodifiable({
    for (final color in colors) color.series: _seriesLabel(color.series),
  });

  static int indexFor(BeadColor color) {
    final exact = colors.indexWhere((item) => item.code == color.code);
    if (exact >= 0) return exact;
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var index = 0; index < colors.length; index++) {
      final distance = ColorScience.deltaE2000(color.lab, colors[index].lab);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  static String _seriesOf(String code) =>
      RegExp(r'^[A-Za-z]+').firstMatch(code)?.group(0)?.toUpperCase() ?? '其他';

  static String _seriesLabel(String series) {
    if (series.startsWith('M')) return 'Artkal Mini $series';
    if (series == 'S') return 'Artkal S 标准色';
    return 'Artkal S $series';
  }

  static String _typeName(String family) => switch (family) {
    'pearl' => '珠光',
    'translucent' => '透明',
    'neon' => '荧光',
    'metallic' => '金属',
    'glitter' => '闪粉',
    'glow' => '夜光',
    _ => '标准实色',
  };

  static LabColor _boundedLab(int red, int green, int blue) {
    final lab = ColorScience.rgbToLab(red, green, blue);
    return LabColor(lab.l.clamp(0, 100).toDouble(), lab.a, lab.b);
  }

  static const _legacyCounts = {
    'A': 26,
    'B': 32,
    'C': 29,
    'D': 26,
    'E': 24,
    'F': 25,
    'G': 21,
    'H': 23,
    'M': 15,
  };

  static const Map<String, List<int>> _legacyAnchors = {
    'A': [0xFFF7F0D0, 0xFFFFE36D, 0xFFF5B62E, 0xFFF17B35, 0xFFB94B24],
    'B': [0xFFE2F1C7, 0xFF9DDB78, 0xFF45B56B, 0xFF16856B, 0xFF24583F],
    'C': [0xFFDDF3F4, 0xFF82D6E9, 0xFF3EA9D7, 0xFF3479C8, 0xFF182B59],
    'D': [0xFFE8E1F5, 0xFFC3A6E3, 0xFF8D78CB, 0xFF6548A6, 0xFF4E285B],
    'E': [0xFFFFECEC, 0xFFF9CBD6, 0xFFF19AB7, 0xFFDA6E9E, 0xFFB34778],
    'F': [0xFFFFD3C6, 0xFFF58B7C, 0xFFE65051, 0xFFB8273F, 0xFF6B3A31],
    'G': [0xFFFFEBD1, 0xFFF4CDA8, 0xFFD99F75, 0xFFB9784F, 0xFF563A2E],
    'H': [0xFFFAFAF7, 0xFFD9D8D2, 0xFFA8A6A2, 0xFF777674, 0xFF161616],
    'M': [0xFFD9C7BE, 0xFFC7B2B8, 0xFFB5B6CA, 0xFFA6BEC0, 0xFFAFC4AB],
  };

  static List<BeadColor> _buildLegacyColors() {
    final result = <BeadColor>[];
    var id = 10001;
    for (final entry in _legacyCounts.entries) {
      final anchors = _legacyAnchors[entry.key]!;
      for (var index = 0; index < entry.value; index++) {
        final position =
            index / math.max(1, entry.value - 1) * (anchors.length - 1);
        final lower = position.floor().clamp(0, anchors.length - 1);
        final upper = math.min(lower + 1, anchors.length - 1);
        final fraction = position - lower;
        int channel(int shift) {
          final start = (anchors[lower] >> shift) & 0xFF;
          final end = (anchors[upper] >> shift) & 0xFF;
          return (start + (end - start) * fraction).round();
        }

        final red = channel(16);
        final green = channel(8);
        final blue = channel(0);
        final code = '${entry.key}${index + 1}';
        result.add(
          BeadColor(
            id: id++,
            brand: 'MARD（兼容旧作品）',
            series: entry.key,
            code: code,
            nameCn: '旧版色号 $code',
            nameEn: 'Legacy $code',
            red: red,
            green: green,
            blue: blue,
            lab: _boundedLab(red, green, blue),
          ),
        );
      }
    }
    return result;
  }
}
