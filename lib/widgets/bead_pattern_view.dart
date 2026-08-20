import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/bead_pattern.dart';

class BeadPatternView extends StatelessWidget {
  const BeadPatternView({
    super.key,
    required this.pattern,
    this.showCodes = false,
    this.interactive = false,
    this.padding = 12,
  });

  final BeadPattern pattern;
  final bool showCodes;
  final bool interactive;
  final double padding;

  @override
  Widget build(BuildContext context) {
    if (interactive) {
      final cell = showCodes ? 24.0 : 14.0;
      final size = Size(pattern.width * cell, pattern.height * cell);
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: ColoredBox(
            color: const Color(0xFFF3ECE6),
            child: InteractiveViewer.builder(
              minScale: 0.08,
              maxScale: 5,
              boundaryMargin: const EdgeInsets.all(180),
              alignment: Alignment.topLeft,
              builder: (context, viewport) {
                final xs = [
                  viewport.point0.x,
                  viewport.point1.x,
                  viewport.point2.x,
                  viewport.point3.x,
                ];
                final ys = [
                  viewport.point0.y,
                  viewport.point1.y,
                  viewport.point2.y,
                  viewport.point3.y,
                ];
                final visible = Rect.fromLTRB(
                  xs.reduce(math.min),
                  ys.reduce(math.min),
                  xs.reduce(math.max),
                  ys.reduce(math.max),
                ).inflate(cell * 2);
                return SizedBox.fromSize(
                  size: size,
                  child: CustomPaint(
                    isComplex: true,
                    willChange: true,
                    painter: BeadPatternPainter(
                      pattern,
                      showCodes: showCodes,
                      visibleRect: visible,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: AspectRatio(
          aspectRatio: pattern.width / pattern.height,
          child: CustomPaint(
            isComplex: true,
            willChange: false,
            painter: BeadPatternPainter(pattern, showCodes: showCodes),
          ),
        ),
      ),
    );
  }
}

class BeadPatternPainter extends CustomPainter {
  BeadPatternPainter(this.pattern, {this.showCodes = false, this.visibleRect});

  final BeadPattern pattern;
  final bool showCodes;
  final Rect? visibleRect;

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / pattern.width;
    final cellHeight = size.height / pattern.height;
    final cell = math.min(cellWidth, cellHeight);
    final beadPaint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.35, cell * 0.035)
      ..color = Colors.black.withValues(alpha: 0.13);
    final holePaint = Paint()..style = PaintingStyle.fill;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF4EEE8),
    );
    final visible = visibleRect ?? (Offset.zero & size);
    final startX = (visible.left / cellWidth).floor().clamp(0, pattern.width);
    final endX = (visible.right / cellWidth).ceil().clamp(0, pattern.width);
    final startY = (visible.top / cellHeight).floor().clamp(0, pattern.height);
    final endY = (visible.bottom / cellHeight).ceil().clamp(0, pattern.height);
    final visibleCellCount = (endX - startX) * (endY - startY);

    // At overview scale a 200 x 200 board used to build tens of thousands of
    // TextPainters and circles in one frame. Draw one batched path per color
    // instead; details are restored automatically as the user zooms in.
    if (visibleCellCount > 2400 || cell < 2.4) {
      final colorPaths = List<Path>.generate(
        pattern.colors.length,
        (_) => Path(),
        growable: false,
      );
      for (var y = startY; y < endY; y++) {
        for (var x = startX; x < endX; x++) {
          final colorIndex = pattern.cells[y * pattern.width + x];
          if (colorIndex < 0) continue;
          colorPaths[colorIndex].addRect(
            Rect.fromLTWH(
              x * cellWidth,
              y * cellHeight,
              cellWidth + 0.08,
              cellHeight + 0.08,
            ),
          );
        }
      }
      for (var index = 0; index < colorPaths.length; index++) {
        if (colorPaths[index].getBounds().isEmpty) continue;
        canvas.drawPath(
          colorPaths[index],
          Paint()
            ..style = PaintingStyle.fill
            ..color = pattern.colors[index].color,
        );
      }
      return;
    }

    final paintCodes = showCodes && visibleCellCount <= 1400;
    for (var y = startY; y < endY; y++) {
      for (var x = startX; x < endX; x++) {
        final colorIndex = pattern.cells[y * pattern.width + x];
        if (colorIndex < 0) continue;
        final color = pattern.colors[colorIndex];
        final center = Offset((x + 0.5) * cellWidth, (y + 0.5) * cellHeight);
        final radius = cell * 0.455;
        beadPaint.color = color.color;
        canvas.drawCircle(center, radius, beadPaint);
        canvas.drawCircle(center, radius, borderPaint);
        if (!showCodes) {
          holePaint.color = Color.fromARGB(
            115,
            (color.red * 0.45).round(),
            (color.green * 0.45).round(),
            (color.blue * 0.45).round(),
          );
          canvas.drawCircle(center, math.max(0.7, radius * 0.23), holePaint);
          if (cell >= 7) {
            canvas.drawCircle(
              center.translate(-radius * 0.27, -radius * 0.27),
              radius * 0.12,
              Paint()..color = Colors.white.withValues(alpha: 0.48),
            );
          }
        } else if (paintCodes && cell >= 8) {
          final luminance = color.color.computeLuminance();
          final textPainter = TextPainter(
            text: TextSpan(
              text: color.code,
              style: TextStyle(
                color: luminance > 0.55 ? Colors.black87 : Colors.white,
                fontSize: (cell * 0.29).clamp(5.0, 10.0),
                fontWeight: FontWeight.w800,
              ),
            ),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: cellWidth);
          textPainter.paint(
            canvas,
            center - Offset(textPainter.width / 2, textPainter.height / 2),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant BeadPatternPainter oldDelegate) => true;
}
