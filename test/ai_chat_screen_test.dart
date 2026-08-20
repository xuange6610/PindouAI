import 'dart:async';
import 'dart:io';

import 'package:bead_ai_designer/screens/ai_chat_screen.dart';
import 'package:bead_ai_designer/models/bead_pattern.dart';
import 'package:bead_ai_designer/services/ai_chat_service.dart';
import 'package:bead_ai_designer/services/ai_chat_store.dart';
import 'package:bead_ai_designer/services/app_settings.dart';
import 'package:bead_ai_designer/services/project_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('连续触发发送只会写入并请求一次相同问题', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/chat_screen_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    await tester.runAsync(() async {
      await AppSettings.instance.initialize();
      await AppSettings.instance.setAiModels('gpt-5.6-sol');
    });
    final service = _CountingChatService();
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(home: AiChatScreen(service: service)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '同一个问题');
    expect(tester.widget<TextField>(composer).controller?.text, '同一个问题');
    expect(service.loadCount, greaterThan(0));
    expect(find.text('gpt-5.6-sol'), findsWidgets);
    expect(AppSettings.instance.aiChatModel, 'gpt-5.6-sol');
    final sendButton = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .singleWhere((button) => button.tooltip == '发送');
    sendButton.onPressed!();
    sendButton.onPressed!();
    await tester.pump();
    for (var index = 0; index < 6; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(service.sendCount, 1);
    expect(find.text('同一个问题'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() async {
      for (
        var attempt = 0;
        attempt < 5 && await documents.exists();
        attempt++
      ) {
        try {
          await documents.delete(recursive: true);
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
  });

  testWidgets('聊天消息与历史列表显示提问时间和模型答复时间', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/chat_times_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    final askedAt = DateTime(2026, 8, 2, 9, 10, 11);
    final answeredAt = DateTime(2026, 8, 2, 9, 10, 15);
    await tester.runAsync(() async {
      await AppSettings.instance.setAiModels('gpt-5.6-sol');
      await AiChatStore().save(
        AiChatConversation(
          id: 'time_conversation',
          title: '时间记录测试',
          model: 'gpt-5.6-sol',
          createdAt: askedAt,
          updatedAt: answeredAt,
          messages: [
            AiChatMessage(
              id: 'time_question',
              role: 'user',
              content: '几点提问？',
              createdAt: askedAt,
            ),
            AiChatMessage(
              id: 'time_answer',
              role: 'assistant',
              content: '这是带时间的回答。',
              createdAt: answeredAt,
              model: 'gpt-5.6-sol',
            ),
          ],
        ),
      );
    });

    await tester.pumpWidget(
      MaterialApp(home: AiChatScreen(service: _CountingChatService())),
    );
    for (var index = 0; index < 20; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 30));
      if (find
          .byKey(const ValueKey('chatMessageTime_time_answer'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    expect(find.text('提问时间：2026-08-02 09:10:11'), findsOneWidget);
    expect(find.text('模型答复时间：2026-08-02 09:10:15'), findsOneWidget);
    await tester.tap(find.byTooltip('聊天历史'));
    await tester.pumpAndSettle();
    expect(find.textContaining('提问 2026-08-02 09:10:11'), findsOneWidget);
    expect(find.textContaining('答复 2026-08-02 09:10:15'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() async {
      if (await documents.exists()) await documents.delete(recursive: true);
    });
  });

  testWidgets('对话超时会询问是否用原问题重新提问', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/chat_timeout_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    await tester.runAsync(() => AppSettings.instance.setAiModels('qwen-max'));
    final service = _TimeoutChatService();
    await tester.pumpWidget(
      MaterialApp(
        home: AiChatScreen(
          service: service,
          requestTimeout: const Duration(milliseconds: 200),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '超时问题');
    final sendButton = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .singleWhere((button) => button.tooltip == '发送');
    sendButton.onPressed!();
    for (var index = 0; index < 6 && service.sendCount == 0; index++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    expect(service.sendCount, 1);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(find.text('AI 响应超时'), findsOneWidget);
    expect(find.textContaining('是否使用刚才的原问题重新发起提问'), findsOneWidget);
    await tester.tap(find.text('暂不重试'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() async {
      for (
        var attempt = 0;
        attempt < 5 && await documents.exists();
        attempt++
      ) {
        try {
          await documents.delete(recursive: true);
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
  });

  testWidgets('历史用户问题可按原内容、原模型和原模式重新发送', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/chat_resend_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    await tester.runAsync(() async {
      await AppSettings.instance.setAiModels('gpt-5.6-sol');
      final now = DateTime.now();
      await AiChatStore().save(
        AiChatConversation(
          id: 'resend_conversation',
          title: '重新发送测试',
          model: 'qwen-max',
          createdAt: now,
          updatedAt: now,
          messages: [
            AiChatMessage(
              id: 'original_question',
              role: 'user',
              content: '请原样再问一次',
              createdAt: now,
              model: 'qwen-max',
              requestMode: 'chat',
            ),
          ],
        ),
      );
    });
    final service = _CountingChatService();
    await tester.pumpWidget(MaterialApp(home: AiChatScreen(service: service)));
    for (var index = 0; index < 20; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 30));
      if (find
          .byKey(const ValueKey('resendChatMessage_original_question'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    await tester.tap(
      find.byKey(const ValueKey('resendChatMessage_original_question')),
    );
    for (var index = 0; index < 12 && service.sendCount == 0; index++) {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    expect(service.sendCount, 1);
    expect(service.lastModel, 'qwen-max');
    expect(
      service.lastMessages
          .where(
            (message) => message.role == 'user' && message.content == '请原样再问一次',
          )
          .length,
      2,
    );
    List<AiChatConversation> storedConversations = const [];
    for (var index = 0; index < 10; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      storedConversations =
          (await tester.runAsync(() => AiChatStore().load())) ?? const [];
      if (storedConversations.isNotEmpty &&
          storedConversations.single.messages.length >= 3) {
        break;
      }
    }
    final stored = storedConversations.single;
    final resent = stored.messages
        .where((message) => message.role == 'user')
        .last;
    expect(resent.model, 'qwen-max');
    expect(resent.requestMode, 'chat');

    await tester.pumpWidget(const SizedBox.shrink());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() async {
      for (
        var attempt = 0;
        attempt < 5 && await documents.exists();
        attempt++
      ) {
        try {
          await documents.delete(recursive: true);
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
  });

  testWidgets('聊天历史可按图片、文件、视频和音频类型筛选', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/chat_filter_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    await tester.runAsync(() async {
      final store = AiChatStore();
      final now = DateTime.now();
      for (final item in const [
        ('图片会话', 'image/png'),
        ('文件会话', 'application/pdf'),
        ('视频会话', 'video/mp4'),
        ('音频会话', 'audio/mpeg'),
      ]) {
        await store.save(
          AiChatConversation(
            id: item.$1,
            title: item.$1,
            model: 'gpt-5.6-sol',
            createdAt: now,
            updatedAt: now.add(Duration(seconds: item.$1.length)),
            messages: [
              AiChatMessage(
                id: '${item.$1}_message',
                role: 'user',
                content: '附件',
                createdAt: now,
                attachment: AiChatAttachment(
                  path: '${documents.path}/${item.$1}',
                  name: item.$1,
                  mimeType: item.$2,
                  bytes: 10,
                ),
              ),
            ],
          ),
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(home: AiChatScreen(service: _CountingChatService())),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('聊天历史'));
    await tester.pumpAndSettle();
    for (var index = 0; index < 15; index++) {
      if (find.text('音频会话').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('音频会话'), findsWidgets);
    final audioFilter = find.byKey(const ValueKey('chatHistoryFilter_audio'));
    await tester.ensureVisible(audioFilter);
    await tester.pumpAndSettle();
    await tester.tap(audioFilter);
    await tester.pumpAndSettle();
    expect(find.text('音频会话'), findsWidgets);
    expect(find.text('图片会话'), findsNothing);
    expect(find.text('视频会话'), findsNothing);
    expect(find.text('文件会话'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() async {
      if (await documents.exists()) await documents.delete(recursive: true);
    });
  });

  testWidgets('发送新问题后长聊天会稳定滚到底部且 AI 图片显示作品与收藏按钮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/chat_scroll_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    await tester.runAsync(
      () => AppSettings.instance.setAiModels('gpt-5.6-sol'),
    );
    final image = File('${documents.path}${Platform.pathSeparator}answer.png');
    await tester.runAsync(
      () => image.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10]),
    );
    final now = DateTime.now();
    final messages = <AiChatMessage>[
      for (var index = 0; index < 24; index++)
        AiChatMessage(
          id: 'history_$index',
          role: index.isEven ? 'user' : 'assistant',
          content: '历史长消息 $index\n这是用于验证滚动位置的多行内容。\n请保持消息列表足够长。',
          createdAt: now.add(Duration(seconds: index)),
          model: index.isOdd ? 'gpt-5.6-sol' : null,
        ),
      AiChatMessage(
        id: 'generated_image',
        role: 'assistant',
        content: '图片已生成',
        createdAt: now.add(const Duration(minutes: 1)),
        model: 'gpt-5.6-sol',
        attachment: AiChatAttachment(
          path: image.path,
          name: 'answer.png',
          mimeType: 'image/png',
          bytes: 8,
        ),
      ),
    ];
    await tester.runAsync(
      () => AiChatStore().save(
        AiChatConversation(
          id: 'scroll_test',
          title: '滚动测试',
          model: 'gpt-5.6-sol',
          createdAt: now,
          updatedAt: now,
          messages: messages,
        ),
      ),
    );
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    final service = _CountingChatService();
    await tester.pumpWidget(MaterialApp(home: AiChatScreen(service: service)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    for (var index = 0; index < 30; index++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      final listFinder = find.byKey(const ValueKey('aiChatMessageList'));
      if (listFinder.evaluate().isNotEmpty &&
          tester
                  .widget<ListView>(listFinder)
                  .controller!
                  .position
                  .maxScrollExtent >
              0) {
        break;
      }
    }
    final initialChatList = tester.widget<ListView>(
      find.byKey(const ValueKey('aiChatMessageList')),
    );
    expect(
      initialChatList.controller?.position.maxScrollExtent,
      greaterThan(0),
    );
    await tester.enterText(find.byType(TextField).last, '新的问题');
    final sendButton = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .singleWhere((button) => button.tooltip == '发送');
    expect(sendButton.onPressed, isNotNull);
    sendButton.onPressed!();
    for (var index = 0; index < 20 && service.sendCount == 0; index++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    for (var index = 0; index < 6; index++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    final chatList = tester.widget<ListView>(
      find.byKey(const ValueKey('aiChatMessageList')),
    );
    expect(service.sendCount, 1);
    expect(chatList.controller?.position.maxScrollExtent, greaterThan(0));
    expect(chatList.controller?.position.extentAfter, lessThanOrEqualTo(1));
    expect(
      find.byKey(const ValueKey('saveAiImageToWorks_generated_image')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('favoriteAiImage_generated_image')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() async {
      for (
        var attempt = 0;
        attempt < 5 && await documents.exists();
        attempt++
      ) {
        try {
          await documents.delete(recursive: true);
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
  });

  testWidgets('AI 图片的作品与收藏按钮直接保存原始照片并立即通知刷新', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/chat_photo_save_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    final image = img.Image(width: 13, height: 9);
    img.fill(image, color: img.ColorRgb8(25, 130, 220));
    final original = img.encodePng(image);
    final imageFile = File(
      '${documents.path}${Platform.pathSeparator}generated.png',
    );
    await tester.runAsync(() => imageFile.writeAsBytes(original));
    await tester.runAsync(() async {
      final now = DateTime.now();
      await AiChatStore().save(
        AiChatConversation(
          id: 'photo_save_conversation',
          title: '图片保存',
          model: 'gpt-5.6-sol',
          createdAt: now,
          updatedAt: now,
          messages: [
            AiChatMessage(
              id: 'photo_answer',
              role: 'assistant',
              content: '图片已生成',
              createdAt: now,
              model: 'gpt-5.6-sol',
              attachment: AiChatAttachment(
                path: imageFile.path,
                name: 'generated.png',
                mimeType: 'image/png',
                bytes: original.length,
              ),
            ),
          ],
        ),
      );
      await ProjectRepository().savePhotoProject(
        original,
        title: 'generated',
        sourceName: 'AI聊天/generated.png',
      );
    });
    var refreshCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AiChatScreen(
          service: _CountingChatService(),
          onProjectsChanged: () {
            refreshCount++;
            return Future<void>.value();
          },
        ),
      ),
    );
    final saveButton = find.byKey(
      const ValueKey('saveAiImageToWorks_photo_answer'),
    );
    for (var index = 0; index < 20 && saveButton.evaluate().isEmpty; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.tap(saveButton);
    for (var index = 0; index < 30 && refreshCount < 1; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    final summaries =
        (await tester.runAsync(() => ProjectRepository().loadSummaries())) ??
        const <ProjectSummary>[];
    expect(summaries.single.isPhotoProject, isTrue);
    final stored = await tester.runAsync(
      () => ProjectRepository().load(summaries.single.id),
    );
    expect(stored?.sourceBytes, orderedEquals(original));
    expect(refreshCount, 1);

    await tester.tap(
      find.byKey(const ValueKey('favoriteAiImage_photo_answer')),
    );
    for (var index = 0; index < 30 && refreshCount < 2; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    final favoriteSummaries =
        (await tester.runAsync(() => ProjectRepository().loadSummaries())) ??
        const <ProjectSummary>[];
    expect(favoriteSummaries.single.isFavorite, isTrue);
    expect(refreshCount, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() async {
      for (
        var attempt = 0;
        attempt < 5 && await documents.exists();
        attempt++
      ) {
        try {
          await documents.delete(recursive: true);
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
  });

  testWidgets('AI 聊天顶部操作在 360 宽窄屏不溢出并保留全部入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/chat_narrow_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    await tester.runAsync(() => AppSettings.instance.setAiModels('qwen-max'));
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(home: AiChatScreen(service: _CountingChatService())),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();

    expect(find.byTooltip('余额与消耗统计'), findsOneWidget);
    expect(find.byTooltip('一键清空当前聊天'), findsOneWidget);
    expect(find.byTooltip('聊天历史'), findsOneWidget);
    expect(find.byTooltip('更多聊天操作'), findsOneWidget);
    await tester.tap(find.byTooltip('更多聊天操作'));
    await tester.pumpAndSettle();
    expect(find.text('分享界面或聊天记录'), findsOneWidget);
    expect(find.text('新聊天'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() async {
      if (await documents.exists()) await documents.delete(recursive: true);
    });
  });

  testWidgets('目录缺少当前模型时采用 API 推荐项，手动切换会立即同步三个设置', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel(
      'com.xuan.bead_ai_designer/secure_settings',
    );
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/chat_model_sync_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    await tester.runAsync(
      () => AppSettings.instance.setAiModels('gpt-5.6-sol'),
    );

    await tester.pumpWidget(
      MaterialApp(home: AiChatScreen(service: _CatalogChatService())),
    );
    for (var index = 0; index < 20; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 40));
      if (find
              .byKey(const ValueKey('aiChatModelSelector'))
              .evaluate()
              .isNotEmpty &&
          AppSettings.instance.aiChatModel == 'qwen-max') {
        break;
      }
    }

    expect(AppSettings.instance.aiChatModel, 'qwen-max');
    expect(AppSettings.instance.aiImageModel, 'qwen-max');
    expect(AppSettings.instance.aiVideoModel, 'qwen-max');
    expect(find.text('qwen-max'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('aiChatModelSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('glm-5.2').last);
    await tester.pumpAndSettle();

    expect(AppSettings.instance.aiChatModel, 'glm-5.2');
    expect(AppSettings.instance.aiImageModel, 'glm-5.2');
    expect(AppSettings.instance.aiVideoModel, 'glm-5.2');

    await tester.pumpWidget(const SizedBox.shrink());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() async {
      for (
        var attempt = 0;
        attempt < 5 && await documents.exists();
        attempt++
      ) {
        try {
          await documents.delete(recursive: true);
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
  });
}

class _CountingChatService extends AiChatService {
  var loadCount = 0;
  var sendCount = 0;
  var lastMessages = <AiChatMessage>[];
  String? lastModel;

  @override
  Future<AiModelCatalog> loadCatalog() async {
    loadCount++;
    return const AiModelCatalog(
      models: ['gpt-5.6-sol', 'gpt-6.0-sol', 'qwen-max'],
      activeModel: 'gpt-6.0-sol',
    );
  }

  @override
  Future<AiChatReply> send({
    required String model,
    required List<AiChatMessage> messages,
    AiChatCancelToken? cancelToken,
    void Function(String delta)? onDelta,
    void Function(String delta)? onReasoningDelta,
  }) async {
    sendCount++;
    lastModel = model;
    lastMessages = List<AiChatMessage>.from(messages);
    cancelToken?.throwIfCancelled();
    onDelta?.call('只回答一次');
    return AiChatReply(model: model, content: '只回答一次');
  }
}

class _TimeoutChatService extends AiChatService {
  var sendCount = 0;

  @override
  Future<AiModelCatalog> loadCatalog() async =>
      const AiModelCatalog(models: ['qwen-max'], activeModel: 'qwen-max');

  @override
  Future<AiChatReply> send({
    required String model,
    required List<AiChatMessage> messages,
    AiChatCancelToken? cancelToken,
    void Function(String delta)? onDelta,
    void Function(String delta)? onReasoningDelta,
  }) {
    sendCount++;
    return Completer<AiChatReply>().future;
  }
}

class _CatalogChatService extends AiChatService {
  @override
  Future<AiModelCatalog> loadCatalog() async => const AiModelCatalog(
    models: ['qwen-turbo', 'qwen-max', 'glm-5.2'],
    activeModel: 'glm-5.2',
  );
}
