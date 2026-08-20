import 'dart:convert';

import 'package:bead_ai_designer/services/click_sound_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('内置十种点击音效 ID 唯一且生成不同的有效 WAV', () {
    expect(ClickSoundService.options, hasLength(10));
    expect(
      ClickSoundService.options.map((option) => option.id).toSet(),
      hasLength(10),
    );
    final encoded = <String>{};
    for (final option in ClickSoundService.options) {
      final bytes = ClickSoundService.instance.buildSoundBytes(option.id);
      expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
      expect(bytes.length, greaterThan(500));
      encoded.add(base64Encode(bytes));
    }
    expect(encoded, hasLength(10));
  });
}
