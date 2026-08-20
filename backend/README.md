# 拼豆 AI 服务端

版权所有 © 2026 xuan。

服务端是 Flutter 离线客户端的可选云能力骨架，包含品牌隔离色库、色卡版本、作品元数据、Redis 缓存和 S3/OSS 接口配置。核心 APK 不依赖它也能生成图纸。

## 本地启动

```bash
docker compose up --build
```

API 文档：`http://localhost:8000/docs`，健康检查：`GET /health`。

AI 默认密钥只通过服务端环境变量 `AI_PROXY_API_KEY` 配置，不应写入 APK。
APP 也可成对提交自定义的 `X-AI-Provider-Base-Url` 与
`X-AI-Provider-Key` 请求头；服务端不会保存或输出该密钥。生产环境必须
使用 HTTPS，并在网关配置用户鉴权、速率限制和日志脱敏。

生产部署前应替换 `.env` 中的密钥、配置 TLS、迁移工具、对象存储私有桶、监控告警和正式的 MARD 授权测色数据。
