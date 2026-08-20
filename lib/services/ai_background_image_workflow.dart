import 'dart:typed_data';

import 'ai_design_service.dart';
import 'pattern_processor.dart';

typedef AiReferenceAnalyzer =
    Future<AiDesignResult> Function({
      required String prompt,
      required Uint8List imageBytes,
      required String model,
    });

typedef AiBackgroundImageGenerator =
    Future<AiImageResult> Function({
      required String prompt,
      required Uint8List? imageBytes,
      required String model,
    });

typedef LocalImageCutout = Future<Uint8List> Function(Uint8List imageBytes);
typedef AiBackgroundProgress = void Function(double progress, String phase);

class AiCutoutResult {
  const AiCutoutResult({
    required this.bytes,
    required this.usedAi,
    this.model,
    this.warning,
  });

  final Uint8List bytes;
  final bool usedAi;
  final String? model;
  final String? warning;
}

/// Shared non-UI workflow for features that need the same AI capabilities as
/// the chat screen. It keeps navigation out of background tasks and isolates
/// compatibility fallbacks in one place.
class AiBackgroundImageWorkflow {
  AiBackgroundImageWorkflow({
    AiReferenceAnalyzer? referenceAnalyzer,
    AiBackgroundImageGenerator? imageGenerator,
    LocalImageCutout? localCutout,
  }) : _referenceAnalyzer = referenceAnalyzer ?? _defaultReferenceAnalyzer,
       _imageGenerator = imageGenerator ?? _defaultImageGenerator,
       _localCutout = localCutout ?? PatternProcessor().smartCutout;

  static final instance = AiBackgroundImageWorkflow();

  final AiReferenceAnalyzer _referenceAnalyzer;
  final AiBackgroundImageGenerator _imageGenerator;
  final LocalImageCutout _localCutout;

  Future<AiImageResult> generateBeadDesign({
    required String prompt,
    required Uint8List referenceImage,
    required String imageModel,
    required String visionModel,
    AiBackgroundProgress? onProgress,
  }) async {
    Object? visionError;
    Object? textImageError;
    onProgress?.call(0.2, '后台调用 AI 对话模型识别参考图');
    try {
      final analysis = await _referenceAnalyzer(
        prompt: _referenceAnalysisPrompt,
        imageBytes: referenceImage,
        model: visionModel,
      );
      final description = analysis.content.trim();
      if (description.isEmpty) {
        throw const FormatException('AI 对话模型没有返回参考图描述');
      }
      onProgress?.call(0.46, '参考图识别完成，后台调用图片模型生成');
      try {
        return await _imageGenerator(
          prompt: '$prompt\n\n参考图视觉分析（必须据此还原主体）：\n$description',
          imageBytes: null,
          model: imageModel,
        );
      } on Object catch (error) {
        textImageError = error;
      }
    } on Object catch (error) {
      visionError = error;
    }

    // Some providers do implement image editing. Keep this as a final
    // compatibility route, but do not make every task depend on it.
    onProgress?.call(0.58, '对话识图链路不可用，尝试兼容图片编辑接口');
    try {
      return await _imageGenerator(
        prompt: prompt,
        imageBytes: referenceImage,
        model: imageModel,
      );
    } on Object catch (directError) {
      final details = <String>[
        if (visionError != null) '参考图识别失败：$visionError',
        if (textImageError != null) '文本生图失败：$textImageError',
        '图片编辑兼容路径失败：$directError',
      ].join('；');
      throw StateError('后台 AI 拼豆图生成失败：$details');
    }
  }

  Future<AiCutoutResult> cutout({
    required Uint8List sourceImage,
    required String imageModel,
    bool useAi = true,
    AiBackgroundProgress? onProgress,
  }) async {
    Object? aiError;
    if (useAi) {
      onProgress?.call(0.08, '后台调用 AI 图片模型识别并抠出主体');
      try {
        final generated = await _imageGenerator(
          prompt: _cutoutPrompt,
          imageBytes: sourceImage,
          model: imageModel,
        );
        onProgress?.call(0.32, 'AI 抠图完成，正在清理透明边缘');
        final cleaned = await _localCutout(generated.bytes);
        return AiCutoutResult(
          bytes: cleaned,
          usedAi: true,
          model: generated.model,
        );
      } on Object catch (error) {
        aiError = error;
      }
    }

    onProgress?.call(0.34, useAi ? 'AI 不可用，切换本地安全抠图' : '正在执行本地安全抠图');
    final cleaned = await _localCutout(sourceImage);
    return AiCutoutResult(
      bytes: cleaned,
      usedAi: false,
      warning: aiError == null ? null : 'AI 抠图失败，已切换本地抠图：$aiError',
    );
  }

  static Future<AiDesignResult> _defaultReferenceAnalyzer({
    required String prompt,
    required Uint8List imageBytes,
    required String model,
  }) => AiDesignService.instance.generate(
    prompt: prompt,
    imageBytes: imageBytes,
    model: model,
  );

  static Future<AiImageResult> _defaultImageGenerator({
    required String prompt,
    required Uint8List? imageBytes,
    required String model,
  }) => AiDesignService.instance.generateImage(
    prompt: prompt,
    imageBytes: imageBytes,
    model: model,
  );

  static const _referenceAnalysisPrompt =
      '请仔细识别参考图并输出可供另一个图片模型精确重建的中文视觉描述。'
      '必须包括主体身份、数量、姿态、轮廓、比例、颜色、纹理、构图、背景、光线和关键细节；'
      '不要回答与画面无关的内容，不要省略主体特征。';

  static const _cutoutPrompt =
      '精确抠出参考图片的主要主体，完全保持主体原貌、比例、颜色、纹理和边缘，'
      '删除所有背景并输出真正带透明通道的 PNG。禁止添加、重绘、替换或改变主体，'
      '禁止阴影、文字、边框和棋盘格背景。';
}
