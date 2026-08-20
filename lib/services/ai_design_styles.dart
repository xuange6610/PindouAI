class AiBeadDesignStyle {
  const AiBeadDesignStyle({
    required this.id,
    required this.title,
    required this.tag,
    required this.description,
    required this.exampleAsset,
    required this.stylePrompt,
  });

  final String id;
  final String title;
  final String tag;
  final String description;
  final String exampleAsset;
  final String stylePrompt;

  String buildPrompt(String userRequest) {
    final extra = userRequest.trim();
    return '''
把上传的参考照片重新绘制为$title，最终用于转换成拼豆图纸。
$stylePrompt
必须保留参考照片中的人物数量、主要身份特征、发型、服装主色、姿势和主体关系；简化杂乱背景，但不能添加照片中不存在的人物。
画面要求：正方形构图，主体完整居中，纯像素块边缘，颜色分区清晰，限制渐变和半透明，不要签名或水印。若用户要求拼豆网格、色号、豆子数量、品牌款式或图例，必须完整、清晰地展示这些制图信息，并确保图例不遮挡主体。
${extra.isEmpty ? '在不改变主体的前提下自动优化构图。' : '用户补充要求：$extra'}
'''
        .trim();
  }
}

abstract final class AiBeadDesignStyles {
  static const all = <AiBeadDesignStyle>[
    AiBeadDesignStyle(
      id: 'refined',
      title: '精致像素风',
      tag: '推荐',
      description: '轮廓准确、细节丰富，适合人物照片',
      exampleAsset: 'assets/pindou_collection/sample_refined.png',
      stylePrompt: '采用高精度现代像素插画风格，面部比例自然，明暗层次用离散色块表达，轮廓清楚，细节丰富但保持可拼豆化。',
    ),
    AiBeadDesignStyle(
      id: 'anime',
      title: '动漫像素风',
      tag: '人像',
      description: '动漫五官与清晰线条，适合单人或合照',
      exampleAsset: 'assets/pindou_collection/sample_anime.png',
      stylePrompt: '采用日系动漫像素插画风格，清晰深色描边，眼睛和表情更有表现力，发型与服装用成组像素色块表达。',
    ),
    AiBeadDesignStyle(
      id: 'chibi',
      title: 'Q版像素风',
      tag: '可爱',
      description: '大头小身、表情可爱，适合情侣与全身照',
      exampleAsset: 'assets/pindou_collection/sample_chibi.png',
      stylePrompt: '采用Q版像素角色风格，大头小身但必须保留人物辨识度，表情亲切可爱，造型简洁，轮廓闭合，配色明快。',
    ),
    AiBeadDesignStyle(
      id: 'farm_rpg',
      title: '星露谷像素风',
      tag: '田园',
      description: '16-bit田园RPG质感，复古温暖',
      exampleAsset: 'assets/pindou_collection/sample_farm.png',
      stylePrompt:
          '采用经典16-bit田园生活RPG像素美术语言，复古暖色调、紧凑调色板和清晰像素簇；只借鉴通用田园像素质感，不复制任何现有游戏角色或素材。',
    ),
  ];

  static AiBeadDesignStyle byId(String id) =>
      all.firstWhere((style) => style.id == id, orElse: () => all.first);
}
