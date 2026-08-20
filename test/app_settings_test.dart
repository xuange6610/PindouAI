import 'package:bead_ai_designer/services/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('旧版错误主题值迁移为默认红色并按完整 RGB 即时应用', () async {
    SharedPreferences.setMockInitialValues({
      'appearance_accent_rgb': 0,
      'appearance_accent_format_version': 1,
      'ai_provider_base_url': 'https://api.ciyuan.fast/v1',
      'collection_original_base_url': 'https://api.ciyuan.fast',
    });
    await AppSettings.instance.initialize();
    expect(AppSettings.instance.accent.toARGB32(), 0xFFE96354);
    expect(
      AppSettings.instance.aiProviderBaseUrl,
      AppSettings.defaultAiProviderBaseUrl,
    );
    expect(
      AppSettings.instance.collectionBaseUrl,
      AppSettings.defaultAiProviderBaseUrl,
    );
    expect(AppSettings.instance.aiMemoryEnabled, isTrue);

    await AppSettings.instance.setAccent(const Color(0xFF123456));
    expect(AppSettings.instance.accent.toARGB32(), 0xFF123456);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt('appearance_accent_rgb'), 0x123456);
    expect(preferences.getInt('appearance_accent_format_version'), 2);

    await AppSettings.instance.setAiProviderAndCollectionBaseUrl(
      '  https://gateway.example.com/v1  ',
    );
    expect(
      AppSettings.instance.aiProviderBaseUrl,
      'https://gateway.example.com/v1',
    );
    expect(
      AppSettings.instance.collectionBaseUrl,
      'https://gateway.example.com/v1',
    );
    expect(
      preferences.getString('ai_provider_base_url'),
      'https://gateway.example.com/v1',
    );
    expect(
      preferences.getString('collection_original_base_url'),
      'https://gateway.example.com/v1',
    );
  });

  test('从任一入口切换模型都会同步三个持久化键', () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.setAiVideoModel('gpt5.6sol');

    expect(AppSettings.instance.aiChatModel, 'gpt-5.6-sol');
    expect(AppSettings.instance.aiImageModel, 'gpt-5.6-sol');
    expect(AppSettings.instance.aiVideoModel, 'gpt-5.6-sol');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('ai_provider_chat_model'), 'gpt-5.6-sol');
    expect(preferences.getString('ai_provider_image_model'), 'gpt-5.6-sol');
    expect(preferences.getString('ai_provider_video_model'), 'gpt-5.6-sol');

    await AppSettings.instance.setClickSoundId('glass');
    expect(AppSettings.instance.clickSoundId, 'glass');
    expect(preferences.getString('appearance_click_sound_id'), 'glass');
  });

  test('词元旧域名和缺少版本路径的地址会自动迁移', () {
    expect(
      AppSettings.normalizeAiProviderBaseUrl(
        'https://api.ciyuan.fast/v1/chat/completions',
      ),
      'https://ciyuan.fast/v1',
    );
    expect(
      AppSettings.normalizeAiProviderBaseUrl('https://ciyuan.fast'),
      'https://ciyuan.fast/v1',
    );
  });
}
