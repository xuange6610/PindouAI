import 'package:bead_ai_designer/data/mard_palette.dart';
import 'package:bead_ai_designer/models/bead_pattern.dart';
import 'package:bead_ai_designer/screens/editor_screen.dart';
import 'package:bead_ai_designer/screens/manual_cutout_screen.dart';
import 'package:bead_ai_designer/screens/custom_board_screen.dart';
import 'package:bead_ai_designer/screens/result_screen.dart';
import 'package:bead_ai_designer/services/pattern_processor.dart';
import 'package:bead_ai_designer/theme/app_theme.dart';
import 'package:bead_ai_designer/widgets/bead_pattern_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('拼豆预览组件可以渲染', (tester) async {
    final pattern = BeadPattern(
      id: 'test',
      title: '测试作品',
      width: 2,
      height: 2,
      colors: [MardPalette.colors.first, MardPalette.colors.last],
      cells: const [0, 1, 1, 0],
      sourceBytes: Uint8List(0),
      createdAt: DateTime(2026),
      requestedColorCount: 2,
      portraitMode: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 200,
            child: BeadPatternView(pattern: pattern),
          ),
        ),
      ),
    );

    expect(find.byType(BeadPatternView), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      BeadPatternPainter(pattern).shouldRepaint(BeadPatternPainter(pattern)),
      isTrue,
      reason: '原地镜像、反转和去白底后必须立即重绘',
    );
  });

  testWidgets('200×200 大尺寸作品可用轻量总览渲染', (tester) async {
    final colors = [MardPalette.colors.first, MardPalette.colors.last];
    final pattern = BeadPattern(
      id: 'large-preview',
      title: '大尺寸预览',
      width: 200,
      height: 200,
      colors: colors,
      cells: List<int>.generate(40000, (index) => index & 1),
      sourceBytes: Uint8List(0),
      createdAt: DateTime(2026),
      requestedColorCount: 2,
      portraitMode: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 320,
            child: BeadPatternView(pattern: pattern, showCodes: true),
          ),
        ),
      ),
    );

    expect(find.byType(BeadPatternView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('结果页本地保存菜单提供原图、预览图、效果图和编号图', (tester) async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      (_) async => '.dart_tool/test_result_save_menu',
    );
    final source = img.Image(width: 2, height: 2);
    img.fill(source, color: img.ColorRgb8(240, 100, 80));
    final pattern = BeadPattern(
      id: 'save-menu-test',
      title: '保存菜单测试',
      width: 2,
      height: 2,
      colors: [MardPalette.colors.first, MardPalette.colors.last],
      cells: const [0, 1, 1, 0],
      sourceBytes: Uint8List.fromList(img.encodePng(source)),
      createdAt: DateTime(2026),
      requestedColorCount: 2,
      portraitMode: false,
    );

    await tester.pumpWidget(MaterialApp(home: ResultScreen(pattern: pattern)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('作品操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存图片到本地'));
    await tester.pumpAndSettle();

    expect(find.text('保存原图'), findsOneWidget);
    expect(find.text('保存预览图'), findsOneWidget);
    expect(find.text('保存效果预览图'), findsOneWidget);
    expect(find.text('保存带格子编号的图片'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      null,
    );
  });

  testWidgets('处理页可以完成生成并进入结果页', (tester) async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => '.dart_tool/test_documents',
    );
    final source = img.Image(width: 12, height: 12);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgba(x, y, x * 18, y * 18, 120, 255);
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ProcessingScreen(
          imageBytes: Uint8List.fromList(img.encodePng(source)),
          options: const ProcessingOptions(
            size: 20,
            maxColors: 8,
            portraitMode: false,
            smoothing: true,
          ),
        ),
      ),
    );
    for (var attempt = 0; attempt < 80; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('效果预览').evaluate().isNotEmpty) break;
    }

    expect(find.text('效果预览'), findsOneWidget);
    expect(find.text('生成效果预览'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('原图'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      null,
    );
  });

  testWidgets('编辑页支持自定义画板和确认裁剪', (tester) async {
    final source = img.Image(width: 120, height: 80);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x * 2, y * 3, 150);
      }
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EditorScreen(
          imageBytes: Uint8List.fromList(img.encodePng(source)),
          sourceName: 'crop-test.png',
        ),
      ),
    );

    final custom = find.text('自定义尺寸');
    await tester.scrollUntilVisible(
      custom,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(custom);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '37');
    await tester.enterText(fields.at(1), '23');
    await tester.tap(find.text('应用尺寸'));
    await tester.pumpAndSettle();
    expect(find.text('37 × 23'), findsOneWidget);

    final crop = find.text('移动 / 缩放 / 截取生成区域');
    await tester.scrollUntilVisible(
      crop,
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(crop);
    await tester.pump(const Duration(milliseconds: 400));
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 40));
      if (find.byType(RawImage).evaluate().isNotEmpty) break;
    }
    expect(find.text('使用这个裁剪结果'), findsOneWidget);
    await tester.tap(find.text('使用这个裁剪结果'));
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('使用这个裁剪结果').evaluate().isEmpty) break;
    }
    expect(find.text('生成拼豆图纸'), findsOneWidget);
    await tester.pumpAndSettle();
    final classicTemplate = find.text('经典标题');
    await tester.scrollUntilVisible(
      classicTemplate,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(classicTemplate);
    await tester.pumpAndSettle();
    await tester.tap(classicTemplate);
    await tester.pumpAndSettle();
    expect(find.text('所选模板大致效果'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量图片可切换逐张参数并左右滑动', (tester) async {
    final first = img.Image(width: 30, height: 20);
    final second = img.Image(width: 20, height: 30);
    img.fill(first, color: img.ColorRgb8(220, 80, 90));
    img.fill(second, color: img.ColorRgb8(60, 140, 220));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EditorScreen(
          imageBytes: Uint8List.fromList(img.encodePng(first)),
          sourceName: '第一张.png',
          batchImages: [
            EditorImageInput(
              bytes: Uint8List.fromList(img.encodePng(second)),
              name: '第二张.png',
            ),
          ],
        ),
      ),
    );
    expect(find.text('批量图片参数方式'), findsOneWidget);
    expect(find.text('全部同一参数'), findsOneWidget);
    await tester.tap(find.text('逐张设置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('左右滑动图片'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 张'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('一键智能抠图输出同时包含主体和透明背景的 PNG', (tester) async {
    final source = img.Image(width: 80, height: 80, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(248, 248, 248, 255));
    for (var y = 20; y < 60; y++) {
      for (var x = 20; x < 60; x++) {
        source.setPixelRgba(x, y, 220, 70, 90, 255);
      }
    }
    Uint8List? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<Uint8List>(
                    MaterialPageRoute(
                      builder: (_) => ManualCutoutScreen(
                        imageBytes: Uint8List.fromList(img.encodePng(source)),
                        sourceName: 'cutout.png',
                      ),
                    ),
                  );
                },
                child: const Text('打开抠图'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开抠图'));
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 40));
      if (find.text('一键智能抠出主体').evaluate().isNotEmpty) break;
    }
    expect(find.text('一键智能抠出主体'), findsOneWidget);
    await tester.tap(find.text('一键智能抠出主体'));
    for (var attempt = 0; attempt < 60; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 40));
      if (find.textContaining('已自动抠出主体').evaluate().isNotEmpty) break;
    }
    await tester.tap(find.text('仅用于生成'));
    for (var attempt = 0; attempt < 40 && result == null; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }

    expect(result, isNotNull);
    final output = img.decodePng(result!);
    expect(output, isNotNull);
    var transparent = 0;
    var opaque = 0;
    for (final pixel in output!) {
      if (pixel.a.toInt() == 0) transparent++;
      if (pixel.a.toInt() == 255) opaque++;
    }
    expect(transparent, greaterThan(1000));
    expect(opaque, greaterThan(1000));
  });

  testWidgets('自定义画板显示图标文字、长按说明和恢复白板确认', (tester) async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      (_) async => '.dart_tool/test_documents',
    );
    final pattern = BeadPattern(
      id: 'custom-toolbar',
      title: '工具栏测试',
      width: 15,
      height: 15,
      colors: [MardPalette.colors.first],
      cells: List<int>.generate(225, (index) => index < 3 ? 0 : -1),
      sourceBytes: Uint8List(0),
      createdAt: DateTime(2026),
      requestedColorCount: 1,
      portraitMode: false,
    );
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(
        home: CustomBoardScreen(embedded: true, initialPattern: pattern),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('自由创作'), findsOneWidget);
    expect(find.textContaining('单指画豆'), findsOneWidget);
    expect(find.text('画笔'), findsOneWidget);
    expect(find.text('橡皮'), findsOneWidget);
    expect(find.text('批量换色'), findsOneWidget);
    expect(find.text('尺寸'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('已用 1 色'), findsOneWidget);

    final canvas = find.byKey(const ValueKey('customBoardCanvasGesture'));
    final center = tester.getCenter(canvas);
    await tester.tapAt(center);
    await tester.pump();
    expect(find.textContaining('· 4 颗'), findsOneWidget);

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final beforeTransform = List<double>.from(
      viewer.transformationController!.value.storage,
    );
    final first = await tester.createGesture(pointer: 41);
    final second = await tester.createGesture(pointer: 42);
    await first.down(center - const Offset(24, 0));
    await second.down(center + const Offset(24, 0));
    await first.moveTo(center - const Offset(55, 16));
    await second.moveTo(center + const Offset(55, 16));
    await tester.pump();
    expect(
      viewer.transformationController!.value.storage,
      isNot(orderedEquals(beforeTransform)),
    );
    await second.up();
    await first.up();
    await tester.pump();

    await tester.tap(find.textContaining('× 3'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.textContaining('× 3'));
    await tester.pumpAndSettle();
    expect(find.text('批量替换色号'), findsOneWidget);
    expect(find.text('搜索当前启用色库中的目标色号'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('画笔'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.textContaining('按住并拖动'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(-1700, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('白板'));
    await tester.pumpAndSettle();
    expect(find.text('恢复出厂白板？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      null,
    );
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
