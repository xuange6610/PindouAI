import 'package:flutter/services.dart';

class SecureSettingsStore {
  const SecureSettingsStore();

  static const _channel = MethodChannel(
    'com.xuan.bead_ai_designer/secure_settings',
  );

  Future<String?> read(String key) =>
      _channel.invokeMethod<String>('read', {'key': key});

  Future<void> write(String key, String value) =>
      _channel.invokeMethod<void>('write', {'key': key, 'value': value});

  Future<void> delete(String key) =>
      _channel.invokeMethod<void>('delete', {'key': key});

  Future<void> clearAll() => _channel.invokeMethod<void>('clearAll');
}
