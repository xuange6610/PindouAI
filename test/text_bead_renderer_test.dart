import 'dart:io';

import 'package:bead_ai_designer/services/text_bead_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var cjkTestFont = 'sans-serif';

  setUpAll(() async {
    if (!Platform.isWindows) return;
    final file = File(r'C:\Windows\Fonts\simhei.ttf');
    if (!await file.exists()) return;
    const family = 'TextBeadTestChinese';
    final bytes = await file.readAsBytes();
    await (FontLoader(family)..addFont(
          Future.value(ByteData.sublistView(Uint8List.fromList(bytes))),
        ))
        .load();
    cjkTestFont = family;
  });

  testWidgets('较长中文会自动分行并保留上下两行清晰笔画', (tester) async {
    final result = (await tester.runAsync(
      () => TextBeadRenderer.render(
        text: '拼豆汉字生成',
        width: 48,
        height: 32,
        foreground: const Color(0xFFE53935),
        background: Colors.white,
        fontFamily: cjkTestFont,
        bold: true,
        italic: false,
      ),
    ))!;

    expect(result.arrangedText, contains('\n'));
    expect(result.fontSizeInCells, greaterThanOrEqualTo(8));
    final foregroundCount = result.foregroundMask
        .where((value) => value)
        .length;
    expect(foregroundCount, greaterThan(45));
    expect(foregroundCount, lessThan(result.width * result.height * 0.60));
    final top = result.foregroundMask.take(result.width * 16);
    final bottom = result.foregroundMask.skip(result.width * 16);
    expect(top.where((value) => value).length, greaterThan(15));
    expect(bottom.where((value) => value).length, greaterThan(15));
  });

  testWidgets('文字拼豆输出保持逐格二值颜色而不产生模糊过渡色', (tester) async {
    const foreground = Color(0xFF212121);
    const background = Color(0xFFFFFFFF);
    final result = (await tester.runAsync(
      () => TextBeadRenderer.render(
        text: '清晰',
        width: 32,
        height: 32,
        foreground: foreground,
        background: background,
        fontFamily: cjkTestFont,
        bold: true,
        italic: false,
      ),
    ))!;
    final decoded = img.decodePng(result.bytes)!;
    final colors = <int>{};
    for (final pixel in decoded) {
      colors.add(
        (pixel.r.toInt() << 16) | (pixel.g.toInt() << 8) | pixel.b.toInt(),
      );
    }
    expect(colors, {
      foreground.toARGB32() & 0xFFFFFF,
      background.toARGB32() & 0xFFFFFF,
    });
    expect(decoded.width % result.width, 0);
    expect(decoded.height % result.height, 0);
    final scaleX = decoded.width ~/ result.width;
    final scaleY = decoded.height ~/ result.height;
    expect(scaleX, greaterThanOrEqualTo(4));
    expect(scaleY, scaleX);
    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        final expected = result.foregroundMask[y * result.width + x]
            ? foreground.toARGB32() & 0xFFFFFF
            : background.toARGB32() & 0xFFFFFF;
        for (final sample in [
          (x * scaleX, y * scaleY),
          ((x + 1) * scaleX - 1, y * scaleY),
          (x * scaleX, (y + 1) * scaleY - 1),
          ((x + 1) * scaleX - 1, (y + 1) * scaleY - 1),
        ]) {
          final pixel = decoded.getPixel(sample.$1, sample.$2);
          final actual =
              (pixel.r.toInt() << 16) |
              (pixel.g.toInt() << 8) |
              pixel.b.toInt();
          expect(actual, expected);
        }
      }
    }
    expect(result.foregroundMask.where((value) => value), isNotEmpty);
  });

  testWidgets('四个中文会在方形小板上排成两行并保持每个字的独立轮廓', (tester) async {
    final result = (await tester.runAsync(
      () => TextBeadRenderer.render(
        text: '文字拼豆',
        width: 29,
        height: 29,
        foreground: const Color(0xFF212121),
        background: Colors.white,
        fontFamily: cjkTestFont,
        bold: true,
        italic: false,
      ),
    ))!;

    expect(result.arrangedText, '文字\n拼豆');
    for (var row = 0; row < 2; row++) {
      for (var column = 0; column < 2; column++) {
        var foregroundCount = 0;
        var backgroundCount = 0;
        final startX = column * result.width ~/ 2;
        final endX = (column + 1) * result.width ~/ 2;
        final startY = row * result.height ~/ 2;
        final endY = (row + 1) * result.height ~/ 2;
        for (var y = startY; y < endY; y++) {
          for (var x = startX; x < endX; x++) {
            if (result.foregroundMask[y * result.width + x]) {
              foregroundCount++;
            } else {
              backgroundCount++;
            }
          }
        }
        expect(foregroundCount, greaterThan(12));
        expect(backgroundCount, greaterThan(25));
      }
    }
  });

  testWidgets('常用中文在较小画板上仍保留足够的横竖笔画与左右字符', (tester) async {
    final result = (await tester.runAsync(
      () => TextBeadRenderer.render(
        text: '你好',
        width: 32,
        height: 24,
        foreground: const Color(0xFF212121),
        background: Colors.white,
        fontFamily: cjkTestFont,
        bold: true,
        italic: false,
      ),
    ))!;

    final occupiedRows = <int>{};
    final occupiedColumns = <int>{};
    var leftInk = 0;
    var rightInk = 0;
    for (var index = 0; index < result.foregroundMask.length; index++) {
      if (!result.foregroundMask[index]) continue;
      final x = index % result.width;
      final y = index ~/ result.width;
      occupiedColumns.add(x);
      occupiedRows.add(y);
      if (x < result.width ~/ 2) {
        leftInk++;
      } else {
        rightInk++;
      }
    }
    expect(occupiedRows.length, greaterThanOrEqualTo(12));
    expect(occupiedColumns.length, greaterThanOrEqualTo(22));
    expect(leftInk, greaterThan(35));
    expect(rightInk, greaterThan(35));
  });

  testWidgets('四宫格为每个字生成独立清晰蒙版并支持单字位移', (tester) async {
    final base = (await tester.runAsync(
      () => TextBeadRenderer.render(
        text: '文字拼豆',
        width: 40,
        height: 40,
        foreground: const Color(0xFF212121),
        background: Colors.white,
        fontFamily: cjkTestFont,
        bold: true,
        italic: false,
        layout: TextBeadLayout.fourGrid,
        characterOffsets: const [
          Offset.zero,
          Offset.zero,
          Offset.zero,
          Offset.zero,
        ],
      ),
    ))!;
    final moved = (await tester.runAsync(
      () => TextBeadRenderer.render(
        text: '文字拼豆',
        width: 40,
        height: 40,
        foreground: const Color(0xFF212121),
        background: Colors.white,
        fontFamily: cjkTestFont,
        bold: true,
        italic: false,
        layout: TextBeadLayout.fourGrid,
        characterOffsets: const [
          Offset(3, 2),
          Offset.zero,
          Offset.zero,
          Offset.zero,
        ],
      ),
    ))!;

    expect(base.arrangedText, '文字\n拼豆');
    expect(base.characterMasks, hasLength(4));
    expect(base.characterMasks.every((mask) => mask.cells.isNotEmpty), isTrue);
    expect(
      moved.characterMasks.first.cells,
      isNot(base.characterMasks.first.cells),
    );
    expect(
      moved.characterMasks.first.bounds.left,
      greaterThan(base.characterMasks.first.bounds.left),
    );
    expect(
      moved.characterMasks.skip(1).map((mask) => mask.cells),
      base.characterMasks.skip(1).map((mask) => mask.cells),
    );
  });

  testWidgets('横向和竖向模式按用户选择排列字符', (tester) async {
    final horizontal = (await tester.runAsync(
      () => TextBeadRenderer.render(
        text: 'ABC',
        width: 48,
        height: 32,
        foreground: Colors.black,
        background: Colors.white,
        fontFamily: 'sans-serif',
        bold: true,
        italic: false,
        layout: TextBeadLayout.horizontal,
      ),
    ))!;
    final vertical = (await tester.runAsync(
      () => TextBeadRenderer.render(
        text: 'ABC',
        width: 32,
        height: 48,
        foreground: Colors.black,
        background: Colors.white,
        fontFamily: 'sans-serif',
        bold: true,
        italic: false,
        layout: TextBeadLayout.vertical,
      ),
    ))!;

    expect(horizontal.arrangedText, 'ABC');
    expect(vertical.arrangedText, 'A\nB\nC');
    expect(horizontal.characterMasks, hasLength(3));
    expect(vertical.characterMasks, hasLength(3));
    expect(
      vertical.characterMasks[1].bounds.top,
      greaterThan(vertical.characterMasks[0].bounds.bottom),
    );
  });
}
