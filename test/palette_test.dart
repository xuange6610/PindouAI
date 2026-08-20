import 'package:bead_ai_designer/data/bead_palettes.dart';
import 'package:bead_ai_designer/data/mard_palette.dart';
import 'package:bead_ai_designer/models/bead_palette.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('常见品牌和系列均可选择且默认使用 MARD 291', () {
    expect(BeadPalettes.defaultPalette.id, BeadPaletteId.mard291);
    expect(BeadPalettes.all, hasLength(BeadPaletteId.values.length));
    expect(BeadPalettes.artkal397.colors, hasLength(397));
    expect(BeadPalettes.mard291.colors, hasLength(291));
    expect(BeadPalettes.coco291.colors, hasLength(291));
    expect(BeadPalettes.perler.colors, hasLength(103));
    expect(BeadPalettes.hama.colors, hasLength(89));
    for (final palette in BeadPalettes.all) {
      expect(
        palette.colors.map((color) => color.code).toSet(),
        hasLength(palette.colors.length),
        reason: '${palette.shortName} 色号必须唯一',
      );
      expect(palette.byCode, hasLength(palette.colors.length));
      expect(
        palette.colors.every((color) => color.brand == palette.shortName),
        isTrue,
      );
    }
    for (final query in const [
      '马德',
      '可可拼豆',
      'Artkal Mini',
      '派乐透明',
      '宜家拼豆',
      '漫漫',
      'XW',
      '黄豆豆',
      '咪小窝',
      '优肯',
      '魔法豆豆',
      '动木木',
    ]) {
      expect(
        BeadPalettes.all.any((palette) => palette.matchesQuery(query)),
        isTrue,
        reason: '$query 必须能通过模糊搜索找到',
      );
    }
  });

  test('常用色数子集和规格系列保持独立存储 ID', () {
    expect(BeadPalettes.byId(BeadPaletteId.mard221).colors, hasLength(221));
    expect(BeadPalettes.byId(BeadPaletteId.coco100).colors, hasLength(100));
    expect(BeadPalettes.byId(BeadPaletteId.coco200).colors, hasLength(200));
    expect(BeadPalettes.byId(BeadPaletteId.hamaMini).pitchMm, 2.6);
    expect(BeadPaletteIdStorage.tryParse('dongmumu'), BeadPaletteId.dongmumu);
  });

  test('无品牌字段的旧作品仍优先识别为原 Artkal 色库', () {
    final palette = BeadPalettes.forStoredProject(null, const ['MA1', 'S01']);
    expect(palette.id, BeadPaletteId.artkal397);
    expect(
      BeadPalettes.forStoredProject(null, const ['A1']).id,
      BeadPaletteId.mard291,
    );
  });

  test('Artkal 主色库有 300 个唯一色号和完整字段', () {
    expect(MardPalette.colors, hasLength(300));
    expect(
      MardPalette.colors.map((color) => color.code).toSet(),
      hasLength(300),
    );
    expect(MardPalette.byCode['MA1']?.nameCn, '淡黄色');
    expect(MardPalette.byCode['S01']?.nameEn, 'White');
    // Legacy aliases keep existing MARD projects readable after the upgrade.
    expect(MardPalette.byCode['A1'], isNotNull);
    expect(MardPalette.byCode['H23'], isNotNull);
    for (final color in MardPalette.colors) {
      expect(color.brand, 'Artkal');
      expect(color.hex, matches(RegExp(r'^#[0-9A-F]{6}$')));
      expect(color.sizeMm, anyOf(2.6, 5.0));
      expect(color.lab.l, inInclusiveRange(0, 100));
    }
  });

  test('Artkal Mini 与 S 系列共同构成 300 色且旧色可映射到新画板', () {
    expect(
      MardPalette.colors.where((color) => color.code.startsWith('M')),
      hasLength(221),
    );
    expect(
      MardPalette.colors.where((color) => !color.code.startsWith('M')),
      hasLength(79),
    );
    expect(
      MardPalette.indexFor(MardPalette.byCode['A8']!),
      inInclusiveRange(0, 299),
    );
  });
}
