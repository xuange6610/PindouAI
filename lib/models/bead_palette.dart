import 'bead_color.dart';

enum BeadPaletteId {
  // Keep the first five entries stable: persisted projects and color IDs from
  // older releases depend on their enum order.
  artkal397,
  mard291,
  coco291,
  perler,
  hama,
  mard221,
  mard447,
  coco100,
  coco200,
  artkalA,
  artkalC,
  artkalS,
  artkalMini,
  perlerStandard,
  perlerTransparent,
  perlerGlitter,
  hamaStandard,
  hamaMidi,
  hamaMini,
  nabbiStandard,
  nabbiGem,
  pysslaStandard,
  manman,
  xiaowu,
  panpan,
  huangdoudou,
  mixiaowo,
  youken,
  doudoule,
  mofadoudou,
  xihe,
  rainbowBeans,
  legoBeans,
  heartBeans,
  qicaiBeans,
  bearBeans,
  jingcaiBeans,
  rainbowBridge,
  dongmumu,
}

extension BeadPaletteIdStorage on BeadPaletteId {
  String get storageId => name;

  static BeadPaletteId? tryParse(String? value) {
    for (final id in BeadPaletteId.values) {
      if (id.storageId == value) return id;
    }
    return null;
  }
}

class BeadPalette {
  BeadPalette({
    required this.id,
    required this.shortName,
    required this.displayName,
    required this.description,
    required this.pitchMm,
    required List<BeadColor> colors,
    this.searchTerms = const [],
    this.isReference = false,
  }) : colors = List.unmodifiable(colors),
       byCode = Map.unmodifiable({
         for (final color in colors) color.code: color,
       }),
       seriesNames = Map.unmodifiable({
         for (final color in colors) color.series: _seriesLabel(color.series),
       });

  final BeadPaletteId id;
  final String shortName;
  final String displayName;
  final String description;
  final double pitchMm;
  final List<BeadColor> colors;
  final List<String> searchTerms;
  final bool isReference;
  final Map<String, BeadColor> byCode;
  final Map<String, String> seriesNames;

  String get specification =>
      '$shortName · ${colors.length}色 · ${pitchMm.toStringAsFixed(pitchMm == pitchMm.roundToDouble() ? 0 : 1)}mm';

  bool matchesQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return '$shortName $displayName $description ${searchTerms.join(' ')}'
        .toLowerCase()
        .contains(normalized);
  }

  static String _seriesLabel(String series) => switch (series) {
    'solid' => '标准实色',
    'pearl' => '珠光',
    'translucent' => '透明',
    'neon' => '荧光',
    'metallic' => '金属',
    'glitter' => '闪粉',
    'glow' => '夜光',
    'striped' => '条纹',
    'other' => '其他',
    _ => '$series 系列',
  };
}
