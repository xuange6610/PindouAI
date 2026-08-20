import 'package:bead_ai_designer/screens/text_bead_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('文字拼豆提供三种布局和全屏编辑', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TextBeadScreen()));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('横向'), findsOneWidget);
    expect(find.text('竖向'), findsOneWidget);
    expect(find.text('四宫格'), findsOneWidget);

    await tester.tap(find.text('四宫格'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('全屏编辑'), findsOneWidget);
  });
}
