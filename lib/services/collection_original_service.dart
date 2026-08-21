import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'app_settings.dart';

class CollectionOriginalService {
  const CollectionOriginalService();

  static const _bundledOriginalRoot = '爆款拼豆高清图纸电子素材创意手工个性DIY像素画图纸';

  static const _mediaChannel = MethodChannel('com.xuan.bead_ai_designer/media');

  Future<Uint8List> fetch(String relativePath, {String? baseUrl}) async {
    final localRoot = const String.fromEnvironment('COLLECTION_SOURCE_DIR');
    if (localRoot.isNotEmpty) {
      final normalized = relativePath.replaceAll('/', Platform.pathSeparator);
      final file = File('$localRoot${Platform.pathSeparator}$normalized');
      if (await file.exists()) return file.readAsBytes();
    }
    if (Platform.isWindows) {
      final normalized = relativePath.replaceAll('/', Platform.pathSeparator);
      final executableDir = File(Platform.resolvedExecutable).parent.path;
      final file = File(
        '$executableDir${Platform.pathSeparator}artwork'
        '${Platform.pathSeparator}$normalized',
      );
      if (await file.exists()) return file.readAsBytes();
    }
    final bundledPath =
        '$_bundledOriginalRoot/${relativePath.replaceAll('\\', '/')}';
    try {
      final data = await rootBundle.load(bundledPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (_isLikelyImage(bytes)) return bytes;
    } on Object {
      // Lightweight builds can omit the full artwork library.
    }
    if (Platform.isAndroid) {
      try {
        final bytes = await _mediaChannel.invokeMethod<Uint8List>(
          'readBundledOriginal',
          {'path': relativePath.replaceAll('\\', '/')},
        );
        if (bytes != null && _isLikelyImage(bytes)) return bytes;
      } on PlatformException {
        // Lightweight builds may omit the full offline asset pack. In that
        // case the configured collection server remains a valid fallback.
      } on MissingPluginException {
        // Widget tests and non-Android hosts do not install the native channel.
      }
    }
    final configured = (baseUrl ?? AppSettings.instance.collectionBaseUrl)
        .trim();
    if (configured.isEmpty) {
      throw StateError('离线原图库不可用，请配置原图库服务地址');
    }
    final endpoints = _candidateEndpoints(configured, relativePath);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 30);
    try {
      Object? lastError;
      for (final endpoint in endpoints) {
        try {
          final request = await client.getUrl(endpoint);
          request.headers.set(HttpHeaders.acceptHeader, 'image/*,*/*;q=0.8');
          final response = await request.close();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            final message = await utf8.decoder.bind(response).join();
            lastError = HttpException(
              response.statusCode == 404
                  ? '地址中没有找到该原图'
                  : '原图库服务返回 ${response.statusCode}：$message',
              uri: endpoint,
            );
            continue;
          }
          final builder = BytesBuilder(copy: false);
          await for (final chunk in response) {
            builder.add(chunk);
          }
          final bytes = builder.takeBytes();
          if (bytes.isEmpty) {
            lastError = HttpException('原图库返回了空文件', uri: endpoint);
            continue;
          }
          if (!_isLikelyImage(bytes)) {
            lastError = HttpException('原图库返回的不是图片文件，请检查地址或访问权限', uri: endpoint);
            continue;
          }
          return bytes;
        } on Object catch (error) {
          lastError = error;
        }
      }
      throw StateError('无法从已配置的地址读取原图：${lastError ?? '未知错误'}');
    } finally {
      client.close(force: true);
    }
  }

  static bool _isLikelyImage(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final png =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final jpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    final gif =
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38;
    final webp =
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    final bmp = bytes[0] == 0x42 && bytes[1] == 0x4D;
    final tiff =
        (bytes[0] == 0x49 && bytes[1] == 0x49) ||
        (bytes[0] == 0x4D && bytes[1] == 0x4D);
    final isoBrand =
        bytes.length >= 12 &&
            bytes[4] == 0x66 &&
            bytes[5] == 0x74 &&
            bytes[6] == 0x79 &&
            bytes[7] == 0x70
        ? String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase()
        : '';
    final heif = const {
      'heic',
      'heix',
      'hevc',
      'hevx',
      'mif1',
      'msf1',
      'avif',
    }.contains(isoBrand);
    return png || jpeg || gif || webp || bmp || tiff || heif;
  }

  List<Uri> _candidateEndpoints(String baseUrl, String relativePath) {
    final base = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final baseUri = Uri.parse(base);
    final result = <Uri>[];

    void add(Uri value) {
      if (!result.contains(value)) result.add(value);
    }

    if (base.contains('{path}')) {
      add(
        Uri.parse(base.replaceAll('{path}', Uri.encodeComponent(relativePath))),
      );
      return result;
    }

    Uri apiEndpoint(String prefix) => Uri.parse(
      '$base$prefix',
    ).replace(queryParameters: {'path': relativePath});

    if (baseUri.path.endsWith('/collection/file')) {
      add(Uri.parse(base).replace(queryParameters: {'path': relativePath}));
    } else if (baseUri.path.endsWith('/v1')) {
      add(apiEndpoint('/collection/file'));
    } else if (baseUri.path.endsWith('/collection')) {
      add(apiEndpoint('/file'));
    } else {
      add(apiEndpoint('/v1/collection/file'));
      add(apiEndpoint('/collection/file'));
    }

    final encodedSegments = relativePath
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    add(Uri.parse('$base/$encodedSegments'));
    return result;
  }
}
