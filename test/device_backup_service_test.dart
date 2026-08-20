import 'dart:convert';
import 'dart:io';

import 'package:bead_ai_designer/services/device_backup_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('自定义换机备份只导出勾选分区并始终排除密钥', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final directory = Directory(
      '.dart_tool/device_backup_${DateTime.now().microsecondsSinceEpoch}',
    );
    await directory.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => directory.absolute.path,
        );
    await File(
      '${directory.path}${Platform.pathSeparator}ai_chat_conversations.json',
    ).writeAsString('[]');
    await File(
      '${directory.path}${Platform.pathSeparator}ai_design_history.json',
    ).writeAsString('[]');
    final patterns = Directory(
      '${directory.path}${Platform.pathSeparator}patterns',
    );
    await patterns.create();
    await File(
      '${patterns.path}${Platform.pathSeparator}work.json',
    ).writeAsString('{}');
    SharedPreferences.setMockInitialValues({
      'ai_provider_chat_model': 'model-a',
      'appearance_click_sound': true,
      'ai_provider_api_key': 'must-never-export',
    });

    final backup = await const DeviceBackupService().createBackup(
      selection: const DeviceBackupSelection({DeviceBackupSection.aiHistory}),
    );
    final payload =
        jsonDecode(utf8.decode(gzip.decode(await backup.readAsBytes())))
            as Map<String, dynamic>;
    final paths = (payload['files'] as List)
        .map((value) => (value as Map)['path'])
        .toList();
    expect(
      paths,
      containsAll(['ai_chat_conversations.json', 'ai_design_history.json']),
    );
    expect(paths, isNot(contains('patterns/work.json')));
    final preferences = (payload['preferences'] as Map).cast<String, dynamic>();
    expect(preferences['ai_provider_chat_model'], 'model-a');
    expect(preferences, isNot(contains('appearance_click_sound')));
    expect(preferences.values, isNot(contains('must-never-export')));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await directory.delete(recursive: true);
  });
}
