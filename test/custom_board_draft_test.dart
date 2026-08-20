import 'dart:io';

import 'package:bead_ai_designer/services/custom_board_draft.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('自定义画板草稿可以保存、恢复并恢复出厂清除', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/custom_board_draft_${DateTime.now().microsecondsSinceEpoch}',
    );
    await documents.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (call) async => documents.absolute.path,
        );
    final store = CustomBoardDraftStore();
    final updatedAt = DateTime(2026, 7, 31, 12, 30);
    await store.save(
      CustomBoardDraft(
        width: 15,
        height: 15,
        cells: List<int>.generate(225, (index) => index % 7 == 0 ? 3 : -1),
        title: '未完成草稿',
        selectedColor: 12,
        updatedAt: updatedAt,
      ),
    );

    final restored = await store.load();
    expect(restored?.width, 15);
    expect(restored?.height, 15);
    expect(restored?.cells.where((cell) => cell == 3), hasLength(33));
    expect(restored?.title, '未完成草稿');
    expect(restored?.selectedColor, 12);
    expect(restored?.updatedAt, updatedAt);

    final draft = restored!;
    await store.archive(draft, reason: '测试暂存');
    final trash = await store.loadTrash();
    expect(trash, hasLength(1));
    expect(trash.single.reason, '测试暂存');
    expect(trash.single.draft.cells, draft.cells);

    final transfer = await store.createTransferFile(draft);
    final imported = store.importBytes(await transfer.readAsBytes());
    expect(imported.width, draft.width);
    expect(imported.height, draft.height);
    expect(imported.title, draft.title);
    expect(imported.cells, draft.cells);

    await store.deleteTrash(trash.single.id);
    expect(await store.loadTrash(), isEmpty);
    await store.clear();
    expect(await store.load(), isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await documents.delete(recursive: true);
  });
}
