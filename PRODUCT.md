# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

主要用户是中文拼豆爱好者、手工作室和需要把照片、文字或现成图纸转换为可制作方案的创作者。用户通常在 Android 手机上导入素材、生成和查看图纸，也可在 Windows 上进行更大画布的编辑与管理。

## Product Purpose

PindouAI 把照片、文字和灵感转换为带品牌色号、格子编号与用量统计的拼豆图纸。成功意味着用户无需联网即可完成导入、生成、调整、保存和 PNG/PDF 导出，并能从内置授权图库快速开始。

## Positioning

产品不是普通像素滤镜，而是把图像颜色经过裁切、降色、CIE LAB 与 CIEDE2000 匹配，落到可查询、可备料、可打印的品牌色号图纸。

## Operating Context

核心流程是下载 APK、选择照片或图库图纸、设置画板和颜色参数、核对生成结果、保存作品并导出。用户还可以使用自定义画板、文字拼豆、图片色号识别、多品牌色卡、收藏、回收站、换机备份以及可选 AI 对话和制图服务。

## Capabilities and Constraints

- Android 与 Windows 正式包内置 1265 张授权图纸及完整预览清单。
- 核心图片转换和本地作品管理不依赖服务端。
- AI 对话、AI 图片和视频能力需要用户自行配置兼容 API。
- Android APK 当前使用项目测试签名，适合安装体验，不用于应用商店上架。
- iOS 源码兼容但未作为本次公开 Release 交付物。
- 图纸适用 `ARTWORK_LICENSE.md`，源码适用 Apache-2.0。

## Brand Commitments

产品名称为“拼豆 AI 设计 / PindouAI”，由 xuan 维护。视觉使用应用现有的珊瑚红、深墨色、青绿色和明亮白底，强调真实工具感、离线可用与可制作结果，不使用虚构用户评价或性能数据。

## Evidence on Hand

- Android 首页与结果页真实截图：`docs/screenshots/` 和 `artifacts/android-result-smoke.png`。
- Windows 首页、画板与设置真实截图：`artifacts/` 和 `docs/screenshots/`。
- 1265 项图库清单：`assets/pindou_collection/manifest.json`。
- 自动化验证与历史设备记录：`docs/TEST_REPORT.md`。

## Product Principles

- 先让用户快速得到一张真正能制作的图纸。
- 核心工作流离线、可解释、可重复。
- 真实截图和实际能力优先于营销概念图。
- 复杂功能分层呈现，默认路径保持清楚。
- 用户照片、API 密钥和本地作品由用户掌控。

## Accessibility & Inclusion

公开说明页支持键盘导航、清晰焦点、可读对比度、移动端无横向滚动以及 reduced-motion。应用功能说明使用中文直述，不要求用户理解颜色科学术语后才能开始。
