import '../models/bead_color.dart';
import '../models/bead_palette.dart';
import '../services/color_science.dart';
import 'multi_palette_data.dart';

abstract final class BeadPalettes {
  static final BeadPalette artkal397 = _build(
    id: BeadPaletteId.artkal397,
    shortName: 'Artkal',
    displayName: 'Artkal 300+色',
    description: 'S 与 Mini 完整合并，当前共 397 色',
    pitchMm: 2.6,
    data: artkal397PaletteData,
  );

  static final BeadPalette mard291 = _build(
    id: BeadPaletteId.mard291,
    shortName: 'MARD',
    displayName: 'MARD 291色（常用扩展全色）',
    description: '默认生成方案，完整 291 色',
    pitchMm: 2.6,
    data: mard291PaletteData,
  );

  static final BeadPalette coco291 = _build(
    id: BeadPaletteId.coco291,
    shortName: 'COCO',
    displayName: 'COCO 约291色',
    description: '当前完整色卡 291 色',
    pitchMm: 2.6,
    data: coco291PaletteData,
  );

  static final BeadPalette perler = _build(
    id: BeadPaletteId.perler,
    shortName: 'Perler',
    displayName: 'Perler 主流 / 扩展色',
    description: '约117主流、约150扩展；当前公开实测色卡 103 色',
    pitchMm: 5,
    data: perlerPaletteData,
  );

  static final BeadPalette hama = _build(
    id: BeadPaletteId.hama,
    shortName: 'Hama',
    displayName: 'Hama 约89色',
    description: '当前完整色卡 89 色',
    pitchMm: 5,
    data: hamaPaletteData,
  );

  static final BeadPalette mard221 = _build(
    id: BeadPaletteId.mard221,
    shortName: 'MARD 221',
    displayName: 'MARD 221色',
    description: 'MARD 291 色卡中的常用 221 色子集',
    pitchMm: 2.6,
    data: mard291PaletteData.take(221).toList(),
    searchTerms: const ['马德', '玛豆', 'MARD MM'],
  );

  static final BeadPalette mard447 = _alias(
    id: BeadPaletteId.mard447,
    source: mard291,
    shortName: 'MARD 447',
    displayName: 'MARD 447色系列',
    description: '已收录 291 个有来源色值；其余扩展色待导入官方色卡',
    searchTerms: const ['马德', '玛豆', '447色'],
  );

  static final BeadPalette coco100 = _build(
    id: BeadPaletteId.coco100,
    shortName: 'COCO 100',
    displayName: 'COCO 100色',
    description: 'COCO 291 色卡中的常用 100 色子集',
    pitchMm: 2.6,
    data: coco291PaletteData.take(100).toList(),
    searchTerms: const ['可可拼豆'],
  );

  static final BeadPalette coco200 = _build(
    id: BeadPaletteId.coco200,
    shortName: 'COCO 200',
    displayName: 'COCO 200色',
    description: 'COCO 291 色卡中的常用 200 色子集',
    pitchMm: 2.6,
    data: coco291PaletteData.take(200).toList(),
    searchTerms: const ['可可拼豆'],
  );

  static final BeadPalette artkalS = _build(
    id: BeadPaletteId.artkalS,
    shortName: 'Artkal S',
    displayName: 'Artkal S系列',
    description: 'Artkal S 系列公开色卡',
    pitchMm: 5,
    data: artkalSPaletteData,
    searchTerms: const ['阿特卡', 'Artkal标准色'],
  );

  static final BeadPalette artkalMini = _build(
    id: BeadPaletteId.artkalMini,
    shortName: 'Artkal Mini',
    displayName: 'Artkal Mini系列',
    description: 'Artkal Mini 2.6mm 系列公开色卡',
    pitchMm: 2.6,
    data: artkalMiniPaletteData,
    searchTerms: const ['阿特卡迷你', 'Artkal M'],
  );

  static final BeadPalette artkalA = _alias(
    id: BeadPaletteId.artkalA,
    source: artkal397,
    shortName: 'Artkal A',
    displayName: 'Artkal A系列',
    description: '使用 Artkal 已收录色卡作为兼容参考',
    searchTerms: const ['阿特卡 A系列'],
  );

  static final BeadPalette artkalC = _alias(
    id: BeadPaletteId.artkalC,
    source: artkal397,
    shortName: 'Artkal C',
    displayName: 'Artkal C系列',
    description: '使用 Artkal 已收录色卡作为兼容参考',
    searchTerms: const ['阿特卡 C系列'],
  );

  static final BeadPalette perlerStandard = _alias(
    id: BeadPaletteId.perlerStandard,
    source: perler,
    shortName: 'Perler 标准',
    displayName: 'Perler标准色',
    description: 'Perler 已收录主流标准色',
    searchTerms: const ['派乐', 'Perler主流色'],
    isReference: false,
  );

  static final BeadPalette perlerTransparent = _alias(
    id: BeadPaletteId.perlerTransparent,
    source: perler,
    shortName: 'Perler 透明',
    displayName: 'Perler透明色',
    description: '使用 Perler 已收录色值作为透明系列参考',
    searchTerms: const ['派乐透明'],
  );

  static final BeadPalette perlerGlitter = _alias(
    id: BeadPaletteId.perlerGlitter,
    source: perler,
    shortName: 'Perler 闪光',
    displayName: 'Perler闪光色',
    description: '使用 Perler 已收录色值作为闪光系列参考',
    searchTerms: const ['派乐闪光', '闪粉'],
  );

  static final BeadPalette hamaStandard = _build(
    id: BeadPaletteId.hamaStandard,
    shortName: 'Hama 标准',
    displayName: 'Hama标准色',
    description: 'Hama 色卡中的标准实色',
    pitchMm: 5,
    data: hamaPaletteData.where((item) => item.family == 'solid').toList(),
    searchTerms: const ['哈玛'],
  );

  static final BeadPalette hamaMidi = _alias(
    id: BeadPaletteId.hamaMidi,
    source: hama,
    shortName: 'Hama Midi',
    displayName: 'Hama Midi',
    description: 'Hama 5mm Midi 完整已收录色卡',
    searchTerms: const ['哈玛中号'],
    isReference: false,
  );

  static final BeadPalette hamaMini = _alias(
    id: BeadPaletteId.hamaMini,
    source: hama,
    shortName: 'Hama Mini',
    displayName: 'Hama Mini',
    description: 'Hama 色值的 2.6mm Mini 规格',
    pitchMm: 2.6,
    searchTerms: const ['哈玛迷你'],
  );

  static final BeadPalette nabbiStandard = _reference(
    BeadPaletteId.nabbiStandard,
    'Nabbi',
    'Nabbi标准色',
    hama,
    const ['纳比', 'Nabbi beads'],
  );
  static final BeadPalette nabbiGem = _reference(
    BeadPaletteId.nabbiGem,
    'Nabbi 宝石',
    'Nabbi宝石色',
    hama,
    const ['纳比宝石', '透明'],
  );
  static final BeadPalette pysslaStandard = _reference(
    BeadPaletteId.pysslaStandard,
    'Pyssla',
    'Pyssla标准色',
    hama,
    const ['宜家拼豆', 'IKEA'],
  );
  static final BeadPalette manman = _reference(
    BeadPaletteId.manman,
    'MM 漫漫',
    '漫漫（MM）',
    mard291,
    const ['MARD MM'],
  );
  static final BeadPalette xiaowu = _reference(
    BeadPaletteId.xiaowu,
    'XW 小舞',
    '小舞（XW）',
    mard291,
    const ['小舞拼豆'],
  );
  static final BeadPalette panpan = _reference(
    BeadPaletteId.panpan,
    'PP 盼盼',
    '盼盼（PP）',
    mard291,
    const ['盼盼拼豆'],
  );
  static final BeadPalette huangdoudou = _reference(
    BeadPaletteId.huangdoudou,
    'HDD 黄豆豆',
    '黄豆豆（HDD）',
    mard291,
    const ['黄豆豆拼豆'],
  );
  static final BeadPalette mixiaowo = _reference(
    BeadPaletteId.mixiaowo,
    'MXW 咪小窝',
    '咪小窝（MXW）',
    mard291,
    const ['咪小窝拼豆'],
  );
  static final BeadPalette youken = _reference(
    BeadPaletteId.youken,
    'UK 优肯',
    '优肯（UK）',
    mard291,
    const ['优肯拼豆'],
  );
  static final BeadPalette doudoule = _reference(
    BeadPaletteId.doudoule,
    'DDL 豆豆乐',
    '豆豆乐（DDL）',
    mard291,
    const ['豆豆乐拼豆'],
  );
  static final BeadPalette mofadoudou = _reference(
    BeadPaletteId.mofadoudou,
    'MFD 魔法豆豆',
    '魔法豆豆（MFD）',
    mard291,
    const ['魔法豆豆拼豆'],
  );
  static final BeadPalette xihe = _reference(
    BeadPaletteId.xihe,
    '熙和拼豆',
    '熙和拼豆',
    mard291,
    const ['熙和'],
  );
  static final BeadPalette rainbowBeans = _reference(
    BeadPaletteId.rainbowBeans,
    '彩虹豆',
    '彩虹豆',
    mard291,
    const ['彩虹'],
  );
  static final BeadPalette legoBeans = _reference(
    BeadPaletteId.legoBeans,
    '乐高豆',
    '乐高豆',
    mard291,
    const ['LEGO'],
  );
  static final BeadPalette heartBeans = _reference(
    BeadPaletteId.heartBeans,
    '爱心豆',
    '爱心豆',
    mard291,
    const ['心形豆'],
  );
  static final BeadPalette qicaiBeans = _reference(
    BeadPaletteId.qicaiBeans,
    '七彩豆',
    '七彩豆',
    mard291,
    const ['七彩'],
  );
  static final BeadPalette bearBeans = _reference(
    BeadPaletteId.bearBeans,
    '小熊豆',
    '小熊豆',
    mard291,
    const ['小熊拼豆'],
  );
  static final BeadPalette jingcaiBeans = _reference(
    BeadPaletteId.jingcaiBeans,
    '晶彩豆',
    '晶彩豆',
    mard291,
    const ['晶彩'],
  );
  static final BeadPalette rainbowBridge = _reference(
    BeadPaletteId.rainbowBridge,
    '彩虹桥',
    '彩虹桥拼豆',
    mard291,
    const ['彩虹桥拼豆'],
  );
  static final BeadPalette dongmumu = _reference(
    BeadPaletteId.dongmumu,
    '动木木',
    '动木木',
    mard291,
    const ['动木木拼豆'],
  );

  static final List<BeadPalette> all = List.unmodifiable([
    mard291,
    mard221,
    mard447,
    coco100,
    coco200,
    artkal397,
    artkalA,
    artkalC,
    artkalS,
    artkalMini,
    coco291,
    perler,
    perlerStandard,
    perlerTransparent,
    perlerGlitter,
    hama,
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
  ]);

  static final Map<BeadPaletteId, BeadPalette> _byId = Map.unmodifiable({
    for (final palette in all) palette.id: palette,
  });

  static BeadPalette get defaultPalette => mard291;

  static BeadPalette byId(BeadPaletteId id) => _byId[id] ?? defaultPalette;

  /// Projects saved before palette IDs were introduced used Artkal. If those
  /// codes do not match Artkal, detect the first complete brand match so older
  /// MARD/custom imports remain readable too.
  static BeadPalette forStoredProject(String? id, Iterable<String> codes) {
    final parsed = BeadPaletteIdStorage.tryParse(id);
    final codeList = codes.toList();
    if (parsed != null) {
      final storedPalette = byId(parsed);
      if (codeList.every(storedPalette.byCode.containsKey)) {
        return storedPalette;
      }
    }
    for (final palette in all) {
      if (codeList.every(palette.byCode.containsKey)) return palette;
    }
    return artkal397;
  }

  static BeadPalette _build({
    required BeadPaletteId id,
    required String shortName,
    required String displayName,
    required String description,
    required double pitchMm,
    required List<RawPaletteColorData> data,
    List<String> searchTerms = const [],
    bool isReference = false,
  }) {
    final colors = <BeadColor>[];
    for (var index = 0; index < data.length; index++) {
      final item = data[index];
      final red = (item.argb >> 16) & 0xFF;
      final green = (item.argb >> 8) & 0xFF;
      final blue = item.argb & 0xFF;
      final slash = item.name.indexOf('/');
      final nameCn = slash < 0
          ? item.name.trim()
          : item.name.substring(0, slash).trim();
      final nameEn = slash < 0
          ? item.name.trim()
          : item.name.substring(slash + 1).trim();
      final lab = ColorScience.rgbToLab(red, green, blue);
      colors.add(
        BeadColor(
          id: id.index * 10000 + index + 1,
          brand: shortName,
          series: _seriesOf(item.code, item.family),
          code: item.code,
          nameCn: nameCn,
          nameEn: nameEn,
          red: red,
          green: green,
          blue: blue,
          lab: LabColor(lab.l.clamp(0, 100).toDouble(), lab.a, lab.b),
          sizeMm: pitchMm,
          type: _typeName(item.family),
          isMeasured: id == BeadPaletteId.perler,
        ),
      );
    }
    return BeadPalette(
      id: id,
      shortName: shortName,
      displayName: displayName,
      description: description,
      pitchMm: pitchMm,
      colors: colors,
      searchTerms: searchTerms,
      isReference: isReference,
    );
  }

  static BeadPalette _reference(
    BeadPaletteId id,
    String shortName,
    String displayName,
    BeadPalette source,
    List<String> searchTerms,
  ) => _alias(
    id: id,
    source: source,
    shortName: shortName,
    displayName: displayName,
    description: '兼容参考色表；可导入官方色卡覆盖',
    searchTerms: searchTerms,
  );

  static BeadPalette _alias({
    required BeadPaletteId id,
    required BeadPalette source,
    required String shortName,
    required String displayName,
    required String description,
    List<String> searchTerms = const [],
    double? pitchMm,
    bool isReference = true,
  }) {
    final colors = <BeadColor>[
      for (var index = 0; index < source.colors.length; index++)
        BeadColor(
          id: id.index * 10000 + index + 1,
          brand: shortName,
          series: source.colors[index].series,
          code: source.colors[index].code,
          nameCn: source.colors[index].nameCn,
          nameEn: source.colors[index].nameEn,
          red: source.colors[index].red,
          green: source.colors[index].green,
          blue: source.colors[index].blue,
          lab: source.colors[index].lab,
          sizeMm: pitchMm ?? source.pitchMm,
          type: source.colors[index].type,
          isMeasured: source.colors[index].isMeasured && !isReference,
        ),
    ];
    return BeadPalette(
      id: id,
      shortName: shortName,
      displayName: displayName,
      description: description,
      pitchMm: pitchMm ?? source.pitchMm,
      colors: colors,
      searchTerms: searchTerms,
      isReference: isReference,
    );
  }

  static String _seriesOf(String code, String family) =>
      RegExp(r'^[A-Za-z]+').firstMatch(code)?.group(0)?.toUpperCase() ?? family;

  static String _typeName(String family) => switch (family) {
    'pearl' => '珠光',
    'translucent' => '透明',
    'neon' => '荧光',
    'metallic' => '金属',
    'glitter' => '闪粉',
    'glow' => '夜光',
    'striped' => '条纹',
    _ => '标准实色',
  };
}
