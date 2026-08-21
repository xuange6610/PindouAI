# 《拼豆 AI 设计》交付测试报告

测试日期：2026-08-21
版本：2.8.10+28
版权所有：xuan

## 自动化结果

- `flutter analyze`：通过，0 issue。
- `flutter test`：通过，126/126。
- Android APK：`1,852,245,145` 字节，APK 内置原图条目 `1265/1265`。
- Windows 安装程序：`1,245,157,779` 字节，静默安装退出码 `0`。
- Windows 安装后图库：`1265` 个文件，原图总字节 `1,774,279,056`，与授权原图清单一致。
- CIEDE2000：公开标准测试对结果 2.0425，误差阈值 0.0001。
- MARD221：总数 221、色号唯一、系列数量、HEX/LAB/尺寸字段校验通过。
- 转换闭环：图片解码、20×20 映射、色数上限、格子索引、数量守恒通过。
- UI 闭环：处理页完成生成、本地保存并进入结果页通过。
- 导出：PNG 可解码，PDF 文件头及文件体生成通过。
- 后端：`python -m compileall backend/app` 通过。

## v2.8.10 安装包验证

- 包名：`com.xuan.bead_ai_designer`
- 应用名：拼豆 AI 设计
- 版本：2.8.10（versionCode 28）
- minSdk：24；targetSdk：36
- ABI：本次构建目标 `android-arm64`。
- APK 结构：zipalign 校验通过；APK Signature Scheme v2 校验通过；包内 1265 个授权原图条目存在。
- Windows 安装：安装到短路径 `artwork`，程序窗口标题为“拼豆 AI 设计”且进程响应正常；安装包不再创建超长 URL 编码资源目录。
- 签名：APK Signature Scheme v2 校验通过；zipalign 校验通过。
- Android SHA-256：`AB4EB09C163D1762F580E38F4B397DD4E0B55FA3303EE8E60D4EF795E94CB2F6`
- Windows SHA-256：`A5A7F1D1413828A57ADBD7154D15794ABCA0624B098B66A8EC11302DECF569B5`

## 发布前注意事项

1. 当前 APK 使用 Flutter 工程的测试签名，可直接安装验收；提交应用商店前必须由xuan持有的正式 keystore 重新签名，且密钥不得提交到源码仓库。
2. 当前 MARD221 RGB/LAB 是工程预置近似值，完整覆盖 221 个编号但不是官方实测色卡。采购和商业印刷前必须导入经授权、在明确光源/观察者条件下测得的正式数据。
3. Android 已完成本次交付；iOS 代码兼容，但仍需 Apple 开发者账号、证书和真机验收才能发布。
