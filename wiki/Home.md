# 拼豆 AI 设计 Wiki

把照片、文字和现成图纸转换为真正能制作的品牌色号拼豆图。PindouAI 是离线优先的 Flutter 拼豆工作台，Android 与 Windows 正式包均内置 1265 张授权图纸；照片转换、画板、作品管理和 PNG/PDF 导出不要求登录，也不依赖服务端。

GitHub Pages 用于展示真实界面和功能说明，GitHub Wiki 提供逐页面操作手册。要实际制图，请从 [最新 Release](https://github.com/xuange6610/PindouAI/releases/latest) 下载完整 APK 或 Windows 安装程序。

![拼豆 AI Android 首页](https://xuange6610.github.io/PindouAI/screenshots/home-android.png)

## Wiki 导航

1. [安装与快速开始](01-安装与快速开始) - Android APK、Windows EXE、校验和第一张图纸。
2. [首页与照片制图](02-首页与照片制图) - 相册、相机、批量导入、裁切和基础流程。
3. [参数编辑与处理中心](03-参数编辑与处理中心) - 画板、颜色、保护、去噪和后台任务。
4. [结果页与导出](04-结果页与导出) - 预览、编号格子、颜色统计、PNG 与 PDF。
5. [完整图纸库](05-完整图纸库) - 1265 张图纸、24 个顶层分类、搜索和高清原图。
6. [作品、收藏与回收站](06-作品收藏与回收站) - 搜索、排序、批量管理、分组与恢复。
7. [自定义画板](07-自定义画板) - 逐格绘制、批量换色、草稿和工程文件。
8. [文字拼豆、识别与抠图](08-文字拼豆图片识别与抠图) - 文字渲染、图片色号识别和主体处理。
9. [多品牌色库与颜色匹配](09-多品牌色库与颜色匹配) - 色号查询、色卡筛选和颜色科学。
10. [AI 对话与 AI 制图](10-AI对话与AI制图) - 多模型对话、附件、风格制图和历史。
11. [API 设置、任务与用量](11-API设置任务与用量) - 地址、密钥、模型检测、任务中心和 Token。
12. [设置、备份、声音与隐私](12-设置备份声音与隐私) - 主题、语言、换机、本地音乐和数据边界。
13. [Windows 版完整使用](13-Windows版完整使用) - 安装、桌面布局、资源目录和卸载。
14. [常见问题与故障排查](14-常见问题与故障排查) - 安装、图库、AI、导出和色差问题。
15. [技术架构与源码运行](15-技术架构与源码运行) - Flutter 分层、算法、可选服务和构建。
16. [发布文件与校验](16-发布文件与校验) - APK、EXE、SHA-256、版本和下载边界。
17. [版权、安全与参与贡献](17-版权安全与参与贡献) - 源码许可、图纸授权、密钥和 PR 流程。

## 快速入口

- 产品展示：[xuange6610.github.io/PindouAI](https://xuange6610.github.io/PindouAI/)
- GitHub 主页：[github.com/xuange6610/PindouAI](https://github.com/xuange6610/PindouAI)
- 最新下载：[Releases/latest](https://github.com/xuange6610/PindouAI/releases/latest)
- 问题反馈：[GitHub Issues](https://github.com/xuange6610/PindouAI/issues)

## 功能边界

- 核心照片转换、完整图库、画板、作品和导出可离线使用。
- AI 对话、AI 制图和 AI 修复需要用户自行配置兼容 API；软件不附带公共密钥或免费额度。
- Android APK 当前使用项目测试签名，适合直接安装体验，不代表应用商店正式签名。
- 源代码采用 Apache-2.0；内置图纸适用独立的 `ARTWORK_LICENSE.md`，不能把图纸当作 Apache-2.0 素材单独转售。

项目由 xuan 维护。文档只描述当前仓库和已发布安装包中实际存在的能力，不把可选服务写成默认在线服务。
