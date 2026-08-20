import 'dart:io';

import 'package:bead_ai_designer/services/app_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('错误分类能区分网络、鉴权、限额、服务端和返回格式', () {
    expect(
      AppErrorClassifier.classify(const SocketException('DNS')).category,
      AppErrorCategory.network,
    );
    expect(
      AppErrorClassifier.classify(
        StateError('HTTP 401 invalid api key'),
      ).category,
      AppErrorCategory.authentication,
    );
    expect(
      AppErrorClassifier.classify(StateError('HTTP 429 rate limit')).category,
      AppErrorCategory.quota,
    );
    expect(
      AppErrorClassifier.classify(StateError('HTTP 503')).category,
      AppErrorCategory.server,
    );
    final unavailable = AppErrorClassifier.classify(
      StateError('Service temporarily unavailable'),
      operation: 'AI 连接测试',
    );
    expect(unavailable.category, AppErrorCategory.server);
    expect(unavailable.message, contains('Service temporarily unavailable'));
    final missingRoute = AppErrorClassifier.classify(
      StateError('HTTP 404，端点 /v1/videos'),
      operation: '视频模型测试',
    );
    expect(missingRoute.message, contains('/v1/videos'));
    expect(
      AppErrorClassifier.classify(
        const FormatException('invalid json'),
      ).category,
      AppErrorCategory.response,
    );
  });
}
