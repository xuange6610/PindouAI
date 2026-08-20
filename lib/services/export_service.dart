import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../data/bead_palettes.dart';
import '../models/bead_pattern.dart';

class ExportService {
  static const _mediaChannel = MethodChannel(
    'com.xuan.bead_ai_designer/media',
  );

  Future<Uint8List> renderPreview(BeadPattern pattern) async {
    return compute(_renderPreviewIsolate, _patternPayload(pattern));
  }

  Future<Uint8List> renderPixelPreview(BeadPattern pattern) async {
    return compute(_renderPixelPreviewIsolate, _patternPayload(pattern));
  }

  Future<Uint8List> renderCodeGrid(BeadPattern pattern) {
    return compute(_renderCodeGridIsolate, _patternPayload(pattern));
  }

  Future<String> saveCodeGrid(BeadPattern pattern) async {
    final bytes = await renderCodeGrid(pattern);
    final path = await _saveImage(bytes, '拼豆编号格子_${pattern.id}.png');
    return path;
  }

  Future<String> savePreview(BeadPattern pattern) async {
    final bytes = await renderPreview(pattern);
    final decoded = img.decodePng(bytes);
    if (decoded == null) throw StateError('无法编码 JPG 效果图');
    final jpg = Uint8List.fromList(img.encodeJpg(decoded, quality: 94));
    return _saveImage(jpg, '${_exportBaseName(pattern)}_效果预览图.jpg');
  }

  Future<String> savePixelPreview(BeadPattern pattern) async {
    final bytes = await renderPixelPreview(pattern);
    return _saveImage(bytes, '${_exportBaseName(pattern)}_预览图.png');
  }

  Future<String> saveOriginal(BeadPattern pattern) async {
    final bytes = pattern.referenceBytes ?? pattern.sourceBytes;
    if (bytes.isEmpty) throw const FormatException('原图内容为空');
    final extension = _originalImageExtension(pattern, bytes);
    return _saveImage(bytes, '${_exportBaseName(pattern)}_原图.$extension');
  }

  Future<String> saveImageBytes(Uint8List bytes, String name) =>
      _saveImage(bytes, name);

  Future<String> saveDocumentBytes(
    Uint8List bytes,
    String name, {
    String mimeType = 'application/octet-stream',
  }) async {
    if (bytes.isEmpty) throw const FormatException('文件内容为空');
    final safeName = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (Platform.isAndroid) {
      final path = await _mediaChannel.invokeMethod<String>('saveDocument', {
        'bytes': bytes,
        'name': safeName,
        'mimeType': mimeType,
      });
      if (path == null) throw StateError('系统没有返回保存位置');
      return path;
    }
    final Directory baseDirectory;
    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      baseDirectory = profile == null || profile.isEmpty
          ? await getApplicationDocumentsDirectory()
          : Directory('$profile${Platform.pathSeparator}Downloads');
    } else {
      baseDirectory =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    final outputDirectory = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}拼豆AI',
    );
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }
    final file = File(
      '${outputDirectory.path}${Platform.pathSeparator}$safeName',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Opens the platform's Save As UI so the user chooses the exact download
  /// folder and filename. A null result means the picker was cancelled.
  Future<String?> saveDocumentBytesAs(
    Uint8List bytes,
    String name, {
    String mimeType = 'application/octet-stream',
  }) async {
    if (bytes.isEmpty) throw const FormatException('文件内容为空');
    final safeName = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (Platform.isAndroid) {
      return _mediaChannel.invokeMethod<String>('saveDocumentAs', {
        'bytes': bytes,
        'name': safeName,
        'mimeType': mimeType,
      });
    }
    final location = await getSaveLocation(
      suggestedName: safeName,
      confirmButtonText: '保存到这里',
      canCreateDirectories: true,
    );
    if (location == null) return null;
    await XFile.fromData(
      bytes,
      name: safeName,
      mimeType: mimeType,
    ).saveTo(location.path);
    return location.path;
  }

  Future<String> _saveImage(Uint8List bytes, String name) async {
    if (Platform.isAndroid) {
      final path = await _mediaChannel.invokeMethod<String>('saveImage', {
        'bytes': bytes,
        'name': name,
      });
      if (path == null) throw StateError('系统没有返回保存位置');
      return path;
    }

    final Directory baseDirectory;
    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      baseDirectory = profile == null || profile.isEmpty
          ? await getApplicationDocumentsDirectory()
          : Directory('$profile${Platform.pathSeparator}Pictures');
    } else {
      baseDirectory =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    final outputDirectory = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}拼豆AI',
    );
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }
    final safeName = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final file = File(
      '${outputDirectory.path}${Platform.pathSeparator}$safeName',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static String _exportBaseName(BeadPattern pattern) {
    final source = (pattern.sourceName ?? pattern.title)
        .replaceFirst(RegExp(r'\.[^.]+$'), '')
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final time = pattern.createdAt;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${source}_${time.year}${two(time.month)}${two(time.day)}_'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }

  static String _originalImageExtension(BeadPattern pattern, Uint8List bytes) {
    final sourceName = pattern.sourceName ?? '';
    final namedExtension = RegExp(
      r'\.([a-zA-Z0-9]{2,5})$',
    ).firstMatch(sourceName)?.group(1)?.toLowerCase();
    const supported = {
      'png',
      'jpg',
      'jpeg',
      'webp',
      'gif',
      'bmp',
      'tif',
      'tiff',
      'heic',
      'heif',
      'avif',
    };
    if (namedExtension != null && supported.contains(namedExtension)) {
      return namedExtension;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    final signature = bytes.length >= 6
        ? String.fromCharCodes(bytes.take(6))
        : '';
    if (signature == 'GIF87a' || signature == 'GIF89a') {
      return 'gif';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
      return 'webp';
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'bmp';
    }
    return 'png';
  }

  Future<File> createPreviewFile(BeadPattern pattern) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}bead_${pattern.id}.png',
    );
    return file.writeAsBytes(await renderPreview(pattern), flush: true);
  }

  Future<File> createCodeGridFile(BeadPattern pattern) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}bead_codes_${pattern.id}.png',
    );
    return file.writeAsBytes(await renderCodeGrid(pattern), flush: true);
  }

  Future<File> createPdf(BeadPattern pattern) async {
    final document = pw.Document(
      title: '${pattern.title} - Bead AI Design',
      author: 'xuan',
      creator: 'Bead AI Design',
    );
    final codeGrid = pw.MemoryImage(await renderCodeGrid(pattern));
    final longestSide = math.max(pattern.width, pattern.height);
    final cell = longestSide <= 60
        ? 12.0
        : longestSide <= 120
        ? 9.0
        : longestSide <= 220
        ? 7.5
        : 6.5;
    final templateLayout = _templateLayout(_patternPayload(pattern));
    final templateScale = cell / templateLayout.cellSize;
    final gridWidth = templateLayout.width * templateScale;
    final gridHeight = templateLayout.height * templateScale;
    const margin = 24.0;
    const gap = 20.0;
    final sideWidth = pattern.template == PatternTemplate.none ? 250.0 : 0.0;
    const headerHeight = 46.0;
    final legendHeight = pattern.template == PatternTemplate.none
        ? 150.0 + pattern.sortedCounts.length * 15.0
        : 0.0;
    final contentHeight = math.max(gridHeight, legendHeight);
    final pageWidth = math.max(
      PdfPageFormat.a4.width,
      margin * 2 + gridWidth + (sideWidth > 0 ? gap + sideWidth : 0),
    );
    final pageHeight = math.max(
      PdfPageFormat.a4.height,
      margin * 2 + headerHeight + contentHeight + 14,
    );

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, pageHeight),
        margin: const pw.EdgeInsets.all(margin),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              height: headerHeight,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'BEAD AI DESIGN  /  ONE-PAGE CODE GRID',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    '${pattern.width} x ${pattern.height}  |  '
                    '${pattern.colors.length} COLORS  |  '
                    '${pattern.totalBeads} BEADS  |  '
                    'MIN BOARD ${pattern.occupiedBounds.width} x ${pattern.occupiedBounds.height}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Image(
                  codeGrid,
                  width: gridWidth,
                  height: gridHeight,
                  fit: pw.BoxFit.fill,
                ),
                if (sideWidth > 0) ...[
                  pw.SizedBox(width: gap),
                  pw.SizedBox(width: sideWidth, child: _onePageLegend(pattern)),
                ],
              ],
            ),
            pw.Spacer(),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Single page | ${BeadPalettes.byId(pattern.paletteId).shortName} palette | Copyright 2026 xuan',
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey700,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}bead_pattern_${pattern.id}.pdf',
    );
    return file.writeAsBytes(await document.save(), flush: true);
  }

  Future<void> sharePreview(BeadPattern pattern) async {
    final file = await createPreviewFile(pattern);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: '${pattern.title} · 拼豆 AI 设计 · 版权所有 xuan',
      ),
    );
  }

  Future<void> shareCodeGrid(BeadPattern pattern) async {
    final file = await createCodeGridFile(pattern);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text:
            '${pattern.title} · 带 ${BeadPalettes.byId(pattern.paletteId).shortName} 颜色编号的拼豆图纸',
      ),
    );
  }

  Future<void> sharePdf(BeadPattern pattern) async {
    final file = await createPdf(pattern);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        text:
            '${pattern.title} · ${BeadPalettes.byId(pattern.paletteId).shortName} 拼豆图纸',
      ),
    );
  }

  static pw.TextStyle _pdfSectionStyle() => pw.TextStyle(
    fontSize: 11,
    fontWeight: pw.FontWeight.bold,
    color: PdfColor.fromHex('#303030'),
  );

  static pw.Widget _onePageLegend(BeadPattern pattern) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('COLOR / PURCHASE LIST', style: _pdfSectionStyle()),
      pw.SizedBox(height: 5),
      pw.Text(
        'QTY = exact pattern count  |  BUY = QTY + 8%',
        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        'MINIMUM BOARD: ${pattern.width} x ${pattern.height} GRID CELLS',
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.grey800,
        ),
      ),
      pw.SizedBox(height: 10),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        color: PdfColors.grey200,
        child: pw.Row(
          children: [
            pw.SizedBox(width: 18),
            pw.SizedBox(
              width: 70,
              child: pw.Text('CODE', style: _legendHeaderStyle()),
            ),
            pw.Expanded(child: pw.Text('QTY', style: _legendHeaderStyle())),
            pw.SizedBox(
              width: 48,
              child: pw.Text('BUY', style: _legendHeaderStyle()),
            ),
          ],
        ),
      ),
      for (final entry in pattern.sortedCounts)
        pw.Container(
          height: 15,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(width: 0.25, color: PdfColors.grey300),
            ),
          ),
          child: pw.Row(
            children: [
              pw.Container(
                width: 10,
                height: 10,
                decoration: pw.BoxDecoration(
                  color: PdfColor(
                    pattern.colors[entry.key].red / 255,
                    pattern.colors[entry.key].green / 255,
                    pattern.colors[entry.key].blue / 255,
                  ),
                  border: pw.Border.all(width: 0.25),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.SizedBox(
                width: 70,
                child: pw.Text(
                  pattern.colors[entry.key].code,
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text('${entry.value}', style: _legendValueStyle()),
              ),
              pw.SizedBox(
                width: 48,
                child: pw.Text(
                  '${(entry.value * 1.08).ceil()}',
                  style: _legendValueStyle(),
                ),
              ),
            ],
          ),
        ),
      pw.SizedBox(height: 10),
      pw.Text(
        'Palette values are engineering approximations. Check a physical swatch before purchasing.',
        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
      ),
    ],
  );

  static pw.TextStyle _legendHeaderStyle() =>
      pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);

  static pw.TextStyle _legendValueStyle() => const pw.TextStyle(fontSize: 7);
}

Map<String, Object> _patternPayload(BeadPattern pattern) => {
  'width': pattern.width,
  'height': pattern.height,
  'cells': pattern.cells,
  'colors': [
    for (final color in pattern.colors)
      [color.red, color.green, color.blue, color.code],
  ],
  'template': pattern.template.name,
  'title': pattern.title,
};

Uint8List _renderPreviewIsolate(Map<String, Object> payload) {
  final width = payload['width']! as int;
  final height = payload['height']! as int;
  final cells = (payload['cells']! as List).cast<int>();
  final colors = (payload['colors']! as List)
      .map((value) => (value as List).toList())
      .toList();
  final cellSize = (3200 / math.max(width, height)).floor().clamp(8, 48);
  final output = img.Image(
    width: width * cellSize,
    height: height * cellSize,
    numChannels: 4,
  );
  img.fill(output, color: img.ColorRgb8(247, 241, 235));
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final colorIndex = cells[y * width + x];
      if (colorIndex < 0) continue;
      final color = colors[colorIndex];
      final centerX = x * cellSize + cellSize ~/ 2;
      final centerY = y * cellSize + cellSize ~/ 2;
      final radius = math.max(2, cellSize ~/ 2 - 1);
      img.fillCircle(
        output,
        x: centerX,
        y: centerY,
        radius: radius,
        color: img.ColorRgb8(color[0] as int, color[1] as int, color[2] as int),
        antialias: cellSize >= 8,
      );
      img.fillCircle(
        output,
        x: centerX,
        y: centerY,
        radius: math.max(1, (radius * 0.24).round()),
        color: img.ColorRgb8(
          ((color[0] as int) * 0.72).round(),
          ((color[1] as int) * 0.72).round(),
          ((color[2] as int) * 0.72).round(),
        ),
      );
    }
  }
  return Uint8List.fromList(img.encodePng(output, level: 6));
}

Uint8List _renderPixelPreviewIsolate(Map<String, Object> payload) {
  final width = payload['width']! as int;
  final height = payload['height']! as int;
  final cells = (payload['cells']! as List).cast<int>();
  final colors = (payload['colors']! as List)
      .map((value) => (value as List).toList())
      .toList();
  final cellSize = (3200 / math.max(width, height)).floor().clamp(1, 64);
  final output = img.Image(
    width: width * cellSize,
    height: height * cellSize,
    numChannels: 4,
  );
  img.fill(output, color: img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final colorIndex = cells[y * width + x];
      if (colorIndex < 0) continue;
      final color = colors[colorIndex];
      img.fillRect(
        output,
        x1: x * cellSize,
        y1: y * cellSize,
        x2: (x + 1) * cellSize - 1,
        y2: (y + 1) * cellSize - 1,
        color: img.ColorRgb8(color[0] as int, color[1] as int, color[2] as int),
      );
    }
  }
  return Uint8List.fromList(img.encodePng(output, level: 6));
}

Uint8List _renderCodeGridIsolate(Map<String, Object> payload) {
  final width = payload['width']! as int;
  final height = payload['height']! as int;
  final cells = (payload['cells']! as List).cast<int>();
  final colors = (payload['colors']! as List)
      .map((value) => (value as List).toList())
      .toList();
  final template = PatternTemplate.values.firstWhere(
    (value) => value.name == payload['template'],
    orElse: () => PatternTemplate.none,
  );
  final layout = _templateLayout(payload);
  final cellSize = layout.cellSize;
  final output = img.Image(
    width: layout.width,
    height: layout.height,
    numChannels: 3,
  );
  img.fill(output, color: img.ColorRgb8(255, 255, 255));

  if (template != PatternTemplate.none) {
    _drawTemplateHeader(output, payload, template, layout, cells);
    _drawCoordinateBands(output, width, height, template, layout);
  }

  final originX = layout.left;
  final originY = layout.top;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final colorIndex = cells[y * width + x];
      if (colorIndex < 0) continue;
      final color = colors[colorIndex];
      final red = color[0] as int;
      final green = color[1] as int;
      final blue = color[2] as int;
      img.fillRect(
        output,
        x1: originX + x * cellSize,
        y1: originY + y * cellSize,
        x2: originX + (x + 1) * cellSize,
        y2: originY + (y + 1) * cellSize,
        color: img.ColorRgb8(red, green, blue),
      );
      final code = color[3] as String;
      var textWidth = 0;
      for (final character in code.split('')) {
        textWidth += img.arial14.characterXAdvance(character);
      }
      final luminance = (0.299 * red + 0.587 * green + 0.114 * blue) / 255;
      img.drawString(
        output,
        code,
        font: img.arial14,
        x: originX + x * cellSize + math.max(1, (cellSize - textWidth) ~/ 2),
        y: originY + y * cellSize + math.max(1, (cellSize - 14) ~/ 2),
        color: luminance > 0.58
            ? img.ColorRgb8(24, 24, 24)
            : img.ColorRgb8(255, 255, 255),
      );
    }
  }
  final grid = img.ColorRgb8(72, 72, 72);
  final blockSize = switch (template) {
    PatternTemplate.fresh => 10,
    PatternTemplate.classic || PatternTemplate.mard => 5,
    PatternTemplate.none => 0,
  };
  for (var x = 0; x <= width; x++) {
    img.drawLine(
      output,
      x1: originX + x * cellSize,
      y1: originY,
      x2: originX + x * cellSize,
      y2: originY + height * cellSize,
      color: grid,
      thickness: blockSize > 0 && x % blockSize == 0 ? 3 : 1,
    );
  }
  for (var y = 0; y <= height; y++) {
    img.drawLine(
      output,
      x1: originX,
      y1: originY + y * cellSize,
      x2: originX + width * cellSize,
      y2: originY + y * cellSize,
      color: grid,
      thickness: blockSize > 0 && y % blockSize == 0 ? 3 : 1,
    );
  }

  if (template != PatternTemplate.none) {
    _drawTemplateLegend(output, colors, cells, template, layout);
  }
  return Uint8List.fromList(img.encodePng(output, level: 6));
}

class _TemplateLayout {
  const _TemplateLayout({
    required this.cellSize,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.width,
    required this.height,
    required this.headerHeight,
    required this.legendColumns,
  });

  final int cellSize;
  final int left;
  final int top;
  final int right;
  final int bottom;
  final int width;
  final int height;
  final int headerHeight;
  final int legendColumns;
}

_TemplateLayout _templateLayout(Map<String, Object> payload) {
  final width = payload['width']! as int;
  final height = payload['height']! as int;
  final colorCount = (payload['colors']! as List).length;
  final longestSide = math.max(width, height);
  final cellSize = (4800 / longestSide).floor().clamp(16, 32);
  final template = PatternTemplate.values.firstWhere(
    (value) => value.name == payload['template'],
    orElse: () => PatternTemplate.none,
  );
  if (template == PatternTemplate.none) {
    return _TemplateLayout(
      cellSize: cellSize,
      left: 0,
      top: 0,
      right: 1,
      bottom: 1,
      width: width * cellSize + 1,
      height: height * cellSize + 1,
      headerHeight: 0,
      legendColumns: 0,
    );
  }
  final legendColumns = switch (template) {
    PatternTemplate.classic => 8,
    PatternTemplate.fresh => 6,
    PatternTemplate.mard => 5,
    PatternTemplate.none => 0,
  };
  final legendRows = (colorCount / legendColumns).ceil();
  final axis = cellSize;
  final headerHeight = switch (template) {
    PatternTemplate.classic => cellSize * 5,
    PatternTemplate.fresh => cellSize * 4,
    PatternTemplate.mard => cellSize * 3,
    PatternTemplate.none => 0,
  };
  final legendHeight = cellSize + legendRows * (cellSize + 10) + 12;
  final left = axis;
  final top = headerHeight + axis;
  final right = axis;
  final bottom = axis + legendHeight;
  return _TemplateLayout(
    cellSize: cellSize,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    width: left + width * cellSize + right + 1,
    height: top + height * cellSize + bottom + 1,
    headerHeight: headerHeight,
    legendColumns: legendColumns,
  );
}

void _drawTemplateHeader(
  img.Image output,
  Map<String, Object> payload,
  PatternTemplate template,
  _TemplateLayout layout,
  List<int> cells,
) {
  final background = switch (template) {
    PatternTemplate.classic => img.ColorRgb8(255, 248, 244),
    PatternTemplate.fresh => img.ColorRgb8(231, 247, 242),
    PatternTemplate.mard => img.ColorRgb8(238, 244, 253),
    PatternTemplate.none => img.ColorRgb8(255, 255, 255),
  };
  img.fillRect(
    output,
    x1: 0,
    y1: 0,
    x2: output.width - 1,
    y2: layout.headerHeight - 1,
    color: background,
  );
  final accent = switch (template) {
    PatternTemplate.classic => img.ColorRgb8(229, 102, 81),
    PatternTemplate.fresh => img.ColorRgb8(31, 139, 125),
    PatternTemplate.mard => img.ColorRgb8(67, 91, 130),
    PatternTemplate.none => img.ColorRgb8(40, 40, 40),
  };
  final badgeSize = layout.cellSize * 2;
  img.fillRect(
    output,
    x1: layout.cellSize,
    y1: layout.cellSize,
    x2: layout.cellSize + badgeSize,
    y2: layout.cellSize + badgeSize,
    color: accent,
  );
  _drawCenteredString(
    output,
    'B',
    font: img.arial48,
    centerX: layout.cellSize + badgeSize ~/ 2,
    y: layout.cellSize + math.max(0, (badgeSize - 48) ~/ 2),
    color: img.ColorRgb8(255, 255, 255),
  );
  final heading = switch (template) {
    PatternTemplate.classic => 'BEAD AI DESIGN / CLASSIC',
    PatternTemplate.fresh => 'BEAD AI DESIGN / FRESH GRID',
    PatternTemplate.mard => 'ARTKAL COLOR CODE',
    PatternTemplate.none => 'BEAD PATTERN',
  };
  img.drawString(
    output,
    heading,
    font: img.arial24,
    x: layout.cellSize * 4,
    y: layout.cellSize,
    color: img.ColorRgb8(28, 29, 31),
  );
  final usedColors = cells.where((index) => index >= 0).toSet().length;
  final beads = cells.where((index) => index >= 0).length;
  final details =
      '${payload['width']} x ${payload['height']}  /  '
      '$usedColors COLORS  /  $beads BEADS  /  '
      'MIN BOARD ${payload['width']} x ${payload['height']}';
  img.drawString(
    output,
    details,
    font: img.arial14,
    x: layout.cellSize * 4,
    y: layout.cellSize + 32,
    color: img.ColorRgb8(69, 70, 74),
  );
  final title = _asciiTitle(payload['title']! as String);
  if (layout.headerHeight >= layout.cellSize * 4) {
    img.drawString(
      output,
      title,
      font: img.arial14,
      x: layout.cellSize,
      y: layout.headerHeight - 22,
      color: accent,
    );
  }
}

void _drawCoordinateBands(
  img.Image output,
  int width,
  int height,
  PatternTemplate template,
  _TemplateLayout layout,
) {
  final band = template == PatternTemplate.mard
      ? img.ColorRgb8(229, 237, 249)
      : img.ColorRgb8(238, 238, 238);
  final gridWidth = width * layout.cellSize;
  final gridHeight = height * layout.cellSize;
  img.fillRect(
    output,
    x1: layout.left,
    y1: layout.top - layout.cellSize,
    x2: layout.left + gridWidth,
    y2: layout.top - 1,
    color: band,
  );
  img.fillRect(
    output,
    x1: layout.left,
    y1: layout.top + gridHeight + 1,
    x2: layout.left + gridWidth,
    y2: layout.top + gridHeight + layout.cellSize,
    color: band,
  );
  img.fillRect(
    output,
    x1: 0,
    y1: layout.top,
    x2: layout.left - 1,
    y2: layout.top + gridHeight,
    color: band,
  );
  img.fillRect(
    output,
    x1: layout.left + gridWidth + 1,
    y1: layout.top,
    x2: layout.left + gridWidth + layout.right,
    y2: layout.top + gridHeight,
    color: band,
  );
  final ink = img.ColorRgb8(40, 43, 48);
  for (var x = 0; x < width; x++) {
    final value = '${x + 1}';
    final centerX = layout.left + x * layout.cellSize + layout.cellSize ~/ 2;
    _drawCenteredString(
      output,
      value,
      font: img.arial14,
      centerX: centerX,
      y:
          layout.top -
          layout.cellSize +
          math.max(0, (layout.cellSize - 14) ~/ 2),
      color: ink,
    );
    _drawCenteredString(
      output,
      value,
      font: img.arial14,
      centerX: centerX,
      y: layout.top + gridHeight + math.max(1, (layout.cellSize - 14) ~/ 2),
      color: ink,
    );
  }
  for (var y = 0; y < height; y++) {
    final value = '${y + 1}';
    final textY =
        layout.top +
        y * layout.cellSize +
        math.max(0, (layout.cellSize - 14) ~/ 2).toInt();
    _drawCenteredString(
      output,
      value,
      font: img.arial14,
      centerX: layout.left ~/ 2,
      y: textY,
      color: ink,
    );
    _drawCenteredString(
      output,
      value,
      font: img.arial14,
      centerX: layout.left + gridWidth + layout.right ~/ 2,
      y: textY,
      color: ink,
    );
  }
}

void _drawTemplateLegend(
  img.Image output,
  List<List<dynamic>> colors,
  List<int> cells,
  PatternTemplate template,
  _TemplateLayout layout,
) {
  final counts = <int, int>{};
  for (final index in cells) {
    if (index >= 0) counts[index] = (counts[index] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final gridBottom =
      layout.top +
      (output.height - layout.top - layout.bottom) +
      layout.cellSize;
  final areaWidth = output.width - layout.cellSize * 2;
  final itemWidth = areaWidth ~/ layout.legendColumns;
  img.drawString(
    output,
    template == PatternTemplate.fresh ? 'COLOR LIST' : 'COLOR / QUANTITY',
    font: img.arial14,
    x: layout.cellSize,
    y: gridBottom + 6,
    color: img.ColorRgb8(45, 45, 48),
  );
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final row = i ~/ layout.legendColumns;
    final column = i % layout.legendColumns;
    final x = layout.cellSize + column * itemWidth;
    final y = gridBottom + layout.cellSize + row * (layout.cellSize + 10);
    final color = colors[entry.key];
    final red = color[0] as int;
    final green = color[1] as int;
    final blue = color[2] as int;
    img.fillRect(
      output,
      x1: x,
      y1: y,
      x2: x + layout.cellSize - 3,
      y2: y + layout.cellSize - 3,
      color: img.ColorRgb8(red, green, blue),
    );
    img.drawString(
      output,
      '${color[3]}  ${entry.value}',
      font: img.arial14,
      x: x + layout.cellSize + 2,
      y: y + math.max(0, (layout.cellSize - 14) ~/ 2),
      color: img.ColorRgb8(35, 35, 38),
    );
  }
}

void _drawCenteredString(
  img.Image output,
  String value, {
  required img.BitmapFont font,
  required int centerX,
  required int y,
  required img.Color color,
}) {
  var width = 0;
  for (final character in value.split('')) {
    width += font.characterXAdvance(character);
  }
  img.drawString(
    output,
    value,
    font: font,
    x: centerX - width ~/ 2,
    y: y,
    color: color,
  );
}

String _asciiTitle(String title) {
  final ascii = title.codeUnits
      .where((value) => value >= 32 && value <= 126)
      .map(String.fromCharCode)
      .join()
      .trim();
  return ascii.isEmpty ? 'YOUR BEAD PATTERN' : ascii;
}
