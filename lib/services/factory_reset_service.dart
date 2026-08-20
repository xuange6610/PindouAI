import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_settings_store.dart';

class FactoryResetService {
  const FactoryResetService();

  Future<void> reset() async {
    // Each target is resolved by path_provider and only its children are
    // removed. The application-owned root directory itself is preserved.
    final directories = <Directory>[
      await getApplicationDocumentsDirectory(),
      await getApplicationSupportDirectory(),
      await getTemporaryDirectory(),
    ];
    final seen = <String>{};
    for (final directory in directories) {
      final absolute = directory.absolute.path;
      if (!seen.add(absolute) || !await directory.exists()) continue;
      await for (final entity in directory.list(followLinks: false)) {
        await entity.delete(recursive: true);
      }
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.clear();
    try {
      await const SecureSettingsStore().clearAll();
    } on Object {
      // Desktop/web test environments may not provide the Android channel.
      // The normal preference and application data reset still completes.
    }
  }
}
