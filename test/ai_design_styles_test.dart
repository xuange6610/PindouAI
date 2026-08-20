import 'package:bead_ai_designer/services/ai_design_styles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI 拼豆制图提供四种独立风格和参考图转换提示词', () {
    expect(AiBeadDesignStyles.all, hasLength(4));
    expect(
      AiBeadDesignStyles.all.map((style) => style.id).toSet(),
      hasLength(4),
    );
    expect(
      AiBeadDesignStyles.all.map((style) => style.stylePrompt).toSet(),
      hasLength(4),
    );
    for (final style in AiBeadDesignStyles.all) {
      final prompt = style.buildPrompt('保留两个人');
      expect(prompt, contains(style.title));
      expect(prompt, contains('保留参考照片中的人物数量'));
      expect(prompt, contains('保留两个人'));
      expect(prompt, contains('色号、豆子数量、品牌款式或图例'));
      expect(style.exampleAsset, startsWith('assets/pindou_collection/'));
    }
  });
}
