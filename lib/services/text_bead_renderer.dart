import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

enum TextBeadLayout { automatic, horizontal, vertical, fourGrid }

class TextBeadCharacterMask {
  const TextBeadCharacterMask({
    required this.character,
    required this.cells,
    required this.bounds,
    required this.renderOffset,
  });

  final String character;
  final List<int> cells;
  final Rect bounds;
  final Offset renderOffset;
}

class TextBeadRenderResult {
  const TextBeadRenderResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.foregroundMask,
    required this.arrangedText,
    required this.fontSizeInCells,
    this.characterMasks = const [],
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final List<bool> foregroundMask;
  final String arrangedText;
  final double fontSizeInCells;
  final List<TextBeadCharacterMask> characterMasks;
}

abstract final class TextBeadRenderer {
  static const _fontFallback = <String>[
    'NotoSansSC',
    'Noto Sans CJK SC',
    'Noto Sans SC',
    'Microsoft YaHei',
    'PingFang SC',
    'sans-serif',
  ];

  static String arrangeText(String input, int width, int height) {
    final normalized = input.trim().isEmpty ? 'LOVE' : input.trim();
    if (normalized.contains('\n')) return normalized;
    final runes = normalized.runes.toList(growable: false);
    if (!runes.any(_isCjk)) return normalized;

    final oneLineCellSize = math.min(
      width * 0.90 / runes.length,
      height * 0.84,
    );
    var bestRows = 1;
    var bestCellSize = oneLineCellSize;
    for (var rows = 2; rows <= math.min(4, runes.length); rows++) {
      final columns = (runes.length / rows).ceil();
      final cellSize = math.min(width * 0.90 / columns, height * 0.84 / rows);
      if (cellSize > bestCellSize * 1.12) {
        bestRows = rows;
        bestCellSize = cellSize;
      }
    }
    if (bestRows == 1) return normalized;

    final columns = (runes.length / bestRows).ceil();
    final lines = <String>[];
    for (var start = 0; start < runes.length; start += columns) {
      lines.add(
        String.fromCharCodes(
          runes.sublist(start, math.min(start + columns, runes.length)),
        ),
      );
    }
    return lines.join('\n');
  }

  static List<String> editableCharacters(String input) {
    final normalized = input.trim().isEmpty ? 'LOVE' : input.trim();
    return normalized.runes
        .where((rune) => rune != 10 && rune != 13)
        .map(String.fromCharCode)
        .toList(growable: false);
  }

  static Future<TextBeadRenderResult> render({
    required String text,
    required int width,
    required int height,
    required Color foreground,
    required Color background,
    required String fontFamily,
    required bool bold,
    required bool italic,
    double offsetX = 0,
    double offsetY = 0,
    TextBeadLayout layout = TextBeadLayout.automatic,
    List<Offset> characterOffsets = const [],
  }) async {
    if (width < 1 || height < 1) {
      throw ArgumentError('文字画板尺寸必须大于 0');
    }
    if (layout != TextBeadLayout.automatic || characterOffsets.isNotEmpty) {
      return _renderEditable(
        text: text,
        width: width,
        height: height,
        foreground: foreground,
        background: background,
        fontFamily: fontFamily,
        bold: bold,
        italic: italic,
        layout: layout == TextBeadLayout.automatic
            ? TextBeadLayout.horizontal
            : layout,
        characterOffsets: characterOffsets,
      );
    }
    final arranged = arrangeText(text, width, height);
    final containsCjk = arranged.runes.any(_isCjk);
    // Render at the final bead-grid resolution so font hinting decides each
    // bead directly. Oversampling and coverage thresholds merge nearby CJK
    // strokes and make compact characters unreadable.
    final renderWidth = width;
    final renderHeight = height;
    final contentWidth = renderWidth * 0.98;
    final contentHeight = renderHeight * 0.96;
    final expectedLines = arranged.split('\n').length;

    TextPainter painter(double fontSize) {
      return TextPainter(
        text: TextSpan(
          text: arranged,
          style: TextStyle(
            color: foreground,
            fontSize: fontSize,
            height: 1,
            letterSpacing: 0,
            fontFamily: fontFamily == 'sans-serif' ? null : fontFamily,
            fontFamilyFallback: _fontFallback,
            fontWeight: bold
                ? (containsCjk ? FontWeight.w600 : FontWeight.w800)
                : FontWeight.w400,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: expectedLines,
        textWidthBasis: TextWidthBasis.parent,
      )..layout(maxWidth: contentWidth);
    }

    var low = 2.0;
    var high = renderHeight.toDouble();
    for (var iteration = 0; iteration < 18; iteration++) {
      final candidateSize = (low + high) / 2;
      final candidate = painter(candidateSize);
      final metrics = candidate.computeLineMetrics();
      final widest = metrics.fold<double>(
        0,
        (value, line) => math.max(value, line.width),
      );
      final fits =
          !candidate.didExceedMaxLines &&
          metrics.length <= expectedLines &&
          widest <= contentWidth &&
          candidate.height <= contentHeight;
      candidate.dispose();
      if (fits) {
        low = candidateSize;
      } else {
        high = candidateSize;
      }
    }
    final textPainter = painter(low);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(background, BlendMode.src);
    final left = renderWidth * 0.01 + offsetX;
    final top = ((renderHeight - textPainter.height) / 2 + offsetY).clamp(
      -renderHeight.toDouble(),
      renderHeight.toDouble(),
    );
    textPainter.paint(canvas, Offset(left, top));
    textPainter.dispose();
    final renderedImage = await recorder.endRecording().toImage(
      renderWidth,
      renderHeight,
    );
    final byteData = await renderedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    renderedImage.dispose();
    if (byteData == null) throw StateError('无法生成文字图片');
    final highResolution = img.decodePng(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
    );
    if (highResolution == null) throw StateError('无法解析文字图片');

    final foregroundRgb = _rgb(foreground);
    final backgroundRgb = _rgb(background);
    final mask = List<bool>.filled(width * height, false);
    final fontSizeInCells = low;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        final pixel = highResolution.getPixel(x, y);
        final foregroundDistance =
            (pixel.r.toDouble() - foregroundRgb.r).abs() +
            (pixel.g.toDouble() - foregroundRgb.g).abs() +
            (pixel.b.toDouble() - foregroundRgb.b).abs();
        final backgroundDistance =
            (pixel.r.toDouble() - backgroundRgb.r).abs() +
            (pixel.g.toDouble() - backgroundRgb.g).abs() +
            (pixel.b.toDouble() - backgroundRgb.b).abs();
        mask[index] = foregroundDistance < backgroundDistance;
      }
    }

    final crisp = img.Image(width: width, height: height, numChannels: 4);
    for (var index = 0; index < mask.length; index++) {
      final color = mask[index] ? foregroundRgb : backgroundRgb;
      crisp.setPixelRgba(
        index % width,
        index ~/ width,
        color.r,
        color.g,
        color.b,
        255,
      );
    }
    final previewScale = (960 ~/ math.max(width, height)).clamp(4, 12);
    final preview = img.copyResize(
      crisp,
      width: width * previewScale,
      height: height * previewScale,
      interpolation: img.Interpolation.nearest,
    );
    return TextBeadRenderResult(
      bytes: Uint8List.fromList(img.encodePng(preview, level: 6)),
      width: width,
      height: height,
      foregroundMask: List.unmodifiable(mask),
      arrangedText: arranged,
      fontSizeInCells: fontSizeInCells,
    );
  }

  static Future<TextBeadRenderResult> _renderEditable({
    required String text,
    required int width,
    required int height,
    required Color foreground,
    required Color background,
    required String fontFamily,
    required bool bold,
    required bool italic,
    required TextBeadLayout layout,
    required List<Offset> characterOffsets,
  }) async {
    final characters = editableCharacters(text);
    final count = characters.length;
    final rows = switch (layout) {
      TextBeadLayout.horizontal => 1,
      TextBeadLayout.vertical => count,
      TextBeadLayout.fourGrid => (count / 2).ceil(),
      TextBeadLayout.automatic => 1,
    };
    final columns = switch (layout) {
      TextBeadLayout.horizontal => count,
      TextBeadLayout.vertical => 1,
      TextBeadLayout.fourGrid => math.min(2, count),
      TextBeadLayout.automatic => count,
    };
    final safeRows = math.max(1, rows);
    final safeColumns = math.max(1, columns);
    final contentLeft = width * 0.02;
    final contentTop = height * 0.03;
    final slotWidth = width * 0.96 / safeColumns;
    final slotHeight = height * 0.94 / safeRows;
    final containsCjk = characters.any((value) => value.runes.any(_isCjk));

    TextPainter characterPainter(String character, double fontSize) {
      return TextPainter(
        text: TextSpan(
          text: character,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            height: 1,
            letterSpacing: 0,
            fontFamily: fontFamily == 'sans-serif' ? null : fontFamily,
            fontFamilyFallback: _fontFallback,
            fontWeight: bold
                ? (containsCjk ? FontWeight.w600 : FontWeight.w800)
                : FontWeight.w400,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        textWidthBasis: TextWidthBasis.longestLine,
      )..layout(maxWidth: slotWidth * 0.94);
    }

    var low = 1.0;
    var high = math.max(2.0, slotHeight);
    for (var iteration = 0; iteration < 16; iteration++) {
      final candidateSize = (low + high) / 2;
      var fits = true;
      for (final character in characters) {
        if (character.trim().isEmpty) continue;
        final painter = characterPainter(character, candidateSize);
        final lineWidth = painter.computeLineMetrics().fold<double>(
          0,
          (value, line) => math.max(value, line.width),
        );
        if (painter.didExceedMaxLines ||
            lineWidth > slotWidth * 0.92 ||
            painter.height > slotHeight * 0.88) {
          fits = false;
        }
        painter.dispose();
        if (!fits) break;
      }
      if (fits) {
        low = candidateSize;
      } else {
        high = candidateSize;
      }
    }

    final masks = <TextBeadCharacterMask>[];
    final combined = List<bool>.filled(width * height, false);
    for (var index = 0; index < characters.length; index++) {
      final character = characters[index];
      final row = layout == TextBeadLayout.horizontal
          ? 0
          : index ~/ safeColumns;
      final column = layout == TextBeadLayout.vertical
          ? 0
          : index % safeColumns;
      final suppliedOffset = index < characterOffsets.length
          ? characterOffsets[index]
          : Offset.zero;
      final painter = characterPainter(character, low);
      final lineWidth = painter.computeLineMetrics().fold<double>(
        0,
        (value, line) => math.max(value, line.width),
      );
      final left =
          contentLeft +
          column * slotWidth +
          (slotWidth - lineWidth) / 2 +
          suppliedOffset.dx;
      final top =
          contentTop +
          row * slotHeight +
          (slotHeight - painter.height) / 2 +
          suppliedOffset.dy;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawColor(Colors.transparent, BlendMode.src);
      painter.paint(canvas, Offset(left, top));
      painter.dispose();
      final rendered = await recorder.endRecording().toImage(width, height);
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      rendered.dispose();
      if (data == null) throw StateError('无法读取单字像素');
      final rgba = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final cells = <int>[];
      var minX = width;
      var minY = height;
      var maxX = -1;
      var maxY = -1;
      for (var cellIndex = 0; cellIndex < width * height; cellIndex++) {
        if (rgba[cellIndex * 4 + 3] < 56) continue;
        cells.add(cellIndex);
        combined[cellIndex] = true;
        final x = cellIndex % width;
        final y = cellIndex ~/ width;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
      final fallbackBounds = Rect.fromLTWH(
        contentLeft + column * slotWidth + suppliedOffset.dx,
        contentTop + row * slotHeight + suppliedOffset.dy,
        slotWidth,
        slotHeight,
      );
      masks.add(
        TextBeadCharacterMask(
          character: character,
          cells: List.unmodifiable(cells),
          bounds: maxX >= minX
              ? Rect.fromLTRB(
                  minX.toDouble(),
                  minY.toDouble(),
                  (maxX + 1).toDouble(),
                  (maxY + 1).toDouble(),
                )
              : fallbackBounds,
          renderOffset: suppliedOffset,
        ),
      );
    }

    final foregroundRgb = _rgb(foreground);
    final backgroundRgb = _rgb(background);
    final crisp = img.Image(width: width, height: height, numChannels: 4);
    for (var index = 0; index < combined.length; index++) {
      final color = combined[index] ? foregroundRgb : backgroundRgb;
      crisp.setPixelRgba(
        index % width,
        index ~/ width,
        color.r,
        color.g,
        color.b,
        255,
      );
    }
    final previewScale = (960 ~/ math.max(width, height)).clamp(4, 12);
    final preview = img.copyResize(
      crisp,
      width: width * previewScale,
      height: height * previewScale,
      interpolation: img.Interpolation.nearest,
    );
    final arranged = switch (layout) {
      TextBeadLayout.horizontal => characters.join(),
      TextBeadLayout.vertical => characters.join('\n'),
      TextBeadLayout.fourGrid => [
        for (var start = 0; start < count; start += safeColumns)
          characters
              .sublist(start, math.min(start + safeColumns, count))
              .join(),
      ].join('\n'),
      TextBeadLayout.automatic => characters.join(),
    };
    return TextBeadRenderResult(
      bytes: Uint8List.fromList(img.encodePng(preview, level: 6)),
      width: width,
      height: height,
      foregroundMask: List.unmodifiable(combined),
      arrangedText: arranged,
      fontSizeInCells: low,
      characterMasks: List.unmodifiable(masks),
    );
  }

  static bool _isCjk(int rune) =>
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF);

  static ({int r, int g, int b}) _rgb(Color color) {
    final value = color.toARGB32();
    return (r: (value >> 16) & 0xFF, g: (value >> 8) & 0xFF, b: value & 0xFF);
  }
}
