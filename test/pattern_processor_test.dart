import 'dart:typed_data';

import 'package:bead_ai_designer/data/bead_palettes.dart';
import 'package:bead_ai_designer/data/mard_palette.dart';
import 'package:bead_ai_designer/models/bead_palette.dart';
import 'package:bead_ai_designer/models/bead_pattern.dart';
import 'package:bead_ai_designer/services/export_service.dart';
import 'package:bead_ai_designer/services/pattern_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('图片转换、色号映射、统计与预览导出闭环', () async {
    final source = img.Image(width: 8, height: 8);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgba(
          x,
          y,
          x < 4 ? 246 : 45,
          y < 4 ? 191 : 86,
          x < 4 ? 72 : 144,
          255,
        );
      }
    }
    final bytes = Uint8List.fromList(img.encodePng(source));
    final pattern = await PatternProcessor().process(
      bytes,
      const ProcessingOptions(
        size: 20,
        maxColors: 8,
        portraitMode: false,
        smoothing: true,
      ),
    );

    expect(pattern.width, 20);
    expect(pattern.height, 20);
    expect(pattern.cells, hasLength(400));
    expect(
      pattern.counts.values.fold<int>(0, (sum, value) => sum + value),
      400,
    );
    expect(pattern.colors.length, lessThanOrEqualTo(8));
    expect(
      pattern.cells.every((index) => index < pattern.colors.length),
      isTrue,
    );

    final preview = await ExportService().renderPreview(pattern);
    expect(img.decodePng(preview), isNotNull);

    final codeGrid = await ExportService().renderCodeGrid(pattern);
    final decodedGrid = img.decodePng(codeGrid);
    expect(decodedGrid, isNotNull);
    expect(decodedGrid!.width, 641);
    expect(decodedGrid.height, 641);
  });

  test('后台处理任务可以立即取消', () async {
    final source = img.Image(width: 32, height: 32);
    img.fill(source, color: img.ColorRgb8(210, 90, 80));
    final operation = await PatternProcessor().start(
      Uint8List.fromList(img.encodePng(source)),
      const ProcessingOptions(
        size: 200,
        maxColors: 96,
        portraitMode: false,
        smoothing: true,
      ),
    );
    operation.cancel();
    await expectLater(
      operation.result,
      throwsA(isA<ProcessingCancelledException>()),
    );
  });

  test('可选 AI 抠图会保留主体并把背景变为空白豆位', () async {
    final source = img.Image(width: 80, height: 80);
    img.fill(source, color: img.ColorRgb8(248, 248, 248));
    img.fillRect(
      source,
      x1: 22,
      y1: 16,
      x2: 58,
      y2: 66,
      color: img.ColorRgb8(210, 50, 65),
    );
    final bytes = Uint8List.fromList(img.encodePng(source));
    final pattern = await PatternProcessor().process(
      bytes,
      const ProcessingOptions(
        size: 40,
        maxColors: 8,
        portraitMode: false,
        smoothing: true,
        removeBackground: true,
      ),
    );

    expect(pattern.backgroundRemoved, isTrue);
    expect(pattern.cells.where((cell) => cell < 0), isNotEmpty);
    expect(pattern.totalBeads, greaterThan(100));
    expect(pattern.totalBeads, lessThan(1200));
    expect(
      pattern.counts.values.fold<int>(0, (sum, value) => sum + value),
      pattern.totalBeads,
    );
  });

  test('自定义长方形画板按指定宽高生成', () async {
    final source = img.Image(width: 60, height: 40);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x * 4, y * 6, 150);
      }
    }
    final pattern = await PatternProcessor().process(
      Uint8List.fromList(img.encodePng(source)),
      const ProcessingOptions(
        size: 37,
        height: 23,
        maxColors: 16,
        portraitMode: false,
        smoothing: true,
      ),
    );
    expect(pattern.width, 37);
    expect(pattern.height, 23);
    expect(pattern.cells, hasLength(851));
  });

  test('不同方案种子会为复杂图像生成可比较的颜色方案', () async {
    final source = img.Image(width: 96, height: 72);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(
          x,
          y,
          (x * 7 + y * 3) % 256,
          (x * 2 + y * 9) % 256,
          (x * 11 + y * 5) % 256,
        );
      }
    }
    final bytes = Uint8List.fromList(img.encodePng(source));
    final first = await PatternProcessor().process(
      bytes,
      const ProcessingOptions(
        size: 40,
        height: 30,
        maxColors: 16,
        portraitMode: false,
        smoothing: true,
        variantSeed: 101,
      ),
    );
    final second = await PatternProcessor().process(
      bytes,
      const ProcessingOptions(
        size: 40,
        height: 30,
        maxColors: 16,
        portraitMode: false,
        smoothing: true,
        variantSeed: 202,
      ),
    );
    expect(
      first.colors.map((color) => color.code).join(',') ==
              second.colors.map((color) => color.code).join(',') &&
          first.cells.join(',') == second.cells.join(','),
      isFalse,
    );
    final changedCells = List<int>.generate(
      first.cells.length,
      (index) => first.cells[index] == second.cells[index] ? 0 : 1,
    ).fold<int>(0, (sum, value) => sum + value);
    expect(changedCells / first.cells.length, greaterThan(0.05));
  });

  test('Artkal 图表中的原色可以无偏色映射回同一色号', () async {
    final expected = MardPalette.byCode['MA20']!;
    final source = img.Image(width: 48, height: 48);
    img.fill(
      source,
      color: img.ColorRgb8(expected.red, expected.green, expected.blue),
    );
    final pattern = await PatternProcessor().process(
      Uint8List.fromList(img.encodePng(source)),
      const ProcessingOptions(
        size: 29,
        maxColors: 300,
        portraitMode: false,
        smoothing: false,
        paletteId: BeadPaletteId.artkal397,
      ),
    );
    final usedCodes = pattern.counts.keys.map(
      (index) => pattern.colors[index].code,
    );
    expect(usedCodes, [expected.code]);
  });

  test('默认使用 MARD 291，也可指定 COCO 色卡参与真实匹配', () async {
    final expected = BeadPalettes.coco291.byCode['Z23']!;
    final source = img.Image(width: 32, height: 32);
    img.fill(
      source,
      color: img.ColorRgb8(expected.red, expected.green, expected.blue),
    );
    final bytes = Uint8List.fromList(img.encodePng(source));
    final defaults = await PatternProcessor().process(
      bytes,
      const ProcessingOptions(
        size: 20,
        maxColors: 16,
        portraitMode: false,
        smoothing: false,
      ),
    );
    expect(defaults.paletteId, BeadPaletteId.mard291);
    expect(defaults.colors.every((color) => color.brand == 'MARD'), isTrue);

    final coco = await PatternProcessor().process(
      bytes,
      const ProcessingOptions(
        size: 20,
        maxColors: 291,
        portraitMode: false,
        smoothing: false,
        paletteId: BeadPaletteId.coco291,
      ),
    );
    expect(coco.paletteId, BeadPaletteId.coco291);
    expect(coco.colors.every((color) => color.brand == 'COCO'), isTrue);
    expect(
      coco.counts.keys.map((index) => coco.colors[index].code),
      contains(expected.code),
    );
  });

  test('默认完整保留非正方形原图构图而不是静默裁掉两侧', () async {
    final source = img.Image(width: 80, height: 40);
    img.fill(source, color: img.ColorRgb8(30, 140, 220));
    img.fillRect(
      source,
      x1: 0,
      y1: 0,
      x2: 7,
      y2: 39,
      color: img.ColorRgb8(240, 40, 50),
    );
    img.fillRect(
      source,
      x1: 72,
      y1: 0,
      x2: 79,
      y2: 39,
      color: img.ColorRgb8(40, 220, 80),
    );
    final pattern = await PatternProcessor().process(
      Uint8List.fromList(img.encodePng(source)),
      const ProcessingOptions(
        size: 40,
        height: 40,
        maxColors: 16,
        portraitMode: false,
        smoothing: false,
      ),
    );
    expect(pattern.cells.take(40).every((cell) => cell < 0), isTrue);
    expect(pattern.cells.skip(39 * 40).every((cell) => cell < 0), isTrue);
    final middle = pattern.cells.skip(10 * 40).take(20 * 40);
    expect(middle.where((cell) => cell >= 0), isNotEmpty);
  });

  test('最少预留格子只计算图案实际占用边界', () {
    final pattern = BeadPattern(
      id: 'occupied-bounds',
      title: '边界测试',
      width: 6,
      height: 5,
      colors: [MardPalette.colors.first],
      cells: [
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        0,
        0,
        0,
        -1,
        -1,
        -1,
        0,
        0,
        0,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
      ],
      sourceBytes: Uint8List(0),
      createdAt: DateTime(2026),
      requestedColorCount: 1,
      portraitMode: false,
    );
    expect(pattern.minimumBoardSize, '3×2 格');
    expect(pattern.occupiedBounds.left, 1);
    expect(pattern.occupiedBounds.top, 1);
  });
}
