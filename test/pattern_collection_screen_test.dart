import 'dart:io';

import 'package:bead_ai_designer/screens/pattern_collection_screen.dart';
import 'package:bead_ai_designer/services/collection_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('合集分类不再显示三点排序并可通过长按选择排到首尾', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/collection_screen_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );

    await tester.pumpWidget(const MaterialApp(home: PatternCollectionScreen()));
    Finder? chip;
    for (var index = 0; index < 40; index++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      final categories = CollectionLibrary.instance.categoryOrder;
      if (categories.isEmpty) continue;
      final candidate = find.byKey(
        ValueKey('collectionCategory_${categories.first}'),
      );
      if (candidate.evaluate().isNotEmpty) {
        chip = candidate;
        break;
      }
    }
    final category = CollectionLibrary.instance.categoryOrder.first;
    chip ??= find.byKey(ValueKey('collectionCategory_$category'));
    expect(chip, findsOneWidget);
    expect(find.byTooltip('分类排序'), findsNothing);

    await tester.longPress(chip);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('一键排到最前'), findsOneWidget);
    expect(find.text('一键排到最后'), findsOneWidget);

    Navigator.of(tester.element(find.text('一键排到最后'))).pop();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('resetPatternCollectionButton')),
      findsOneWidget,
    );
    await tester.longPress(find.byType(CollectionPatternCard).first);
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.textContaining('从合集删除'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() async {
      if (await documents.exists()) await documents.delete(recursive: true);
    });
  });
}
