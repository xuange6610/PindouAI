# AI 多模型工作台

前后端分离的多模型聊天平台。浏览器只访问本项目后端，模型 API Key 使用服务器端 Fernet 加密后写入 MySQL，不返回前端。

当前可运行范围：

- 邮箱注册、JWT 登录、管理员/用户/访客角色模型
- 用户私有模型与管理员共享模型
- OpenAI 兼容协议、Anthropic、Gemini、Ollama 适配器
- ChatGPT 风格会话、历史记录、模型切换、Markdown、代码高亮、SSE 流式输出
- PDF、Office、文本、CSV、图片等文件上传和所有权隔离
- `users`、`chats`、`messages`、`models`、`api_configs`、`files`、`knowledge`、`agents`、`usage_logs`、`audit_logs` 表
- Agent 基础管理、管理员统计、Redis 和 Qdrant 部署服务

## 启动

1. 将 `.env.example` 复制为 `.env`，替换所有密码及两个独立密钥。
2. 运行 `docker compose up --build -d`。
3. 打开 `http://localhost:8080`。

首次注册的账号默认为普通用户。生产环境应通过受控数据库迁移或管理脚本设置首个管理员，不应开放“注册管理员”接口。

## 扩展 Provider

在 `backend/app/gateway/` 新增 `ModelAdapter`，并在 `factory.py` 注册协议名称。模型记录只保存实际 `model_id`，不把第三方名称硬映射成其他厂商模型。

## 后续阶段边界

数据库已经包含知识库、Agent、审计和用量结构，Docker 已包含 Qdrant。文档解析、切片、Embedding、检索重排、工具沙箱、OAuth/短信验证、计费结算和 Alembic 迁移需要在部署域名、对象存储、邮件/短信服务以及具体 Embedding 模型确定后继续实现和验收。
