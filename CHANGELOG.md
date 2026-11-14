# Keystone Phoenix 当前主线

## [Unreleased]

### 修复 / Bug Fixes

- 生产运行时拒绝未明确允许的 HTTP 配置、无效的 CORS 来源和缺失的 `PHX_HOST`。
- 统一 API、LiveView、静态资源和错误响应的安全头；未登记的跨域来源不返回 CORS 授权头。

### 新增 / Features

- 增加标准 `/api/.well-known/jwks.json` smoke 校验，确认 RSA JWK 的 `kid`、`alg`、`use`、`n` 和 `e` 字段。
- 增加 API Key 的业务访问、元数据脱敏、MFA/人类会话入口拒绝和撤销后失效检查。
- 增加生产 HTTPS、HSTS、CORS 来源和安全头的运行时启动检查。

### 优化 / Performance

- 将跨域预检处理限制在显式允许的来源，避免为跨域请求启用凭据。

### 维护、文档与测试 / Maintenance, Docs & Tests

- 补充 release smoke 的 MFA、JWK、API Key 和资源范围验收边界；非管理员范围矩阵继续由集成测试和真实 HTTP 验收覆盖。
- 更新部署手册、环境变量示例和当前主线发布记录；本节不对应 Git tag 或 GitHub Release。

# Keystone Phoenix 0.3.0

对比范围：`v0.2.0..v0.3.0`　发布日期：2026-11-12

## 修复

- 完善认证会话、refresh token 轮换、退出登录、权限校验、数据范围和生产运行时边界。
- 修复上传下载、数据库故障恢复、重复迁移、备份恢复、定时任务异常退出和无效路由参数处理。
- 修复 Elixir 1.20 依赖编译 warning，以及预期调度任务终止产生的 warning。

## 新增

- 增加完整的 LiveView 管理后台，覆盖账号、组织、角色、菜单、配置、字典、公告、定时任务和运行监控。
- 新增表格分页、状态徽标、无障碍语义、错误反馈和响应式窄屏布局。
- 新增共享模态框交互。管理表格默认进入查询页面，新增和编辑表单在模态框中完成。

## 优化

- 统一管理后台导航、页面标题、状态表达和表格操作层级，采用正式的产品文案和现代化视觉样式。
- 优化连接池、在线会话、任务列表和监控数据的分页与 Telemetry 指标。

## 调整

- Dockerfile 默认使用 Docker Hub、Hex 和 Debian 官方镜像源；本地构建可显式传入镜像参数切换源。
- 运行时镜像使用非 root 用户，并保留健康检查、TLS 校验和启动可写性检查。

## 构建

- 后续 GitHub Actions 仅在 `vX.Y.Z` 正式版本标签发布时，将镜像推送到 `ghcr.io/bruceblink/keystone-phoenix`，并只生成相同的 `vX.Y.Z` 镜像标签。
- 发布镜像生成 SBOM 和 provenance，并使用 Cosign keyless 签名；发布烟测覆盖迁移、认证、文件、持久化、备份恢复和数据库故障恢复。
- 本地 `linux/arm64` 生产镜像 smoke 和 macOS Chrome 真实窗口验收均已通过。生产容器使用独立 PostgreSQL 18 和 `localhost:4001`，覆盖登录、管理员概览、部门查询与新增模态框、运行监控、退出登录及 `390×844` 窄屏无横向溢出。

