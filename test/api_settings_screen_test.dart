import 'package:bead_ai_designer/screens/api_settings_screen.dart';
import 'package:bead_ai_designer/services/app_settings.dart';
import 'package:bead_ai_designer/services/api_clipboard_import.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('修改 API 中转地址会同步页面和设置中的原图库地址', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.setAiProviderBaseUrl(
      'https://old.example.com/v1',
    );
    await AppSettings.instance.setCollectionBaseUrl(
      'https://library.example.com/v1',
    );
    await tester.pumpWidget(const MaterialApp(home: ApiSettingsScreen()));

    const address = 'https://gateway.example.com/v1';
    await tester.enterText(
      find.byKey(const ValueKey('apiProviderBaseUrlField')),
      address,
    );
    await tester.pump();

    final collectionField = tester.widget<TextField>(
      find.byKey(const ValueKey('collectionBaseUrlField')),
    );
    expect(collectionField.controller?.text, address);
    expect(collectionField.obscureText, isTrue);
    expect(AppSettings.instance.aiProviderBaseUrl, address);
    expect(AppSettings.instance.collectionBaseUrl, address);

    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('测试结果会保留显示在本页面'), findsOneWidget);
    expect(find.byKey(const ValueKey('testAllAiModelsButton')), findsOneWidget);
  });

  testWidgets('修改任一模型输入会同步三个模型配置和输入框', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.setAiModels('old-model');
    await tester.pumpWidget(const MaterialApp(home: ApiSettingsScreen()));

    final chatField = find.byKey(const ValueKey('apiChatModelField'));
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.ensureVisible(chatField);
    await tester.enterText(chatField, 'glm-5.2');
    await tester.pump();

    expect(AppSettings.instance.aiChatModel, 'glm-5.2');
    expect(AppSettings.instance.aiImageModel, 'glm-5.2');
    expect(AppSettings.instance.aiVideoModel, 'glm-5.2');
    final imageFinder = find.byKey(const ValueKey('apiImageModelField'));
    await tester.ensureVisible(imageFinder);
    final imageField = tester.widget<TextField>(imageFinder);
    expect(imageField.controller?.text, 'glm-5.2');

    await tester.enterText(imageFinder, 'qwen-image-plus');
    await tester.pump();
    expect(AppSettings.instance.aiChatModel, 'qwen-image-plus');
    expect(AppSettings.instance.aiImageModel, 'qwen-image-plus');
    expect(AppSettings.instance.aiVideoModel, 'qwen-image-plus');

    final videoFinder = find.byKey(const ValueKey('apiVideoModelField'));
    await tester.ensureVisible(videoFinder);
    await tester.enterText(videoFinder, 'kling-video-v2');
    await tester.pump();
    expect(AppSettings.instance.aiChatModel, 'kling-video-v2');
    expect(AppSettings.instance.aiImageModel, 'kling-video-v2');
    expect(AppSettings.instance.aiVideoModel, 'kling-video-v2');

    await AppSettings.instance.setAiModels('claude-sonnet-4');
    await tester.pump();
    for (final key in const [
      'apiChatModelField',
      'apiImageModelField',
      'apiVideoModelField',
    ]) {
      final field = tester.widget<TextField>(find.byKey(ValueKey(key)));
      expect(field.controller?.text, 'claude-sonnet-4');
    }
  });

  testWidgets('打开 API 设置会识别剪贴板配置并在确认后覆盖对应字段', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return {
              'text':
                  'API 密钥：sk-clipboard_123456789\n'
                  'API 中转地址：https://gateway.example.com/v1\n'
                  '原图库：https://library.example.com/v1\n'
                  '模型：gpt5.6sol',
            };
          }
          return null;
        });
    await AppSettings.instance.setAiProviderKey('old-key');
    await AppSettings.instance.setAiProviderAndCollectionBaseUrl(
      'https://old.example.com/v1',
    );
    await AppSettings.instance.setAiModels('qwen-max');

    await tester.pumpWidget(const MaterialApp(home: ApiSettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('检测到剪贴板 API 配置'), findsOneWidget);
    await tester.tap(find.text('确认覆盖'));
    await tester.pumpAndSettle();

    expect(AppSettings.instance.aiProviderKey, 'sk-clipboard_123456789');
    expect(
      AppSettings.instance.aiProviderBaseUrl,
      'https://gateway.example.com/v1',
    );
    expect(
      AppSettings.instance.collectionBaseUrl,
      'https://library.example.com/v1',
    );
    expect(AppSettings.instance.aiChatModel, 'gpt-5.6-sol');
    expect(AppSettings.instance.aiImageModel, 'gpt-5.6-sol');
    expect(AppSettings.instance.aiVideoModel, 'gpt-5.6-sol');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  testWidgets('剪贴板没有模型时保留当前三个模型设置', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return {
              'text':
                  'API 密钥：sk-new_1234567890\n'
                  'API 中转地址：https://new.example.com/v1',
            };
          }
          return null;
        });
    await AppSettings.instance.setAiModels('qwen-max');

    await tester.pumpWidget(const MaterialApp(home: ApiSettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('检测到剪贴板 API 配置'), findsOneWidget);
    await tester.tap(find.text('确认覆盖'));
    await tester.pumpAndSettle();

    expect(AppSettings.instance.aiChatModel, 'qwen-max');
    expect(AppSettings.instance.aiImageModel, 'qwen-max');
    expect(AppSettings.instance.aiVideoModel, 'qwen-max');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  testWidgets('剪贴板复制示例展示完整教程并能复制推荐样板', (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': ''};
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });

    await tester.pumpWidget(const MaterialApp(home: ApiSettingsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apiClipboardExampleButton')));
    await tester.pumpAndSettle();

    expect(find.text('剪贴板配置示例与教程'), findsOneWidget);
    expect(
      find.textContaining('BASE_URL=https://gateway.example.com/v1'),
      findsOneWidget,
    );
    expect(find.textContaining('无标签独立行'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('copyApiClipboardExampleButton')),
    );
    await tester.pump();
    expect(copied, contains('API 密钥：sk-请替换为你的密钥'));
    expect(copied, contains('模型：gpt-5.6-sol'));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('一键复制当前配置会写入可直接识别的完整分享包', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': ''};
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    await AppSettings.instance.setAiProxyBaseUrl('https://app.example.com');
    await AppSettings.instance.setAiProviderAndCollectionBaseUrl(
      'https://share.example.com/v1',
    );
    await AppSettings.instance.setAiProviderKey('sk-copy_1234567890');
    await AppSettings.instance.setAiModels('glm-5');
    await AppSettings.instance.setAiProviderProtocol(
      AiProviderProtocol.openAiCompatible,
    );

    await tester.pumpWidget(const MaterialApp(home: ApiSettingsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('copyCurrentApiConfigurationButton')),
    );
    await tester.pump();

    final parsed = ApiClipboardImportParser.parse(copied ?? '');
    expect(parsed.appServerBaseUrl, 'https://app.example.com');
    expect(parsed.providerBaseUrl, 'https://share.example.com/v1');
    expect(parsed.apiKey, 'sk-copy_1234567890');
    expect(parsed.model, 'glm-5');
    expect(parsed.protocol, AiProviderProtocol.openAiCompatible);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  testWidgets('自动剪贴板提示可在本次运行期间关闭且手动导入仍保留', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return {
              'text':
                  'API 密钥：sk-session_123456789\n'
                  'API 中转地址：https://session.example.com/v1',
            };
          }
          return null;
        });
    await AppSettings.instance.setAiProviderKey('old-session-key');
    await AppSettings.instance.setAiProviderAndCollectionBaseUrl(
      'https://old-session.example.com/v1',
    );

    await tester.pumpWidget(const MaterialApp(home: ApiSettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('检测到剪贴板 API 配置'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('suppressClipboardApiOfferForSession')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('检测到剪贴板 API 配置'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: ApiSettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('检测到剪贴板 API 配置'), findsNothing);
    expect(
      find.byKey(const ValueKey('importApiClipboardButton')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });
}
