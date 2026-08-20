import 'dart:async';
import 'dart:io';

enum AppErrorCategory {
  network('网络连接'),
  timeout('请求超时'),
  authentication('身份验证'),
  quota('余额或限额'),
  permission('权限'),
  configuration('配置'),
  server('服务端'),
  response('返回数据'),
  storage('本地存储'),
  cancelled('已取消'),
  unknown('程序异常');

  const AppErrorCategory(this.label);
  final String label;
}

class AppErrorInfo {
  const AppErrorInfo({
    required this.category,
    required this.title,
    required this.message,
    required this.suggestion,
    this.canOpenApiSettings = false,
  });

  final AppErrorCategory category;
  final String title;
  final String message;
  final String suggestion;
  final bool canOpenApiSettings;

  String get displayText => '$title：$message\n$suggestion';
}

class AppErrorClassifier {
  const AppErrorClassifier._();

  static AppErrorInfo classify(Object error, {String? operation}) {
    final prefix = operation == null || operation.trim().isEmpty
        ? ''
        : '${operation.trim()}失败';
    final raw = _clean(error.toString());
    final value = raw.toLowerCase();

    if (error is TimeoutException ||
        value.contains('timeout') ||
        value.contains('timed out') ||
        value.contains('超时')) {
      return AppErrorInfo(
        category: AppErrorCategory.timeout,
        title: prefix.isEmpty ? '请求超时' : prefix,
        message: '服务器在限定时间内没有完成响应。',
        suggestion: '请检查网络后重试；生成图片或视频时也可放入任务中心后台等待。',
        canOpenApiSettings: true,
      );
    }
    if (error is SocketException ||
        error is HandshakeException ||
        value.contains('socketexception') ||
        value.contains('failed host lookup') ||
        value.contains('connection refused') ||
        value.contains('connection reset') ||
        value.contains('connection abort') ||
        value.contains('connection closed') ||
        value.contains('broken pipe') ||
        value.contains('network is unreachable') ||
        value.contains('certificate') ||
        value.contains('handshake')) {
      final certificate =
          error is HandshakeException || value.contains('certificate');
      return AppErrorInfo(
        category: AppErrorCategory.network,
        title: prefix.isEmpty ? '网络连接失败' : prefix,
        message: certificate
            ? 'HTTPS 证书校验失败，服务地址证书可能过期、域名不匹配或被网络拦截。'
            : '设备无法连接服务器，可能是断网、DNS 解析失败、地址不可达或服务未启动。',
        suggestion: '请确认 Wi‑Fi/移动网络和 API 地址；本地服务还要确认手机能访问服务器所在设备。',
        canOpenApiSettings: true,
      );
    }
    if (_containsAny(value, const [
      '401',
      '403',
      'unauthorized',
      'forbidden',
      'invalid api key',
      'authentication',
      '鉴权',
      '密钥无效',
      '无权限',
    ])) {
      return AppErrorInfo(
        category: AppErrorCategory.authentication,
        title: prefix.isEmpty ? 'API 身份验证失败' : prefix,
        message: 'API 密钥无效、已过期，或当前账户没有调用该模型的权限。',
        suggestion: '请重新复制完整密钥，并确认中转账户已开通对应模型。',
        canOpenApiSettings: true,
      );
    }
    if (_containsAny(value, const [
      '402',
      '429',
      'quota',
      'rate limit',
      'insufficient',
      '余额',
      '限额',
      '频率',
    ])) {
      return AppErrorInfo(
        category: AppErrorCategory.quota,
        title: prefix.isEmpty ? 'API 余额或限额不足' : prefix,
        message: value.contains('429') || value.contains('rate')
            ? '调用过于频繁或供应商并发额度已满。'
            : '账户余额不足、额度用尽或供应商拒绝计费。',
        suggestion: '请稍后重试并检查中转账户余额、并发数和模型调用权限。',
        canOpenApiSettings: true,
      );
    }
    if (_containsAny(value, const [
      '404',
      'model_not_found',
      'model not found',
      'unknown model',
      '模型不存在',
    ])) {
      return AppErrorInfo(
        category: AppErrorCategory.configuration,
        title: prefix.isEmpty ? '接口或模型不存在' : prefix,
        message: raw.isEmpty ? '中转地址路径不兼容，或填写的模型标识不在该账户可用列表中。' : raw,
        suggestion: '请根据上方具体端点和上游提示检查地址、模型 ID 与账户能力。',
        canOpenApiSettings: true,
      );
    }
    if (_containsAny(value, const [
      '500',
      '502',
      '503',
      '504',
      'bad gateway',
      'service unavailable',
      'temporarily unavailable',
      '服务端',
    ])) {
      return AppErrorInfo(
        category: AppErrorCategory.server,
        title: prefix.isEmpty ? 'AI 服务暂时异常' : prefix,
        message: raw.isEmpty ? '中转或上游模型服务返回服务器错误。' : raw,
        suggestion: '稍后重试；若持续发生，请在 API 设置中切换模型或中转地址。',
        canOpenApiSettings: true,
      );
    }
    if (error is FileSystemException || value.contains('no space left')) {
      return AppErrorInfo(
        category: AppErrorCategory.storage,
        title: prefix.isEmpty ? '本地存储失败' : prefix,
        message: value.contains('no space left') ? '设备存储空间不足。' : raw,
        suggestion: '请释放存储空间并确认文件仍存在，然后重试。',
      );
    }
    if (_containsAny(value, const ['permission', 'denied', '权限', '拒绝访问'])) {
      return AppErrorInfo(
        category: AppErrorCategory.permission,
        title: prefix.isEmpty ? '缺少系统权限' : prefix,
        message: '系统没有授予完成此操作所需的相册、文件或网络权限。',
        suggestion: '请到系统应用设置中允许相关权限后重试。',
      );
    }
    if (error is FormatException ||
        value.contains('无法解析') ||
        value.contains('invalid json')) {
      return AppErrorInfo(
        category: AppErrorCategory.response,
        title: prefix.isEmpty ? '返回数据格式异常' : prefix,
        message: raw,
        suggestion: '该中转返回格式与所选协议不一致，请检查 API 协议和接口地址。',
        canOpenApiSettings: true,
      );
    }
    if (_containsAny(value, const ['cancelled', 'canceled', '已取消', '已停止'])) {
      return AppErrorInfo(
        category: AppErrorCategory.cancelled,
        title: '操作已取消',
        message: raw,
        suggestion: '没有产生新的结果，可随时重新操作。',
      );
    }
    if (_containsAny(value, const ['请先', '尚未配置', '地址格式', '必须使用 https'])) {
      return AppErrorInfo(
        category: AppErrorCategory.configuration,
        title: prefix.isEmpty ? '配置不完整' : prefix,
        message: raw,
        suggestion: '请前往 API 设置补全地址、密钥和模型，并运行连接测试。',
        canOpenApiSettings: true,
      );
    }
    return AppErrorInfo(
      category: AppErrorCategory.unknown,
      title: prefix.isEmpty ? '程序遇到异常' : prefix,
      message: raw.isEmpty ? '未知错误' : raw,
      suggestion: '请保留当前数据后重试；若持续发生，可将此完整提示反馈给作者。',
    );
  }

  static bool _containsAny(String value, List<String> needles) =>
      needles.any(value.contains);

  static String _clean(String value) => value
      .replaceFirst(
        RegExp(r'^(Exception|StateError|HttpException|Bad state):\s*'),
        '',
      )
      .trim();
}
