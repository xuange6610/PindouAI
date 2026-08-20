import 'package:bead_ai_designer/services/board_color_replacer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('批量换色只替换匹配色号并保留空白格', () {
    final cells = <int>[2, -1, 1, 2, 0, 2, -1];

    final changes = replaceBoardColorInPlace(cells, source: 2, target: 7);

    expect(cells, <int>[7, -1, 1, 7, 0, 7, -1]);
    expect(changes, <int, int>{0: 2, 3: 2, 5: 2});

    for (final entry in changes.entries) {
      cells[entry.key] = entry.value;
    }
    expect(cells, <int>[2, -1, 1, 2, 0, 2, -1]);
  });

  test('相同色号或画板未使用该色号时不产生修改记录', () {
    final cells = <int>[1, 2, -1];

    expect(replaceBoardColorInPlace(cells, source: 1, target: 1), isEmpty);
    expect(replaceBoardColorInPlace(cells, source: 8, target: 3), isEmpty);
    expect(cells, <int>[1, 2, -1]);
  });
}
