# 《拼豆 AI 设计》技术架构方案

版权所有 © 2026 xuan

## 总体设计

采用“离线优先客户端 + 可横向扩展服务端”架构。Flutter 客户端持有核心转换算法和内置色库，保证弱网可用；FastAPI 服务负责账号、云作品、色库版本、异步高质量任务和运营后台。

```text
Flutter Android/iOS
  ├─ UI：Home / Editor / Result / Library / Profile
  ├─ Domain：Pattern、BeadColor、Project
  ├─ Algorithm：Resize → LAB K-Means → CIEDE2000 → Palette
  ├─ Storage：应用文档目录 + SharedPreferences
  └─ Export：PNG / paginated PDF / system share
             │ HTTPS + JWT
FastAPI ─────┼─ PostgreSQL（用户、项目、色库元数据）
             ├─ Redis（缓存、限流、任务状态）
             ├─ Worker（高质量图像任务）
             └─ S3/OSS（原图、产物、缩略图）
```

## 客户端分层

- `models/`：不可变领域模型和序列化。
- `data/`：221 色库、作品文件存储。
- `services/`：颜色科学、图像处理、导出。
- `screens/`：页面与交互流程。
- `widgets/`：预览画布、统计组件和统一视觉组件。

算法任务用 Flutter isolate 执行，避免阻塞 UI。200×200 的上限为 40,000 格；颜色匹配先以 LAB K-Means 得到候选色，再在候选色中计算 CIEDE2000，从而控制计算量。

## 服务端扩展

- API 无状态部署，负载均衡后可水平扩容。
- PostgreSQL 作为事实数据源，品牌/色卡/颜色以外键隔离，禁止跨品牌复用编号。
- Redis 保存任务状态、热点色卡和限流令牌。
- 原图和导出文件只存对象存储，数据库保存对象键和校验和。
- 高质量转换通过任务队列异步执行；幂等键避免重复任务。
- 百万用户阶段按 `user_id` 对作品表分区，并用 CDN 分发产物。

## 安全与隐私

- 本地模式不上传照片。
- 云模式必须显式授权，传输使用 TLS，私有对象使用短期签名 URL。
- 密码只存 Argon2id 哈希；访问令牌短时有效，刷新令牌轮换。
- 服务端校验 MIME、尺寸、像素数和解压炸弹；原图设置生命周期删除。
- 管理后台导入需要 RBAC、审计日志、版本回滚和文件病毒扫描。

## 可观测性与质量

- OpenTelemetry trace 串联 API、任务队列和对象存储。
- 指标：生成成功率、P95 时延、Delta E 分布、导出失败率、崩溃率。
- 测试：颜色公式金样、221 色完整性、统计守恒、序列化往返、Flutter 页面冒烟、API 健康检查。
