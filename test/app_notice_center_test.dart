import 'package:bead_ai_designer/services/app_notice_center.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(AppNoticeCenter.instance.dismiss);

  testWidgets('旧页面提示通过全局通知宿主显示在界面上方', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppNoticeHost(child: Scaffold(body: SizedBox.expand())),
      ),
    );

    AppNoticeCenter.instance.showSnackBar(
      const SnackBar(content: Text('图片已保存')),
    );
    await tester.pump();

    final prompt = find.text('图片已保存');
    expect(prompt, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    final box = tester.renderObject<RenderBox>(prompt);
    expect(box.localToGlobal(Offset.zero).dy, lessThan(180));
    expect(AppNoticeCenter.instance.notice?.kind, AppNoticeKind.success);
  });

  test('旧错误提示保留操作按钮并正确标记为错误', () {
    var retried = false;
    AppNoticeCenter.instance.showSnackBar(
      SnackBar(
        content: const Text('网络导入失败：SocketException'),
        action: SnackBarAction(label: '重试', onPressed: () => retried = true),
      ),
    );

    final notice = AppNoticeCenter.instance.notice!;
    expect(notice.kind, AppNoticeKind.error);
    expect(notice.actionLabel, '重试');
    notice.onAction!();
    expect(retried, isTrue);
  });

  test('连接被系统中止会转换成简洁的网络错误而不是暴露整段异常', () {
    AppNoticeCenter.instance.showSnackBar(
      const SnackBar(
        content: Text(
          'AI 生图失败：Bad state: Images API 调用失败：'
          'HttpException: Software caused connection abort',
        ),
      ),
    );

    final notice = AppNoticeCenter.instance.notice!;
    expect(notice.kind, AppNoticeKind.error);
    expect(notice.message, contains('设备无法连接服务器'));
    expect(notice.message, isNot(contains('Software caused connection abort')));
  });

  testWidgets('长提示可以打开详情查看完整内容', (tester) async {
    const message =
        '这是一段需要完整保留的错误提示，用于说明服务地址、网络状态以及模型返回的具体情况。\n'
        '第二行仍然必须能够在详情窗口中完整查看和复制。';
    await tester.pumpWidget(
      const MaterialApp(
        home: AppNoticeHost(child: Scaffold(body: SizedBox.expand())),
      ),
    );

    AppNoticeCenter.instance.show(message, kind: AppNoticeKind.error);
    await tester.pump();

    expect(find.byKey(const ValueKey('noticeDetailsButton')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('noticeDetailsButton')));
    await tester.pumpAndSettle();

    expect(find.text('完整错误提示'), findsOneWidget);
    expect(find.text(message), findsWidgets);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byKey(const ValueKey('copyNoticeDetails')), findsOneWidget);
  });
}
