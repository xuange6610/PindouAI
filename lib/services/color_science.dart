import 'dart:math' as math;

import '../models/bead_color.dart';

abstract final class ColorScience {
  static LabColor rgbToLab(int red, int green, int blue) {
    double linearize(int value) {
      final channel = value / 255.0;
      return channel <= 0.04045
          ? channel / 12.92
          : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = linearize(red);
    final g = linearize(green);
    final b = linearize(blue);

    final x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047;
    final y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750;
    final z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883;

    double pivot(double value) => value > 0.008856
        ? math.pow(value, 1 / 3).toDouble()
        : (7.787 * value) + (16 / 116);

    final fx = pivot(x);
    final fy = pivot(y);
    final fz = pivot(z);
    return LabColor((116 * fy) - 16, 500 * (fx - fy), 200 * (fy - fz));
  }

  /// CIEDE2000 implementation using D65 LAB values.
  static double deltaE2000(LabColor first, LabColor second) {
    final l1 = first.l;
    final a1 = first.a;
    final b1 = first.b;
    final l2 = second.l;
    final a2 = second.a;
    final b2 = second.b;

    final c1 = math.sqrt(a1 * a1 + b1 * b1);
    final c2 = math.sqrt(a2 * a2 + b2 * b2);
    final cBar = (c1 + c2) / 2;
    final cBar7 = math.pow(cBar, 7).toDouble();
    final g = 0.5 * (1 - math.sqrt(cBar7 / (cBar7 + math.pow(25, 7))));
    final a1Prime = (1 + g) * a1;
    final a2Prime = (1 + g) * a2;
    final c1Prime = math.sqrt(a1Prime * a1Prime + b1 * b1);
    final c2Prime = math.sqrt(a2Prime * a2Prime + b2 * b2);

    double hue(double a, double b) {
      if (a == 0 && b == 0) return 0;
      final degrees = math.atan2(b, a) * 180 / math.pi;
      return degrees >= 0 ? degrees : degrees + 360;
    }

    final h1Prime = hue(a1Prime, b1);
    final h2Prime = hue(a2Prime, b2);
    final deltaLPrime = l2 - l1;
    final deltaCPrime = c2Prime - c1Prime;
    final hueDifference = h2Prime - h1Prime;
    final deltaHDegrees = c1Prime * c2Prime == 0
        ? 0.0
        : hueDifference.abs() <= 180
        ? hueDifference
        : hueDifference > 180
        ? hueDifference - 360
        : hueDifference + 360;
    final deltaHPrime =
        2 *
        math.sqrt(c1Prime * c2Prime) *
        math.sin((deltaHDegrees / 2) * math.pi / 180);

    final lBarPrime = (l1 + l2) / 2;
    final cBarPrime = (c1Prime + c2Prime) / 2;
    final hBarPrime = c1Prime * c2Prime == 0
        ? h1Prime + h2Prime
        : (h1Prime - h2Prime).abs() <= 180
        ? (h1Prime + h2Prime) / 2
        : h1Prime + h2Prime < 360
        ? (h1Prime + h2Prime + 360) / 2
        : (h1Prime + h2Prime - 360) / 2;

    double cosDegrees(double value) => math.cos(value * math.pi / 180);
    final t =
        1 -
        0.17 * cosDegrees(hBarPrime - 30) +
        0.24 * cosDegrees(2 * hBarPrime) +
        0.32 * cosDegrees(3 * hBarPrime + 6) -
        0.20 * cosDegrees(4 * hBarPrime - 63);
    final deltaTheta = 30 * math.exp(-math.pow((hBarPrime - 275) / 25, 2));
    final cBarPrime7 = math.pow(cBarPrime, 7).toDouble();
    final rc = 2 * math.sqrt(cBarPrime7 / (cBarPrime7 + math.pow(25, 7)));
    final sl =
        1 +
        (0.015 * math.pow(lBarPrime - 50, 2)) /
            math.sqrt(20 + math.pow(lBarPrime - 50, 2));
    final sc = 1 + 0.045 * cBarPrime;
    final sh = 1 + 0.015 * cBarPrime * t;
    final rt = -math.sin(2 * deltaTheta * math.pi / 180) * rc;
    final lTerm = deltaLPrime / sl;
    final cTerm = deltaCPrime / sc;
    final hTerm = deltaHPrime / sh;
    return math.sqrt(
      lTerm * lTerm + cTerm * cTerm + hTerm * hTerm + rt * cTerm * hTerm,
    );
  }

  static bool looksLikeSkin(int r, int g, int b) {
    final maxValue = math.max(r, math.max(g, b));
    final minValue = math.min(r, math.min(g, b));
    final rgbRule =
        r > 70 &&
        g > 35 &&
        b > 20 &&
        maxValue - minValue > 12 &&
        r > g &&
        r > b;
    final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
    final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
    return rgbRule && cb >= 72 && cb <= 135 && cr >= 128 && cr <= 178;
  }
}
