import 'package:bead_ai_designer/models/bead_color.dart';
import 'package:bead_ai_designer/services/color_science.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CIEDE2000 与公开标准测试对一致', () {
    const first = LabColor(50, 2.6772, -79.7751);
    const second = LabColor(50, 0, -82.7485);
    expect(ColorScience.deltaE2000(first, second), closeTo(2.0425, 0.0001));
  });

  test('sRGB 白色和黑色转换到合理 LAB', () {
    final white = ColorScience.rgbToLab(255, 255, 255);
    final black = ColorScience.rgbToLab(0, 0, 0);
    expect(white.l, closeTo(100, 0.001));
    expect(black.l, closeTo(0, 0.001));
  });
}
