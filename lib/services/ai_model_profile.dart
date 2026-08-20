import 'ai_usage_store.dart';

enum AiModelProvider {
  openAi,
  anthropic,
  qwen,
  glm,
  kimi,
  deepSeek,
  gemini,
  llama,
  generic,
}

class AiModelRuntimeProfile {
  const AiModelRuntimeProfile({
    required this.provider,
    required this.label,
    required this.preferResponsesApi,
    required this.supportsVision,
    required this.supportsFileInput,
  });

  final AiModelProvider provider;
  final String label;
  final bool preferResponsesApi;
  final bool supportsVision;
  final bool supportsFileInput;

  String systemInstruction(String model) =>
      '你正在通过统一模型网关运行。当前请求使用的模型标识是“$model”，'
      '模型环境为“$label”。请准确遵循用户要求；当用户询问你是什么模型时，'
      '必须如实回答当前模型标识“$model”，不要自称为其他模型或其他提供商。';
}

AiModelRuntimeProfile runtimeProfileForModel(String model) {
  final value = model.trim().toLowerCase();
  if (value.startsWith('claude') || value.contains('anthropic')) {
    return AiModelRuntimeProfile(
      provider: AiModelProvider.anthropic,
      label: 'Anthropic Claude 兼容环境',
      preferResponsesApi: false,
      supportsVision: true,
      supportsFileInput: true,
    );
  }
  if (value.startsWith('qwen') || value.contains('tongyi')) {
    return AiModelRuntimeProfile(
      provider: AiModelProvider.qwen,
      label: '阿里云 Qwen 兼容环境',
      preferResponsesApi: false,
      supportsVision: value.contains('vl'),
      supportsFileInput: false,
    );
  }
  if (value.startsWith('glm') || value.contains('chatglm')) {
    return AiModelRuntimeProfile(
      provider: AiModelProvider.glm,
      label: '智谱 GLM 兼容环境',
      preferResponsesApi: false,
      supportsVision: value.contains('v'),
      supportsFileInput: false,
    );
  }
  if (value.startsWith('kimi') || value.contains('moonshot')) {
    return AiModelRuntimeProfile(
      provider: AiModelProvider.kimi,
      label: 'Moonshot Kimi 兼容环境',
      preferResponsesApi: false,
      supportsVision: value.contains('vision'),
      supportsFileInput: true,
    );
  }
  if (value.startsWith('deepseek')) {
    return const AiModelRuntimeProfile(
      provider: AiModelProvider.deepSeek,
      label: 'DeepSeek 兼容环境',
      preferResponsesApi: false,
      supportsVision: false,
      supportsFileInput: false,
    );
  }
  if (value.startsWith('gemini')) {
    return const AiModelRuntimeProfile(
      provider: AiModelProvider.gemini,
      label: 'Google Gemini 兼容环境',
      preferResponsesApi: false,
      supportsVision: true,
      supportsFileInput: true,
    );
  }
  if (value.contains('llama') || value.contains('ollama')) {
    return AiModelRuntimeProfile(
      provider: AiModelProvider.llama,
      label: 'Llama / 本地模型兼容环境',
      preferResponsesApi: false,
      supportsVision: value.contains('vision'),
      supportsFileInput: false,
    );
  }
  if (value.startsWith('gpt-') ||
      value.startsWith('chatgpt') ||
      value.startsWith('o1') ||
      value.startsWith('o3') ||
      value.startsWith('o4') ||
      value.contains('openai')) {
    return const AiModelRuntimeProfile(
      provider: AiModelProvider.openAi,
      label: 'OpenAI Responses 兼容环境',
      preferResponsesApi: true,
      supportsVision: true,
      supportsFileInput: true,
    );
  }
  return const AiModelRuntimeProfile(
    provider: AiModelProvider.generic,
    label: 'OpenAI Chat Completions 兼容环境',
    preferResponsesApi: false,
    supportsVision: false,
    supportsFileInput: false,
  );
}

class AiModelRecommendation {
  const AiModelRecommendation({required this.model, required this.reason});

  final String model;
  final String reason;
}

AiModelRecommendation? recommendAiModel(
  List<String> models, {
  Map<String, AiModelUsageSummary> localUsage = const {},
}) {
  if (models.isEmpty) return null;
  var best = models.first;
  var bestScore = _qualityScore(best, localUsage[best]);
  for (final model in models.skip(1)) {
    final score = _qualityScore(model, localUsage[model]);
    if (score > bestScore) {
      best = model;
      bestScore = score;
    }
  }
  final usage = localUsage[best];
  final profile = runtimeProfileForModel(best);
  final reason = usage != null && usage.requests >= 2
      ? '${profile.label}；结合本机 ${usage.requests} 次调用的速度和成功率推荐'
      : '${profile.label}；按网关当前可用型号、代际与速度/能力平衡推荐';
  return AiModelRecommendation(model: best, reason: reason);
}

bool isLikelyImageGenerationModel(String model) {
  final value = model.trim().toLowerCase();
  return value.contains('gpt-image') ||
      value.contains('dall-e') ||
      value.contains('imagen') ||
      value.contains('image-generation') ||
      value.contains('imagegen') ||
      value.contains('qwen-image') ||
      value.contains('wanx') ||
      value.contains('tongyi-wanxiang') ||
      value.contains('flux') ||
      value.contains('stable-diffusion') ||
      RegExp(r'(^|[-_/])sd(?:3|xl)(?:[-_/]|$)').hasMatch(value) ||
      value.contains('cogview') ||
      value.contains('seedream') ||
      value.contains('jimeng-image') ||
      value.contains('ideogram') ||
      value.contains('midjourney') ||
      value.contains('firefly') ||
      value.contains('gemini') && value.contains('image') ||
      // GPT-5 relays commonly expose image generation through the Responses
      // image_generation tool instead of a separate Images model.
      value.startsWith('gpt-5');
}

bool isLikelyVideoGenerationModel(String model) {
  final value = model.trim().toLowerCase();
  return value.contains('sora') ||
      value.contains('veo') ||
      value.contains('runway') ||
      value.contains('pika') ||
      value.contains('kling') ||
      value.contains('hailuo') ||
      value.contains('hailuo') ||
      value.contains('minimax-video') ||
      value.contains('wan2') ||
      value.contains('wan-video') ||
      value.contains('hunyuan-video') ||
      value.contains('seedance') ||
      value.contains('jimeng-video') ||
      value.contains('vidu') ||
      value.contains('luma') && value.contains('ray') ||
      value.contains('video-generation') ||
      value.contains('text-to-video') ||
      value.contains('image-to-video') ||
      RegExp(r'(^|[-_/])video(?:[-_/]|$)').hasMatch(value);
}

AiModelRecommendation? recommendAiImageModel(
  List<String> models, {
  Map<String, AiModelUsageSummary> localUsage = const {},
}) => _recommendMediaModel(
  models.where(isLikelyImageGenerationModel).toList(),
  localUsage: localUsage,
  video: false,
);

AiModelRecommendation? recommendAiVideoModel(
  List<String> models, {
  Map<String, AiModelUsageSummary> localUsage = const {},
}) => _recommendMediaModel(
  models.where(isLikelyVideoGenerationModel).toList(),
  localUsage: localUsage,
  video: true,
);

AiModelRecommendation? _recommendMediaModel(
  List<String> models, {
  required Map<String, AiModelUsageSummary> localUsage,
  required bool video,
}) {
  if (models.isEmpty) return null;
  var best = models.first;
  var bestScore = _mediaQualityScore(best, localUsage[best], video: video);
  for (final model in models.skip(1)) {
    final score = _mediaQualityScore(model, localUsage[model], video: video);
    if (score > bestScore) {
      best = model;
      bestScore = score;
    }
  }
  final usage = localUsage[best];
  final type = video ? '视频' : '图片';
  return AiModelRecommendation(
    model: best,
    reason: usage != null && usage.requests >= 2
        ? '结合本机 ${usage.requests} 次调用的成功率与速度，推荐当前$type模型'
        : '按网关返回的$type能力、型号代际与稳定性综合推荐',
  );
}

int _mediaQualityScore(
  String model,
  AiModelUsageSummary? usage, {
  required bool video,
}) {
  final value = model.toLowerCase();
  var score = _qualityScore(model, usage);
  if (value.contains('latest')) score += 600;
  if (value.contains('preview') || value.contains('experimental')) score -= 120;
  if (video) {
    if (value.contains('sora')) score += 1300;
    if (value.contains('veo')) score += 1250;
    if (value.contains('kling')) score += 1100;
    if (value.contains('runway')) score += 1000;
    if (value.contains('seedance')) score += 950;
    if (value.contains('wan2')) score += 850;
    if (value.contains('turbo') || value.contains('fast')) score += 350;
  } else {
    if (value.contains('gpt-image')) score += 2500;
    if (value.contains('imagen')) score += 1250;
    if (value.contains('flux')) score += 1100;
    if (value.contains('qwen-image')) score += 1050;
    if (value.contains('seedream')) score += 950;
    if (value.contains('dall-e-3')) score += 800;
    if (value.startsWith('gpt-5')) score += 700;
  }
  return score;
}

int _qualityScore(String model, AiModelUsageSummary? usage) {
  final value = model.toLowerCase();
  var score = 1000;
  if (value.contains('latest')) score += 900;
  if (value.contains('preview') || value.contains('experimental')) score -= 350;
  if (value.contains('deprecated') || value.contains('legacy')) score -= 5000;

  final profile = runtimeProfileForModel(model);
  switch (profile.provider) {
    case AiModelProvider.openAi:
      score += 5000;
      if (value.contains('chatgpt')) score += 500;
      if (value.contains('mini')) score -= 500;
      if (value.contains('nano')) score -= 1100;
      if (value.startsWith('o') || value.contains('reason')) score -= 250;
      break;
    case AiModelProvider.anthropic:
      score += 5000;
      if (value.contains('sonnet')) score += 950;
      if (value.contains('opus')) score += 800;
      if (value.contains('haiku')) score += 350;
      break;
    case AiModelProvider.qwen:
      score += 4800;
      if (value.contains('plus')) score += 900;
      if (value.contains('max')) score += 750;
      if (value.contains('turbo')) score += 500;
      if (value.contains('coder')) score -= 100;
      break;
    case AiModelProvider.glm:
      score += 4700;
      if (value.contains('air')) score += 700;
      if (value.contains('flash')) score += 550;
      break;
    case AiModelProvider.kimi:
      score += 4750;
      if (value.contains('k2')) score += 900;
      if (value.contains('code')) score -= 80;
      break;
    case AiModelProvider.deepSeek:
      score += 4850;
      if (value.contains('chat') || value.contains('v3')) score += 800;
      if (value.contains('reasoner') || value.contains('r1')) score += 300;
      break;
    case AiModelProvider.gemini:
      score += 4900;
      if (value.contains('pro')) score += 850;
      if (value.contains('flash')) score += 720;
      break;
    case AiModelProvider.llama:
      score += 4200;
      break;
    case AiModelProvider.generic:
      score += 3500;
      break;
  }

  final versions = RegExp(r'\d+(?:\.\d+)*').allMatches(value).toList();
  if (versions.isNotEmpty) {
    final parts = (versions.last.group(0) ?? '').split('.');
    for (var index = 0; index < parts.length && index < 3; index++) {
      score +=
          (int.tryParse(parts[index]) ?? 0) *
          switch (index) {
            0 => 100,
            1 => 10,
            _ => 1,
          };
    }
  }
  if (usage != null && usage.requests >= 2) {
    score -= (usage.failureRate * 5000).round();
    if (usage.averageElapsedMs > 0) {
      score += (2200 - usage.averageElapsedMs ~/ 10).clamp(-1500, 1800);
    }
  }
  return score;
}
