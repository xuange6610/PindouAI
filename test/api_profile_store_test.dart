import 'dart:convert';

import 'package:bead_ai_designer/services/api_profile_store.dart';
import 'package:bead_ai_designer/services/api_clipboard_import.dart';
import 'package:bead_ai_designer/services/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('API 管理可安全保存、切换并完整导入导出多套配置', () async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    final secrets = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final arguments = (call.arguments as Map?)?.cast<String, dynamic>();
          final key = arguments?['key'] as String?;
          switch (call.method) {
            case 'read':
              return key == null ? null : secrets[key];
            case 'write':
              secrets[key!] = arguments!['value'] as String;
              return null;
            case 'delete':
              if (key != null) secrets.remove(key);
              return null;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await AppSettings.instance.initialize();
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderAndCollectionBaseUrl(
      'https://one.example.com/v1',
    );
    await AppSettings.instance.setAiProviderKey('sk-first_123456789');
    await AppSettings.instance.setAiModels('qwen-max');
    final store = ApiProfileStore();
    final first = await store.saveCurrent(name: '主线路');

    await AppSettings.instance.setAiProviderAndCollectionBaseUrl(
      'https://two.example.com/v1',
    );
    await AppSettings.instance.setAiProviderKey('sk-second_987654321');
    await AppSettings.instance.setAiModels('glm-5');
    await store.saveCurrent(name: '备用线路');
    expect(store.profiles, hasLength(2));

    await store.activate(first);
    expect(
      AppSettings.instance.aiProviderBaseUrl,
      'https://one.example.com/v1',
    );
    expect(AppSettings.instance.aiProviderKey, 'sk-first_123456789');
    expect(AppSettings.instance.aiChatModel, 'qwen-max');
    expect(store.activeProfileId, first.id);

    final exported = store.exportBundle();
    final payload = jsonDecode(utf8.decode(exported)) as Map<String, dynamic>;
    expect(payload['schema'], ApiProfileStore.bundleSchema);
    expect(jsonEncode(payload), contains('sk-first_123456789'));
    final shared = store.shareText(first);
    final sharedData = ApiClipboardImportParser.parse(shared);
    expect(sharedData.profileName, '主线路');
    expect(sharedData.providerBaseUrl, 'https://one.example.com/v1');
    expect(sharedData.apiKey, 'sk-first_123456789');
    expect(sharedData.model, 'qwen-max');
    expect(sharedData.protocol, AiProviderProtocol.auto);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('api_profile_metadata_v1'),
      isNot(contains('sk-first_123456789')),
    );

    final imported = await store.importBundle(exported);
    expect(imported, 2);
    expect(store.profiles, hasLength(4));
    expect(store.profiles.map((value) => value.name).toSet(), hasLength(4));
  });
}
