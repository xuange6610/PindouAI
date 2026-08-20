import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:bead_ai_designer/screens/ai_design_screen.dart';
import 'package:bead_ai_designer/services/ai_design_service.dart';
import 'package:bead_ai_designer/services/ai_design_task_center.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AI 拼豆图纸展示四种风格、上传入口和历史入口', (tester) async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/ai_design_screen_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(const MaterialApp(home: AiDesignScreen()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();

    for (final id in const ['refined', 'anime', 'chibi', 'farm_rpg']) {
      expect(find.byKey(ValueKey('aiDesignStyle_$id')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('aiDesignUploadImage')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('aiDesignGenerateButton')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('aiDesignHistoryButton')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('aiDesignTaskCenterButton')),
      findsOneWidget,
    );
    expect(find.text(AiDesignScreen.defaultAdditionalRequest), findsOneWidget);
    expect(find.text('4 个模式'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() => documents.delete(recursive: true));
  });

  testWidgets('原图库进入 AI 高保真复刻模式时保留参考图和修改入口', (tester) async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/ai_replication_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: AiDesignScreen(
          initialImage: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
          replicationMode: true,
          initialRequest: '只修改背景色',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('AI 一比一复刻与修改'), findsOneWidget);
    expect(find.textContaining('高保真复刻模式已开启'), findsOneWidget);
    expect(find.text('只修改背景色'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() => documents.delete(recursive: true));
  });

  testWidgets('点击生成会展示耗时提示和失败持续重试选项', (tester) async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/ai_notice_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: AiDesignScreen(
          initialImage: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        ),
      ),
    );
    await tester.pump();
    final generate = find.byKey(const ValueKey('aiDesignGenerateButton'));
    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pumpAndSettle();
    await tester.ensureVisible(generate);
    await tester.pumpAndSettle();
    await tester.tap(generate);
    await tester.pumpAndSettle();

    expect(find.text('温馨提示'), findsOneWidget);
    expect(find.textContaining('预计需要5-10分钟'), findsOneWidget);
    expect(find.text('如果生成失败，自动重新生成直到成功'), findsOneWidget);
    expect(find.text('放到任务中心'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() => documents.delete(recursive: true));
  });

  testWidgets('前台生成时锁定风格并在离页前弹出保护确认', (tester) async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final documents = Directory(
      '.dart_tool/ai_protection_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tester.runAsync(() => documents.create(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => documents.absolute.path,
        );
    final pending = Completer<AiImageResult>();
    final center = AiDesignTaskCenter(
      generator: ({required prompt, required imageBytes, required model}) =>
          pending.future,
    );
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: AiDesignScreen(
          initialImage: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
          taskCenter: center,
        ),
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aiDesignGenerateButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('当前页等待'));
    await tester.pump();
    expect(center.tasks.single.isActive, isTrue);

    await tester.drag(find.byType(ListView), const Offset(0, 1700));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('aiDesignStyle_anime')));
    await tester.pump();
    expect(find.textContaining('当前选择：精致像素风'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('图片仍在生成'), findsOneWidget);
    expect(find.text('放到任务中心并退出'), findsOneWidget);
    await tester.tap(find.text('继续等待'));
    await tester.pump(const Duration(milliseconds: 300));

    center.cancel(center.tasks.single.id);
    await tester.pumpWidget(const SizedBox.shrink());
    center.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tester.runAsync(() => documents.delete(recursive: true));
  });
}
