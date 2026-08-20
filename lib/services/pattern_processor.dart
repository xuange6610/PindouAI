import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../data/bead_palettes.dart';
import '../models/bead_color.dart';
import '../models/bead_palette.dart';
import '../models/bead_pattern.dart';
import 'color_science.dart';

class ProcessingOptions {
  const ProcessingOptions({
    required this.size,
    this.height,
    required this.maxColors,
    required this.portraitMode,
    required this.smoothing,
    this.removeBackground = false,
    this.template = PatternTemplate.none,
    this.variantSeed = 0,
    this.paletteId = BeadPaletteId.mard291,
  });

  final int size;
  final int? height;
  final int maxColors;
  final bool portraitMode;
  final bool smoothing;
  final bool removeBackground;
  final PatternTemplate template;
  final int variantSeed;
  final BeadPaletteId paletteId;

  int get width => size;
  int get outputHeight => height ?? size;
}

typedef ProcessingProgressCallback =
    void Function(double progress, String phase);

class ProcessingCancelledException implements Exception {
  const ProcessingCancelledException();

  @override
  String toString() => '处理任务已暂停';
}

class ProcessingOperation {
  ProcessingOperation._(this.result, this._cancel);

  final Future<BeadPattern> result;
  final VoidCallback _cancel;
  bool _cancelled = false;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}

class PatternProcessor {
  Future<Uint8List> smartCutout(Uint8List imageBytes) async {
    final inputBuffer = await ui.ImmutableBuffer.fromUint8List(imageBytes);
    final descriptor = await ui.ImageDescriptor.encoded(inputBuffer);
    final longestSide = math.max(descriptor.width, descriptor.height);
    final scale = longestSide > 3072 ? 3072 / longestSide : 1.0;
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round(),
      targetHeight: (descriptor.height * scale).round(),
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final width = frame.image.width;
    final height = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    inputBuffer.dispose();
    if (data == null) throw const FormatException('无法读取图片像素');
    return compute(_smartCutoutWorker, {
      'bytes': data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      'width': width,
      'height': height,
    });
  }

  Future<BeadPattern> process(
    Uint8List imageBytes,
    ProcessingOptions options, {
    ProcessingProgressCallback? onProgress,
  }) async {
    final operation = await start(imageBytes, options, onProgress: onProgress);
    return operation.result;
  }

  Future<ProcessingOperation> start(
    Uint8List imageBytes,
    ProcessingOptions options, {
    ProcessingProgressCallback? onProgress,
    Uint8List? projectSourceBytes,
    String? sourceName,
    bool backgroundAlreadyRemoved = false,
  }) async {
    // The platform codec supports HEIC and Android screenshot variants that
    // package:image cannot always decode. Pass normalized raw RGBA pixels to
    // the isolate, avoiding a second container-format decode entirely.
    onProgress?.call(0.02, '读取图片');
    final inputBuffer = await ui.ImmutableBuffer.fromUint8List(imageBytes);
    final descriptor = await ui.ImageDescriptor.encoded(inputBuffer);
    final maxDecodeDimension =
        (math.max(options.width, options.outputHeight) * 20).clamp(1536, 3072);
    final longestSide = math.max(descriptor.width, descriptor.height);
    final scale = longestSide > maxDecodeDimension
        ? maxDecodeDimension / longestSide
        : 1.0;
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round(),
      targetHeight: (descriptor.height * scale).round(),
    );
    final frame = await codec.getNextFrame();
    final normalizedData = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final sourceWidth = frame.image.width;
    final sourceHeight = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    inputBuffer.dispose();
    if (normalizedData == null) {
      throw const FormatException('无法解码该图片，请改用 JPG、PNG 或 HEIC');
    }
    final normalizedBytes = normalizedData.buffer.asUint8List(
      normalizedData.offsetInBytes,
      normalizedData.lengthInBytes,
    );
    onProgress?.call(0.18, '准备图像');
    final payload = <String, Object>{
      'bytes': normalizedBytes,
      'sourceWidth': sourceWidth,
      'sourceHeight': sourceHeight,
      'size': options.size,
      'height': options.outputHeight,
      'maxColors': options.maxColors,
      'portraitMode': options.portraitMode,
      'smoothing': options.smoothing,
      'removeBackground': options.removeBackground && !backgroundAlreadyRemoved,
      'variantSeed': options.variantSeed,
      'paletteId': options.paletteId.storageId,
    };
    final receivePort = ReceivePort();
    final resultCompleter = Completer<Map<String, Object>>();
    late final Isolate isolate;
    late final StreamSubscription<Object?> subscription;
    var closed = false;

    void close() {
      if (closed) return;
      closed = true;
      subscription.cancel();
      receivePort.close();
    }

    subscription = receivePort.listen((message) {
      if (message is! Map) return;
      final type = message['type'];
      if (type == 'progress') {
        onProgress?.call(
          (message['value'] as num).toDouble(),
          message['phase'] as String,
        );
      } else if (type == 'result' && !resultCompleter.isCompleted) {
        resultCompleter.complete(
          (message['data'] as Map).cast<String, Object>(),
        );
        close();
      } else if (type == 'error' && !resultCompleter.isCompleted) {
        resultCompleter.completeError(
          StateError(message['message'] as String),
          StackTrace.fromString(message['stack'] as String),
        );
        close();
      }
    });
    isolate = await Isolate.spawn<Map<String, Object>>(_patternWorker, {
      'replyPort': receivePort.sendPort,
      'payload': payload,
    }, debugName: 'bead-pattern-worker');

    final patternFuture = resultCompleter.future.then((output) {
      final codes = (output['codes']! as List).cast<String>();
      final palette = BeadPalettes.byId(options.paletteId);
      final colors = codes.map((code) => palette.byCode[code]!).toList();
      final now = DateTime.now();
      final cleanSourceName = _sourceBaseName(sourceName);
      return BeadPattern(
        id: now.microsecondsSinceEpoch.toString(),
        title: '${cleanSourceName}_${_dateStamp(now)}',
        width: output['width']! as int,
        height: output['height']! as int,
        colors: colors,
        cells: (output['cells']! as List).cast<int>(),
        sourceBytes: projectSourceBytes ?? imageBytes,
        referenceBytes: imageBytes,
        createdAt: now,
        requestedColorCount: options.maxColors,
        portraitMode: options.portraitMode,
        backgroundRemoved: options.removeBackground,
        template: options.template,
        sourceName: sourceName,
        smoothing: options.smoothing,
        variantSeed: options.variantSeed,
        paletteId: options.paletteId,
      );
    });
    return ProcessingOperation._(patternFuture, () {
      isolate.kill(priority: Isolate.immediate);
      if (!resultCompleter.isCompleted) {
        resultCompleter.completeError(const ProcessingCancelledException());
      }
      close();
    });
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  static String _dateStamp(DateTime value) =>
      '${value.year}${_twoDigits(value.month)}${_twoDigits(value.day)}_'
      '${_twoDigits(value.hour)}${_twoDigits(value.minute)}${_twoDigits(value.second)}';

  static String _sourceBaseName(String? sourceName) {
    final name = (sourceName ?? '我的拼豆').trim();
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final safe = base.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return safe.isEmpty ? '我的拼豆' : safe;
  }
}

Uint8List _smartCutoutWorker(Map<String, Object> payload) {
  final bytes = payload['bytes']! as Uint8List;
  final width = payload['width']! as int;
  final height = payload['height']! as int;
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: bytes.buffer,
    bytesOffset: bytes.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  _applySmartSubjectMask(image);
  return Uint8List.fromList(img.encodePng(image, level: 6));
}

void _patternWorker(Map<String, Object> message) {
  final replyPort = message['replyPort']! as SendPort;
  final payload = (message['payload']! as Map).cast<String, Object>();
  try {
    final result = _processPattern(
      payload,
      onProgress: (progress, phase) => replyPort.send({
        'type': 'progress',
        'value': progress,
        'phase': phase,
      }),
    );
    replyPort.send({'type': 'result', 'data': result});
  } on Object catch (error, stackTrace) {
    replyPort.send({
      'type': 'error',
      'message': error.toString(),
      'stack': stackTrace.toString(),
    });
  }
}

Map<String, Object> _processPattern(
  Map<String, Object> payload, {
  void Function(double progress, String phase)? onProgress,
}) {
  final bytes = payload['bytes']! as Uint8List;
  final sourceWidth = payload['sourceWidth']! as int;
  final sourceHeight = payload['sourceHeight']! as int;
  final targetWidth = payload['size']! as int;
  final targetHeight = payload['height']! as int;
  final maxColors = payload['maxColors']! as int;
  final portraitMode = payload['portraitMode']! as bool;
  final smoothing = payload['smoothing']! as bool;
  final removeBackground = payload['removeBackground']! as bool;
  final variantSeed = payload['variantSeed']! as int;
  final paletteId =
      BeadPaletteIdStorage.tryParse(payload['paletteId'] as String?) ??
      BeadPaletteId.mard291;
  final paletteColors = BeadPalettes.byId(paletteId).colors;
  final oriented = img.Image.fromBytes(
    width: sourceWidth,
    height: sourceHeight,
    bytes: bytes.buffer,
    bytesOffset: bytes.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  if (removeBackground) {
    onProgress?.call(0.2, 'AI 识别并抠出主体');
    _applySmartSubjectMask(oriented);
  }
  // Preserve the complete composition by default. Users who want a full-bleed
  // crop can make it explicitly in the editor, while untouched imports are no
  // longer silently cut at the sides or top/bottom.
  final fitScale = math.min(
    targetWidth / oriented.width,
    targetHeight / oriented.height,
  );
  final fittedWidth = math.max(1, (oriented.width * fitScale).round());
  final fittedHeight = math.max(1, (oriented.height * fitScale).round());
  final fitted = img.copyResize(
    oriented,
    width: fittedWidth,
    height: fittedHeight,
    // Area averaging preserves the real mean color represented by each bead
    // cell. Cubic-only downsampling made small photos look soft and shifted
    // narrow high-contrast details toward their surroundings.
    interpolation: img.Interpolation.average,
  );
  final baseResized = img.Image(
    width: targetWidth,
    height: targetHeight,
    numChannels: 4,
  );
  img.fill(baseResized, color: img.ColorRgba8(255, 255, 255, 0));
  img.compositeImage(
    baseResized,
    fitted,
    dstX: (targetWidth - fittedWidth) ~/ 2,
    dstY: (targetHeight - fittedHeight) ~/ 2,
  );
  // Sharpen at the final bead resolution. Sharpening before downsampling was
  // mostly averaged away and made small landscapes look soft.
  final resized = img.convolution(
    baseResized,
    filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
    amount: math.max(targetWidth, targetHeight) <= 58
        ? (smoothing ? 0.34 : 0.5)
        : (smoothing ? 0.22 : 0.34),
  );
  onProgress?.call(0.28, '缩放图片');

  final pixelLabs = <LabColor?>[];
  final opaqueLabs = <LabColor>[];
  final opaqueSkinFlags = <bool>[];
  final skinFlags = <bool>[];
  final colorKeys = <int>[];
  final labCache = <int, LabColor>{};
  for (var y = 0; y < resized.height; y++) {
    for (var x = 0; x < resized.width; x++) {
      final pixel = resized.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      if (pixel.a.toInt() < 80) {
        colorKeys.add(-1);
        pixelLabs.add(null);
        skinFlags.add(false);
        continue;
      }
      final key = (r << 16) | (g << 8) | b;
      colorKeys.add(key);
      final lab = labCache.putIfAbsent(
        key,
        () => ColorScience.rgbToLab(r, g, b),
      );
      final isSkin = portraitMode && ColorScience.looksLikeSkin(r, g, b);
      pixelLabs.add(lab);
      opaqueLabs.add(lab);
      skinFlags.add(isSkin);
      opaqueSkinFlags.add(isSkin);
    }
    if (y % math.max(1, resized.height ~/ 8) == 0) {
      onProgress?.call(0.28 + 0.14 * y / resized.height, '分析颜色');
    }
  }

  if (opaqueLabs.isEmpty) {
    throw StateError('AI 抠图没有识别到可生成的主体，请关闭抠图后重试');
  }

  var candidateColors = maxColors >= paletteColors.length
      ? List<BeadColor>.from(paletteColors)
      : _clusterAndSnap(
          opaqueLabs,
          opaqueSkinFlags,
          maxColors,
          portraitMode,
          paletteColors,
          variantSeed: variantSeed,
          onProgress: onProgress,
        );
  var cells = <int>[];
  final allCandidateIndices = List<int>.generate(
    candidateColors.length,
    (i) => i,
  );
  final matchCache = <int, int>{};
  for (var i = 0; i < pixelLabs.length; i++) {
    final pixelLab = pixelLabs[i];
    if (pixelLab == null) {
      cells.add(-1);
      continue;
    }
    final cacheKey = colorKeys[i];
    cells.add(
      matchCache.putIfAbsent(
        cacheKey,
        () => _nearestCandidateIndex(
          _applyVariantStyle(pixelLab, variantSeed),
          candidateColors,
          allCandidateIndices,
        ),
      ),
    );
    if (i % math.max(1, pixelLabs.length ~/ 12) == 0) {
      onProgress?.call(0.64 + 0.28 * i / pixelLabs.length, '匹配拼豆色号');
    }
  }
  if (smoothing && targetWidth > 2 && targetHeight > 2) {
    cells = _removeIsolatedCells(cells, targetWidth, targetHeight);
  }
  final used = cells.where((value) => value >= 0).toSet().toList()..sort();
  final remap = <int, int>{
    for (var index = 0; index < used.length; index++) used[index]: index,
  };
  cells = cells.map((value) => value < 0 ? -1 : remap[value]!).toList();
  candidateColors = used.map((index) => candidateColors[index]).toList();
  onProgress?.call(0.96, '整理格子与清单');

  return {
    'width': targetWidth,
    'height': targetHeight,
    'codes': candidateColors.map((color) => color.code).toList(),
    'cells': cells,
  };
}

void _applySmartSubjectMask(img.Image source) {
  final width = source.width;
  final height = source.height;
  final total = width * height;
  if (total == 0) return;

  final histogram = <int, int>{};
  final borderStep = math.max(1, math.max(width, height) ~/ 320);

  void sample(int x, int y) {
    final pixel = source.getPixel(x, y);
    if (pixel.a.toInt() < 32) return;
    final key =
        ((pixel.r.toInt() >> 4) << 8) |
        ((pixel.g.toInt() >> 4) << 4) |
        (pixel.b.toInt() >> 4);
    histogram[key] = (histogram[key] ?? 0) + 1;
  }

  for (var x = 0; x < width; x += borderStep) {
    sample(x, 0);
    sample(x, height - 1);
  }
  for (var y = 0; y < height; y += borderStep) {
    sample(0, y);
    sample(width - 1, y);
  }
  if (histogram.isEmpty) return;
  final backgroundKeys = histogram.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final prototypes = <(int, int, int)>[
    for (final entry in backgroundKeys.take(10))
      (
        (((entry.key >> 8) & 0xF) << 4) + 8,
        (((entry.key >> 4) & 0xF) << 4) + 8,
        ((entry.key & 0xF) << 4) + 8,
      ),
  ];

  bool resemblesBackground(int x, int y) {
    final pixel = source.getPixel(x, y);
    if (pixel.a.toInt() < 32) return true;
    var best = 1 << 30;
    for (final prototype in prototypes) {
      final dr = pixel.r.toInt() - prototype.$1;
      final dg = pixel.g.toInt() - prototype.$2;
      final db = pixel.b.toInt() - prototype.$3;
      final distance = dr * dr + dg * dg + db * db;
      if (distance < best) best = distance;
    }
    return best <= 72 * 72;
  }

  final background = Uint8List(total);
  final queue = Int32List(total);
  var head = 0;
  var tail = 0;

  void enqueue(int x, int y) {
    final index = y * width + x;
    if (background[index] != 0) return;
    if (!resemblesBackground(x, y)) {
      background[index] = 2;
      return;
    }
    background[index] = 1;
    queue[tail++] = index;
  }

  for (var x = 0; x < width; x++) {
    enqueue(x, 0);
    enqueue(x, height - 1);
  }
  for (var y = 1; y < height - 1; y++) {
    enqueue(0, y);
    enqueue(width - 1, y);
  }
  while (head < tail) {
    final index = queue[head++];
    final x = index % width;
    final y = index ~/ width;
    if (x > 0) enqueue(x - 1, y);
    if (x + 1 < width) enqueue(x + 1, y);
    if (y > 0) enqueue(x, y - 1);
    if (y + 1 < height) enqueue(x, y + 1);
  }

  // Keep existing transparency and softly feather the detected subject edge.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = y * width + x;
      final pixel = source.getPixel(x, y);
      if (background[index] == 1) {
        source.setPixelRgba(
          x,
          y,
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          0,
        );
        continue;
      }
      var backgroundNeighbors = 0;
      for (var oy = -1; oy <= 1; oy++) {
        for (var ox = -1; ox <= 1; ox++) {
          final nx = x + ox;
          final ny = y + oy;
          if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
            backgroundNeighbors++;
          } else if (background[ny * width + nx] == 1) {
            backgroundNeighbors++;
          }
        }
      }
      final alpha = backgroundNeighbors == 0
          ? pixel.a.toInt()
          : math.min(pixel.a.toInt(), 80 + (9 - backgroundNeighbors) * 20);
      source.setPixelRgba(
        x,
        y,
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
        alpha,
      );
    }
  }
}

List<BeadColor> _clusterAndSnap(
  List<LabColor> pixels,
  List<bool> skinFlags,
  int requestedColors,
  bool portraitMode,
  List<BeadColor> paletteColors, {
  int variantSeed = 0,
  void Function(double progress, String phase)? onProgress,
}) {
  final sampleStride = math.max(1, (pixels.length / 8192).ceil());
  final samples = <LabColor>[];
  final sampleSkin = <bool>[];
  for (var i = 0; i < pixels.length; i += sampleStride) {
    samples.add(pixels[i]);
    sampleSkin.add(skinFlags[i]);
  }
  final k = math.min(requestedColors, samples.length);
  final random = math.Random(variantSeed);
  var centers = List<LabColor>.generate(k, (index) {
    final segmentStart = index * samples.length ~/ k;
    final segmentEnd = math.max(
      segmentStart + 1,
      (index + 1) * samples.length ~/ k,
    );
    final position = variantSeed == 0
        ? (((index + 0.5) * samples.length) / k).floor()
        : segmentStart + random.nextInt(segmentEnd - segmentStart);
    return samples[position.clamp(0, samples.length - 1)];
  });
  var assignments = List<int>.filled(samples.length, 0);

  for (var iteration = 0; iteration < 5; iteration++) {
    final sumL = List<double>.filled(k, 0);
    final sumA = List<double>.filled(k, 0);
    final sumB = List<double>.filled(k, 0);
    final counts = List<int>.filled(k, 0);
    for (var i = 0; i < samples.length; i++) {
      var best = 0;
      var bestDistance = double.infinity;
      for (var centerIndex = 0; centerIndex < centers.length; centerIndex++) {
        final center = centers[centerIndex];
        final sample = samples[i];
        final dl = sample.l - center.l;
        final da = sample.a - center.a;
        final db = sample.b - center.b;
        final distance = dl * dl + da * da + db * db;
        if (distance < bestDistance) {
          bestDistance = distance;
          best = centerIndex;
        }
      }
      assignments[i] = best;
      final sample = samples[i];
      sumL[best] += sample.l;
      sumA[best] += sample.a;
      sumB[best] += sample.b;
      counts[best]++;
    }
    centers = List.generate(k, (index) {
      if (counts[index] == 0) return centers[index];
      return LabColor(
        sumL[index] / counts[index],
        sumA[index] / counts[index],
        sumB[index] / counts[index],
      );
    });
    onProgress?.call(0.43 + 0.04 * iteration, '聚类主要颜色');
  }

  final clusterSkin = List<int>.filled(k, 0);
  final clusterCount = List<int>.filled(k, 0);
  for (var i = 0; i < assignments.length; i++) {
    clusterCount[assignments[i]]++;
    if (sampleSkin[i]) clusterSkin[assignments[i]]++;
  }

  final selected = <BeadColor>[];
  final selectedCenters = <LabColor>[];
  for (var index = 0; index < centers.length; index++) {
    final skinCluster =
        portraitMode &&
        clusterCount[index] > 0 &&
        clusterSkin[index] / clusterCount[index] >= 0.35;
    final center = _applyVariantStyle(centers[index], variantSeed);
    BeadColor? nearest;
    var nearestDistance = double.infinity;
    for (final color in paletteColors) {
      var distance = ColorScience.deltaE2000(center, color.lab);
      if (skinCluster && color.series == 'MG') distance *= 0.96;
      if (distance < nearestDistance) {
        nearest = color;
        nearestDistance = distance;
      }
    }
    if (nearest == null) continue;
    if (!selected.any((item) => item.code == nearest!.code)) {
      selected.add(nearest);
      selectedCenters.add(center);
      continue;
    }
    if (selectedCenters.any(
      (existing) => ColorScience.deltaE2000(center, existing) < 1.8,
    )) {
      continue;
    }
    BeadColor? best;
    var bestDistance = double.infinity;
    for (final color in paletteColors) {
      if (selected.any((item) => item.code == color.code)) continue;
      var distance = ColorScience.deltaE2000(center, color.lab);
      // Portrait mode only uses a tiny preference for Mini skin-family colors;
      // it never excludes a closer color, avoiding the old orange skin cast.
      if (skinCluster && color.series == 'MG') distance *= 0.96;
      if (distance < bestDistance) {
        best = color;
        bestDistance = distance;
      }
    }
    if (best != null) {
      selected.add(best);
      selectedCenters.add(center);
    }
  }

  if (selected.isEmpty) selected.add(paletteColors.first);
  return selected;
}

LabColor _applyVariantStyle(LabColor color, int seed) {
  if (seed == 0) return color;
  final style = seed.abs() % 4;
  return switch (style) {
    0 => LabColor((color.l + 1.2).clamp(0, 100), color.a + 3.5, color.b + 6),
    1 => LabColor((color.l + 0.5).clamp(0, 100), color.a - 2, color.b - 7),
    2 => LabColor(
      color.l,
      (color.a * 1.16).clamp(-128, 127),
      (color.b * 1.16).clamp(-128, 127),
    ),
    _ => LabColor((color.l + 2).clamp(0, 100), color.a * 0.78, color.b * 0.78),
  };
}

int _nearestCandidateIndex(
  LabColor pixel,
  List<BeadColor> candidates,
  List<int> allowedIndices,
) {
  final nearestIndices = List<int>.filled(4, allowedIndices.first);
  final nearestDistances = List<double>.filled(4, double.infinity);
  for (final index in allowedIndices) {
    final lab = candidates[index].lab;
    final dl = pixel.l - lab.l;
    final da = pixel.a - lab.a;
    final db = pixel.b - lab.b;
    final distance = dl * dl + da * da + db * db;
    for (var slot = 0; slot < 4; slot++) {
      if (distance < nearestDistances[slot]) {
        for (var shift = 3; shift > slot; shift--) {
          nearestDistances[shift] = nearestDistances[shift - 1];
          nearestIndices[shift] = nearestIndices[shift - 1];
        }
        nearestDistances[slot] = distance;
        nearestIndices[slot] = index;
        break;
      }
    }
  }
  var bestIndex = nearestIndices.first;
  var bestDelta = double.infinity;
  final checks = math.min(4, allowedIndices.length);
  for (var slot = 0; slot < checks; slot++) {
    final index = nearestIndices[slot];
    final delta = ColorScience.deltaE2000(pixel, candidates[index].lab);
    if (delta < bestDelta) {
      bestDelta = delta;
      bestIndex = index;
    }
  }
  return bestIndex;
}

List<int> _removeIsolatedCells(List<int> source, int width, int height) {
  final result = List<int>.from(source);
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final index = y * width + x;
      if (source[index] < 0) continue;
      final neighbors = [
        source[index - 1],
        source[index + 1],
        source[index - width],
        source[index + width],
      ];
      if (neighbors.any((value) => value < 0)) continue;
      final frequency = <int, int>{};
      for (final value in neighbors) {
        frequency[value] = (frequency[value] ?? 0) + 1;
      }
      final majority = frequency.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      if (majority.value == 4 && source[index] != majority.key) {
        result[index] = majority.key;
      }
    }
  }
  return result;
}
