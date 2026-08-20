import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bead_ai_designer/services/ai_attachment_reader.dart';
import 'package:bead_ai_designer/services/ai_chat_service.dart';
import 'package:bead_ai_designer/services/ai_chat_store.dart';
import 'package:bead_ai_designer/services/ai_generated_artifact.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('可读取 DOCX 和 XLSX 内容供聊天模型分析', () async {
    final directory = await Directory.systemTemp.createTemp('ai_attachment_');
    addTearDown(() => directory.delete(recursive: true));

    final docxArchive = Archive()
      ..addFile(
        ArchiveFile.string(
          'word/document.xml',
          '<w:document><w:body><w:p><w:r><w:t>拼豆代码说明</w:t></w:r></w:p>'
              '<w:p><w:r><w:t>第二段</w:t></w:r></w:p></w:body></w:document>',
        ),
      );
    final docxBytes = ZipEncoder().encode(docxArchive);
    final docx = File('${directory.path}${Platform.pathSeparator}说明.docx');
    await docx.writeAsBytes(docxBytes);
    final docxText = await AiAttachmentReader.extractText(
      AiChatAttachment(
        path: docx.path,
        name: '说明.docx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        bytes: docxBytes.length,
      ),
    );
    expect(docxText, contains('拼豆代码说明'));
    expect(docxText, contains('第二段'));

    final xlsxArchive = Archive()
      ..addFile(
        ArchiveFile.string(
          'xl/sharedStrings.xml',
          '<sst><si><t>色号</t></si><si><t>MARD-A1</t></si></sst>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/worksheets/sheet1.xml',
          '<worksheet><sheetData><row><c t="s"><v>0</v></c>'
              '<c t="s"><v>1</v></c><c><v>36</v></c></row></sheetData></worksheet>',
        ),
      );
    final xlsxBytes = ZipEncoder().encode(xlsxArchive);
    final xlsx = File('${directory.path}${Platform.pathSeparator}色号.xlsx');
    await xlsx.writeAsBytes(xlsxBytes);
    final xlsxText = await AiAttachmentReader.extractText(
      AiChatAttachment(
        path: xlsx.path,
        name: '色号.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        bytes: xlsxBytes.length,
      ),
    );
    expect(xlsxText, contains('色号\tMARD-A1\t36'));
  });

  test('AI 代码块可解析成可预览下载的文件', () {
    const output = '''
下面是完整网页：
```html
filename: index.html
<html><body>拼豆 AI</body></html>
```
```css
filename: styles.css
body { color: red; }
```
''';
    final artifact = AiGeneratedArtifactParser.first(output);
    expect(artifact, isNotNull);
    expect(artifact!.name, 'index.html');
    expect(artifact.content, contains('<html>'));
    expect(artifact.bytes, isA<Uint8List>());
    expect(AiGeneratedArtifactParser.all(output).map((value) => value.name), [
      'index.html',
      'styles.css',
    ]);
  });

  test('聊天记录兼容备注、模型、Token 和耗时持久化', () {
    final conversation = AiChatConversation(
      id: 'chat-1',
      title: '代码修改',
      model: 'qwen-max',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      note: '客户网页',
      messages: [
        AiChatMessage(
          id: 'answer',
          role: 'assistant',
          content: '完成',
          createdAt: DateTime(2026),
          model: 'qwen-max',
          elapsedMs: 1250,
          inputTokens: 10,
          outputTokens: 20,
          totalTokens: 30,
        ),
      ],
    );
    final restored = AiChatConversation.fromJson(
      conversation.toJson().cast<String, dynamic>(),
    );
    expect(restored.note, '客户网页');
    expect(restored.messages.single.elapsedMs, 1250);
    expect(restored.messages.single.totalTokens, 30);
  });

  test('取消令牌能阻止已停止的请求继续连接', () {
    final token = AiChatCancelToken()..cancel();
    expect(token.isCancelled, isTrue);
    expect(
      () => token.attach(HttpClient()),
      throwsA(isA<AiChatCancelledException>()),
    );
  });

  test('聊天备份可连同附件、思考摘要和用量信息完整恢复', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final directory = Directory(
      '.dart_tool/chat_backup_${DateTime.now().microsecondsSinceEpoch}',
    );
    await directory.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => directory.absolute.path,
        );
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    final store = AiChatStore();
    final attachment = await store.saveAttachmentBytes(
      Uint8List.fromList(const [1, 3, 5, 7]),
      name: '说明.txt',
      mimeType: 'text/plain',
    );
    await store.save(
      AiChatConversation(
        id: 'backup-chat',
        title: '备份测试',
        model: 'claude-sonnet-4',
        createdAt: DateTime(2026, 7, 31),
        updatedAt: DateTime(2026, 7, 31),
        note: '保留备注',
        messages: [
          AiChatMessage(
            id: 'answer',
            role: 'assistant',
            content: '最终回答',
            createdAt: DateTime(2026, 7, 31),
            attachment: attachment,
            model: 'claude-sonnet-4',
            reasoning: '先分析',
            elapsedMs: 900,
            inputTokens: 8,
            outputTokens: 13,
            totalTokens: 21,
          ),
        ],
      ),
    );

    final backup = await store.createBackup();
    final bytes = await backup.readAsBytes();
    await store.delete('backup-chat');
    expect(await store.load(), isEmpty);
    expect(await store.importBackupBytes(bytes), 1);

    final restored = (await store.load()).single;
    expect(restored.note, '保留备注');
    expect(restored.messages.single.reasoning, '先分析');
    expect(restored.messages.single.totalTokens, 21);
    final restoredAttachment = restored.messages.single.attachment!;
    expect(await File(restoredAttachment.path).readAsBytes(), [1, 3, 5, 7]);
  });
}
