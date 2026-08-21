# 拼豆 AI 设计 v2.8.10

这是 PindouAI 首个公开 GitHub Release，对应应用版本 `2.8.10+28`。

## 下载

- `PindouAI-Android-v2.8.10.apk`：Android 通用安装包，使用项目测试签名。
- `PindouAI-Windows-v2.8.10-x64-Setup.exe`：包含完整图库的 Windows x64 单文件安装程序。
- `PindouAI-Android-v2.8.10-Lite.apk`：不含授权图纸原图和预览的轻量 Android 包，保留核心制图功能与 4 个开源示例。
- `PindouAI-Windows-v2.8.10-x64-Lite-Setup.exe`：不含 `artwork` 图纸目录的轻量 Windows 安装程序，保留核心制图功能与 4 个开源示例。
- `SHA256SUMS.txt`：四个安装包的 SHA-256 校验值。

本次构建实测大小：完整 APK `1,852,245,145` 字节、完整 Windows 安装程序 `1,245,157,779` 字节、Lite APK `24,386,620` 字节、Lite Windows 安装程序 `20,944,869` 字节。完整包包含 1265 张授权图纸；Lite 包不包含授权图纸原图和预览，仅保留 4 个开源示例。Windows Lite 安装后会创建桌面和开始菜单入口。

## 主要能力

- 照片转拼豆图纸、裁切、降色、去噪和品牌色号匹配。
- 自定义画板、文字拼豆、作品管理、备份与恢复。
- PNG、PDF、编号格子图和颜色用量清单导出。
- 核心转换离线运行；AI 与云端服务按需配置。

## 图纸库与签名说明

- 源码和安装包内置 1265 张高清图纸及对应预览。
- xuan 已确认拥有这些图纸在本项目中的公开分发授权；图纸不适用 Apache-2.0，详见 `ARTWORK_LICENSE.md`。
- Android APK 使用测试签名，适合安装体验，不用于应用商店发布。
