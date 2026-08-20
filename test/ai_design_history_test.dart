import 'dart:io';
import 'package:bead_ai_designer/services/ai_design_history.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AI 制图记录支持批量软删除、恢复和永久删除图片', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/ai_history_${DateTime.now().microsecondsSinceEpoch}',
    );
    await documents.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => documents.absolute.path,
        );
    final store = AiDesignHistoryStore();
    final first = await store.saveImage(
      AiDesignHistoryEntry(
        id: 'first',
        prompt: '第一张',
        content: '完成',
        model: 'image-model',
        createdAt: DateTime(2026),
      ),
      Uint8List.fromList(const [1, 2, 3]),
    );
    final second = await store.saveImage(
      AiDesignHistoryEntry(
        id: 'second',
        prompt: '第二张',
        content: '完成',
        model: 'image-model',
        createdAt: DateTime(2026, 1, 2),
        styleId: 'anime',
      ),
      Uint8List.fromList(const [4, 5, 6]),
    );

    await store.deleteMany([first.id, second.id]);
    final deleted = await store.load();
    expect(deleted.every((entry) => entry.isDeleted), isTrue);
    expect(
      deleted.firstWhere((entry) => entry.id == second.id).styleId,
      'anime',
    );
    await store.restore(first.id);
    expect(
      (await store.load())
          .firstWhere((entry) => entry.id == first.id)
          .isDeleted,
      isFalse,
    );

    await store.deletePermanently([second.id]);
    expect((await store.load()).map((entry) => entry.id), [first.id]);
    expect(await File(second.imagePath!).exists(), isFalse);
    expect(await File(first.imagePath!).exists(), isTrue);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await documents.delete(recursive: true);
  });
}
