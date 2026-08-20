# 《拼豆 AI 设计》交付测试报告

测试日期：2026-08-20
版本：2.8.10+28
版权所有：xuan

## 自动化结果

- `flutter analyze`：通过，0 issue。
- `flutter test`：通过，126/126。
- CIEDE2000：公开标准测试对结果 2.0425，误差阈值 0.0001。
- MARD221：总数 221、色号唯一、系列数量、HEX/LAB/尺寸字段校验通过。
- 转换闭环：图片解码、20×20 映射、色数上限、格子索引、数量守恒通过。
- UI 闭环：处理页完成生成、本地保存并进入结果页通过。
- 导出：PNG 可解码，PDF 文件头及文件体生成通过。
- 后端：`python -m compileall backend/app` 通过。

## Android Release 历史验证

以下为 2026-07-29 对早期 1.0.0+1 APK 的历史验收记录，不代表本次源码公开重新构建了 Android 安装包。

- 包名：`com.xuan.bead_ai_designer`
- 应用名：拼豆 AI 设计
- 版本：1.0.0（versionCode 1）
- minSdk：24；targetSdk：36
- ABI：armeabi-v7a、arm64-v8a、x86_64
- 安装：Pixel 8 Android 模拟器安装成功。
- 启动：首页前台 Activity 正常，进程存活，无 FATAL EXCEPTION / Flutter error。
- 操作：系统相册选择和编辑页实际通过；中文排版与主要页面视觉截图通过。
- 签名：APK Signature Scheme v2 校验通过；zipalign 校验通过。
- SHA-256：`7589625EAEA94D375B2356E30F67B0A46A617962362AAD95C0FA0CAC7D6D8D05`

## 发布前注意事项

1. 当前 APK 使用 Flutter 工程的测试签名，可直接安装验收；提交应用商店前必须由xuan持有的正式 keystore 重新签名，且密钥不得提交到源码仓库。
2. 当前 MARD221 RGB/LAB 是工程预置近似值，完整覆盖 221 个编号但不是官方实测色卡。采购和商业印刷前必须导入经授权、在明确光源/观察者条件下测得的正式数据。
3. Android 已完成本次交付；iOS 代码兼容，但仍需 Apple 开发者账号、证书和真机验收才能发布。
