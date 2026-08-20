import 'package:bead_ai_designer/screens/api_management_screen.dart';
import 'package:bead_ai_designer/services/api_clipboard_import.dart';
import 'package:bead_ai_designer/services/api_profile_store.dart';
import 'package:bead_ai_designer/services/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('API 管理支持双击打开入口和把当前或列表配置完整复制分享', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    final secrets = <String, String>{};
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
          final arguments = (call.arguments as Map?)?.cast<String, dynamic>();
          final key = arguments?['key'] as String?;
          if (call.method == 'read') return key == null ? null : secrets[key];
          if (call.method == 'write') {
            secrets[key!] = arguments!['value'] as String;
          }
          if (call.method == 'delete' && key != null) secrets.remove(key);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': ''};
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });

    await AppSettings.instance.initialize();
    await AppSettings.instance.setAiProxyBaseUrl('');
    await AppSettings.instance.setAiProviderAndCollectionBaseUrl(
      'https://relay.example.com/v1',
    );
    await AppSettings.instance.setAiProviderKey('sk-manager_123456789');
    await AppSettings.instance.setAiModels('qwen-max');
    final store = ApiProfileStore();
    final profile = await store.saveCurrent(name: '分享线路');

    await tester.pumpWidget(
      MaterialApp(home: ApiManagementScreen(store: store)),
    );
    await tester.pumpAndSettle();

    final tile = tester.widget<InkWell>(
      find.byKey(ValueKey('apiProfile_${profile.id}')),
    );
    expect(tile.onDoubleTap, isNotNull);

    await tester.tap(
      find.byKey(const ValueKey('copyCurrentApiConfigurationButton')),
    );
    await tester.pump();
    expect(
      ApiClipboardImportParser.parse(copied ?? '').apiKey,
      'sk-manager_123456789',
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享（复制完整配置）'));
    await tester.pumpAndSettle();
    final shared = ApiClipboardImportParser.parse(copied ?? '');
    expect(shared.profileName, '分享线路');
    expect(shared.providerBaseUrl, 'https://relay.example.com/v1');
    expect(shared.apiKey, 'sk-manager_123456789');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });
}
