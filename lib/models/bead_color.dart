import 'package:flutter/material.dart';

class LabColor {
  const LabColor(this.l, this.a, this.b);

  final double l;
  final double a;
  final double b;
}

class BeadColor {
  const BeadColor({
    required this.id,
    required this.brand,
    required this.series,
    required this.code,
    required this.nameCn,
    required this.nameEn,
    required this.red,
    required this.green,
    required this.blue,
    required this.lab,
    this.sizeMm = 2.6,
    this.type = '标准实色',
    this.isMeasured = false,
  });

  final int id;
  final String brand;
  final String series;
  final String code;
  final String nameCn;
  final String nameEn;
  final int red;
  final int green;
  final int blue;
  final LabColor lab;
  final double sizeMm;
  final String type;
  final bool isMeasured;

  Color get color => Color.fromARGB(255, red, green, blue);

  String get hex =>
      ('#${red.toRadixString(16).padLeft(2, '0')}'
              '${green.toRadixString(16).padLeft(2, '0')}'
              '${blue.toRadixString(16).padLeft(2, '0')}')
          .toUpperCase();

  /// Matches code, English/Chinese labels and common Chinese hue searches.
  /// Palette source files contain a mixture of English names and raw codes,
  /// so hue matching is derived from the measured RGB value as a fallback.
  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final haystack = '$code $nameCn $nameEn $type $brand'.toLowerCase();
    if (haystack.contains(q)) return true;
    final hue = HSVColor.fromColor(color).hue;
    final saturation = HSVColor.fromColor(color).saturation;
    final value = HSVColor.fromColor(color).value;
    final isGrey = saturation < 0.12;
    if (q.contains('红') || q.contains('赤') || q.contains('粉')) {
      return hue >= 330 || hue < 18 || (hue >= 330 && saturation > 0.18);
    }
    if (q.contains('橙') || q.contains('橘')) return hue >= 18 && hue < 45;
    if (q.contains('黄') || q.contains('金')) return hue >= 40 && hue < 72;
    if (q.contains('绿') || q.contains('青')) return hue >= 72 && hue < 170;
    if (q.contains('蓝') || q.contains('靛')) return hue >= 170 && hue < 270;
    if (q.contains('紫') || q.contains('紫罗兰')) return hue >= 270 && hue < 330;
    if (q.contains('白')) return value > 0.86 && (isGrey || saturation < 0.22);
    if (q.contains('黑')) return value < 0.22;
    if (q.contains('灰')) return isGrey && value >= 0.22 && value <= 0.86;
    if (q.contains('棕') || q.contains('褐')) {
      return hue >= 15 && hue < 55 && value < 0.65;
    }
    return false;
  }

  Map<String, Object> toJson() => {
    'id': id,
    'brand': brand,
    'series': series,
    'code': code,
    'color_name_cn': nameCn,
    'color_name_en': nameEn,
    'rgb': [red, green, blue],
    'hex': hex,
    'lab': [lab.l, lab.a, lab.b],
    'size': sizeMm,
    'type': type,
    'is_measured': isMeasured,
  };
}
