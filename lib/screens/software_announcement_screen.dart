import 'package:flutter/material.dart';

class SoftwareAnnouncementScreen extends StatelessWidget {
  const SoftwareAnnouncementScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('软件公告 · AI 兼容说明')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
      children: const [
        Card(
          color: Color(0xFFFFF2CC),
          child: Padding(
            padding: EdgeInsets.all(15),
            child: Text(
              '重要说明：软件支持的是 API 协议和中转端点，不等于可以绕过厂商授权直接调用所有消费端产品。没有公开 API 的平台，必须由用户选择的服务商提供合法授权且格式兼容的中转；软件不会伪造“已直连”。',
              style: TextStyle(fontWeight: FontWeight.w800, height: 1.55),
            ),
          ),
        ),
        SizedBox(height: 12),
        _AnnouncementSection(
          title: '已实现的对话协议',
          text:
              '• OpenAI Chat Completions 与 Responses（含 SSE 流式输出、图片/文件输入、reasoning 摘要）\n'
              '• Anthropic Messages 官方协议（文本、图片、流式 thinking 摘要）\n'
              '• Google Gemini generateContent / streamGenerateContent 官方协议\n'
              '• 自动读取模型列表，兼容返回 data、models、id、name、model_id 的中转\n'
              '• 所有中转返回的任意模型 ID 都可使用，不按厂商名称硬拦截',
        ),
        _AnnouncementSection(
          title: '可通过上述协议使用的模型家族',
          text:
              'OpenAI / ChatGPT / Codex、Claude、Gemini / Gemma、Grok、Mistral、Cohere、Llama、DeepSeek、Qwen 通义千问、Kimi / Moonshot、GLM 智谱、豆包、文心、讯飞星火、腾讯混元/元宝、盘古、百川、MiniMax、零一万物、商汤等。实际可见型号、上下文、文件和视觉能力由你的 API 账户及中转返回为准。',
        ),
        _AnnouncementSection(
          title: '图片生成兼容层',
          text:
              '支持 OpenAI Images generations/edits、Responses image_generation、URL 与 Base64 图片返回，并对中转常见响应字段做兼容解析。DALL·E、OpenAI 图像模型、Stable Diffusion、通义万相、即梦、Ideogram、Adobe Firefly、Midjourney 等只有在中转提供上述兼容端点或授权适配时才能实际生成。',
        ),
        _AnnouncementSection(
          title: '视频生成兼容层',
          text:
              '支持 /videos/generations、/video/generations、/videos，支持异步任务 ID 轮询、URL/Base64/直接视频返回。Sora、Runway、Pika、可灵、即梦视频、海螺、HeyGen、Synthesia 等需中转提供合法的视频生成端点；普通聊天模型本身不能凭模型名自动获得视频能力。',
        ),
        _AnnouncementSection(
          title: '消费端产品与开发工具',
          text:
              'Copilot、GitHub Copilot、Cursor、Windsurf、CharacterAI、Replika、Perplexity、WPS AI、飞书/钉钉/腾讯文档助手、Comate、通义灵码以及各类 AI 搜索属于产品或工具，不是统一的大模型 API。若其官方或授权中转提供兼容接口，可在本软件中配置；否则不能直接对接其网页账号。',
        ),
        _AnnouncementSection(
          title: '自动推荐规则',
          text:
              '每次 API 地址、密钥或模型列表变化后重新判断。推荐同时考虑模型家族、型号代际、旗舰/均衡/轻量定位，以及本机真实调用的响应速度和失败率；当前选择仍在 API 目录中时会保留，已不在目录中时会自动切换为该 API 的综合推荐模型。中转响应中的内部模型别名不会改写仍然有效的本机配置。',
        ),
      ],
    ),
  );
}

class _AnnouncementSection extends StatelessWidget {
  const _AnnouncementSection({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          SelectableText(text, style: const TextStyle(height: 1.6)),
        ],
      ),
    ),
  );
}
