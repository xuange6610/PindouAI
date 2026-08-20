import 'package:bead_ai_designer/screens/ai_design_history_screen.dart';
import 'package:bead_ai_designer/services/ai_design_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AI 制图记录管理支持一键全选', (tester) async {
    final store = _MemoryHistoryStore([
      for (var index = 0; index < 2; index++)
        AiDesignHistoryEntry(
          id: '$index',
          prompt: '记录 $index',
          content: '完成',
          model: 'image-model',
          createdAt: DateTime(2026, 1, index + 1),
          styleId: 'refined',
        ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: AiDesignHistoryScreen(store: store)),
    );
    await tester.pump();
    expect(find.text('记录 0'), findsOneWidget);
    expect(find.text('记录 1'), findsOneWidget);
    await tester.tap(find.text('管理'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('aiHistorySelectAll')));
    await tester.pump();

    expect(find.text('已选择 2 项'), findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);
    expect(find.text('批量删除'), findsOneWidget);
    expect(find.text('永久删除'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _MemoryHistoryStore extends AiDesignHistoryStore {
  _MemoryHistoryStore(this.entries);

  final List<AiDesignHistoryEntry> entries;

  @override
  Future<List<AiDesignHistoryEntry>> load() async => List.from(entries);
}
