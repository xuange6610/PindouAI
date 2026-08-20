import 'dart:convert';
import 'dart:io';

import 'package:bead_ai_designer/data/mard_palette.dart';
import 'package:bead_ai_designer/models/bead_pattern.dart';
import 'package:bead_ai_designer/services/export_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('预览图使用无格子无编号的方形像素色块', () async {
    final source = img.Image(width: 2, height: 1);
    img.fill(source, color: img.ColorRgb8(240, 100, 80));
    final first = MardPalette.byCode['A8']!;
    final second = MardPalette.byCode['H23']!;
    final pattern = BeadPattern(
      id: 'pixel-preview-test',
      title: 'Pixel Preview',
      width: 2,
      height: 1,
      colors: [first, second],
      cells: const [0, 1],
      sourceBytes: Uint8List.fromList(img.encodePng(source)),
      createdAt: DateTime(2026),
      requestedColorCount: 2,
      portraitMode: false,
    );

    final rendered = img.decodePng(
      await ExportService().renderPixelPreview(pattern),
    );
    expect(rendered, isNotNull);
    expect(rendered!.width, 128);
    expect(rendered.height, 64);
    final left = rendered.getPixel(20, 20);
    final right = rendered.getPixel(90, 20);
    expect(
      (left.r.toInt(), left.g.toInt(), left.b.toInt()),
      (first.red, first.green, first.blue),
    );
    expect(
      (right.r.toInt(), right.g.toInt(), right.b.toInt()),
      (second.red, second.green, second.blue),
    );
  });

  test('生成的完整 PDF 有效且始终只有一个页面', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final outputDirectory = Directory('.dart_tool/test_exports');
    await outputDirectory.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => outputDirectory.absolute.path,
        );
    final source = img.Image(width: 2, height: 2);
    img.fill(source, color: img.ColorRgb8(240, 100, 80));
    final pattern = BeadPattern(
      id: 'pdf-test',
      title: 'Test Pattern',
      width: 2,
      height: 2,
      colors: [MardPalette.byCode['A8']!, MardPalette.byCode['H23']!],
      cells: const [0, 1, 1, 0],
      sourceBytes: Uint8List.fromList(img.encodePng(source)),
      createdAt: DateTime(2026),
      requestedColorCount: 2,
      portraitMode: false,
    );

    final file = await ExportService().createPdf(pattern);
    final bytes = await file.readAsBytes();
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final pdfSource = latin1.decode(bytes);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(pdfSource), hasLength(1));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
  });

  test('200×200 完整编号图可装入同一个 PDF 页面', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final outputDirectory = Directory('.dart_tool/test_exports_large');
    await outputDirectory.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => outputDirectory.absolute.path,
        );
    final source = img.Image(width: 2, height: 2);
    img.fill(source, color: img.ColorRgb8(240, 100, 80));
    final pattern = BeadPattern(
      id: 'pdf-large-test',
      title: 'Large Pattern',
      width: 200,
      height: 200,
      colors: [MardPalette.byCode['A8']!, MardPalette.byCode['H23']!],
      cells: List<int>.generate(40000, (index) => index & 1),
      sourceBytes: Uint8List.fromList(img.encodePng(source)),
      createdAt: DateTime(2026),
      requestedColorCount: 2,
      portraitMode: false,
    );

    final file = await ExportService().createPdf(pattern);
    final bytes = await file.readAsBytes();
    final pdfSource = latin1.decode(bytes);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(pdfSource), hasLength(1));
    expect(bytes.length, greaterThan(10000));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await outputDirectory.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('三种图纸模板都会生成带边框信息的完整图纸', () async {
    final source = img.Image(width: 2, height: 2);
    img.fill(source, color: img.ColorRgb8(240, 100, 80));
    final exporter = ExportService();
    final dimensions = <String>{};
    for (final template in PatternTemplate.values.skip(1)) {
      final pattern = BeadPattern(
        id: 'template-${template.name}',
        title: 'Template Test',
        width: 8,
        height: 6,
        colors: [MardPalette.byCode['A8']!, MardPalette.byCode['H23']!],
        cells: List<int>.generate(48, (index) => index & 1),
        sourceBytes: Uint8List.fromList(img.encodePng(source)),
        createdAt: DateTime(2026),
        requestedColorCount: 2,
        portraitMode: false,
        template: template,
      );
      final rendered = img.decodePng(await exporter.renderCodeGrid(pattern));
      expect(rendered, isNotNull);
      expect(rendered!.width, greaterThan(pattern.width * 32));
      expect(rendered.height, greaterThan(pattern.height * 32));
      dimensions.add('${rendered.width}x${rendered.height}');
    }
    expect(dimensions, hasLength(3));
  });
}
