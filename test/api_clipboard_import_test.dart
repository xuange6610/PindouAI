import 'package:bead_ai_designer/services/api_clipboard_import.dart';
import 'package:bead_ai_designer/services/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('可从一段剪贴板文本准确识别密钥、两类地址和 GPT 模型', () {
    final data = ApiClipboardImportParser.parse('''
API 密钥：sk-test_1234567890
API 中转地址：https://gateway.example.com/v1
原图库服务地址：https://images.example.com/v1
模型：gpt5.6sol
''');

    expect(data.apiKey, 'sk-test_1234567890');
    expect(data.providerBaseUrl, 'https://gateway.example.com/v1');
    expect(data.collectionBaseUrl, 'https://images.example.com/v1');
    expect(data.model, 'gpt-5.6-sol');
    expect(data.canOfferAutomatically, isTrue);
  });

  test('只提供一条中转地址时会同步作为原图库地址', () {
    final data = ApiClipboardImportParser.parse(
      'sk-abcdefghijklmnopqrst\nhttps://ciyuan.fast/v1',
    );

    expect(data.providerBaseUrl, 'https://ciyuan.fast/v1');
    expect(data.collectionBaseUrl, data.providerBaseUrl);
    expect(data.canOfferAutomatically, isTrue);
  });

  test('没有模型标签也能识别常见模型 ID，且不会误判为 API 密钥', () {
    final qwen = ApiClipboardImportParser.parse('qwen-max');
    final claude = ApiClipboardImportParser.parse(
      '请使用 claude-sonnet-4-20250514',
    );

    expect(qwen.model, 'qwen-max');
    expect(qwen.apiKey, isNull);
    expect(qwen.canOfferAutomatically, isTrue);
    expect(claude.model, 'claude-sonnet-4-20250514');
    expect(claude.apiKey, isNull);
  });

  test('可完整识别用于分享的 JSON 配置包', () {
    final data = ApiClipboardImportParser.parse('''
{
  "schema": "bead-ai-api-profiles",
  "version": 2,
  "profiles": [{
    "name": "主线路",
    "appServerBaseUrl": "https://app.example.com",
    "providerBaseUrl": "https://gateway.example.com/v1",
    "apiKey": "sk-shared_123456789",
    "collectionBaseUrl": "https://library.example.com/v1",
    "chatModel": "qwen-max",
    "imageModel": "qwen-max",
    "videoModel": "qwen-max",
    "protocol": "openAiCompatible"
  }]
}
''');

    expect(data.profileName, '主线路');
    expect(data.appServerBaseUrl, 'https://app.example.com');
    expect(data.providerBaseUrl, 'https://gateway.example.com/v1');
    expect(data.apiKey, 'sk-shared_123456789');
    expect(data.collectionBaseUrl, 'https://library.example.com/v1');
    expect(data.model, 'qwen-max');
    expect(data.protocol, AiProviderProtocol.openAiCompatible);
    expect(data.canOfferAutomatically, isTrue);
  });
}
