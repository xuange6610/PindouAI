import 'package:bead_ai_designer/screens/embedded_browser_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('内置浏览器将 API /v1 地址转换为可浏览的网站首页', () {
    expect(browserPageUrl('https://ciyuan.fast/v1'), 'https://ciyuan.fast/');
    expect(
      browserPageUrl('https://example.com/api/v1/'),
      'https://example.com/',
    );
    expect(
      browserPageUrl('https://example.com/docs/start'),
      'https://example.com/docs/start',
    );
  });
}
