import 'package:bead_ai_designer/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('应用内置中文字体，不依赖 Android 厂商系统字体', () async {
    final theme = AppTheme.light;
    final fontData = await rootBundle.load('assets/fonts/NotoSansSC-VF.ttf');

    expect(theme.textTheme.bodyMedium?.fontFamily, 'NotoSansSC');
    expect(fontData.lengthInBytes, greaterThan(10 * 1024 * 1024));
  });

  test('极浅自定义颜色会保留色相并自动转换为可读主题色', () {
    const selected = Color(0xFFBFFFFF);
    final theme = AppTheme.lightWith(selected);
    final primary = theme.colorScheme.primary;

    expect(primary, isNot(selected));
    expect(theme.colorScheme.onPrimary, Colors.white);
    expect(
      _contrastRatio(primary, theme.colorScheme.onPrimary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      HSLColor.fromColor(primary).hue,
      closeTo(HSLColor.fromColor(selected).hue, 1),
    );
  });

  test('原本已经可读的深色不会被改变', () {
    const selected = Color(0xFF174A7E);
    expect(AppTheme.accessibleAccent(selected), selected);
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
