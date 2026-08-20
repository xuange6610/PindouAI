import 'package:flutter/material.dart';

import '../models/bead_pattern.dart';
import '../services/app_notice_center.dart';
import '../services/export_service.dart';

class PhotoProjectScreen extends StatelessWidget {
  const PhotoProjectScreen({super.key, required this.project});

  final BeadPattern project;

  Future<void> _saveOriginal(BuildContext context) async {
    try {
      final path = await ExportService().saveOriginal(project);
      if (!context.mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('原图已保存到本地：$path')),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      AppNoticeCenter.instance.showSnackBar(
        SnackBar(content: Text('保存原图失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF171717),
    appBar: AppBar(
      title: Text(project.title),
      foregroundColor: Colors.white,
      backgroundColor: const Color(0xFF171717),
      surfaceTintColor: Colors.transparent,
      actions: [
        IconButton(
          onPressed: () => _saveOriginal(context),
          tooltip: '保存原图到本地',
          icon: const Icon(Icons.download_rounded),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 8,
        boundaryMargin: const EdgeInsets.all(80),
        child: Center(
          child: Image.memory(
            project.sourceBytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white,
                  size: 48,
                ),
                SizedBox(height: 12),
                Text('原图文件已损坏', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
