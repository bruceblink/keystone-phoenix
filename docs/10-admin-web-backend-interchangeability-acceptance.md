# admin-web 后端可替换发布验收矩阵

## 术语和命名

| 术语 | English | 职责和边界 |
| --- | --- | --- |
| admin-web | Admin Web | React 管理页面。本文以正式构建产物作为唯一页面基准。 |
| Native 后端 | Keystone Native | Java/Quarkus HTTP 服务。提供 `/api/v1` 接口。 |
| Phoenix 后端 | Keystone Phoenix | Elixir/Phoenix HTTP 服务。提供与 Native 相同的 `/api/v1` 接口。 |
| 可替换后端 | backend interchangeability | 同一份 admin-web 构建在不修改页面代码的条件下，分别连接两个后端并完成相同验收流程。 |
| 真实窗口验收 | real-window acceptance | 使用 Codex 内置浏览器操作实际页面。Mock 数据、静态 HTML 和组件测试不属于真实窗口通过证据。 |

## 发布目标

正式发布的同一份 admin-web 构建必须满足以下条件：

1. `VITE_ENABLE_MOCK=false` 时，页面只使用当前后端的真实响应。
2. 页面只依赖 `/api/v1` 约定，不读取 Native 或 Phoenix 的内部字段。
3. Native 和 Phoenix 返回相同的响应信封、字段含义、状态码、分页规则、错误分类和 AAL2 行为。
4. 登录、刷新、注销、会话失效、用户、角色、组织、岗位、菜单、API Key、审计、任务、配置、字典、公告、监控和个人资料流程在两个后端完成相同的页面验收。
5. 旧接口和重复接口不再出现在正式路由集合中。

本地切换方式：

```bash
# Native
VITE_API_PROXY_TARGET=http://localhost:8080 VITE_ENABLE_MOCK=false pnpm dev

# Phoenix
VITE_API_PROXY_TARGET=http://localhost:4000 VITE_ENABLE_MOCK=false pnpm dev
```

生产部署使用同源 `/api/v1`，不依赖 Vite 开发代理。

## 接口验收条件

| 接口范围 | 必须一致的内容 | 当前证据 |
| --- | --- | --- |
| 认证和会话 | `accessToken`、`refreshToken`、`sessionId`、`clientId`、401、刷新失效和注销 | Native/Phoenix HTTP 契约测试；需对两个后端分别执行真实窗口流程 |
| MFA 登录和 step-up | 401 二次认证请求结构、AAL2 短时令牌、敏感写操作拒绝 AAL1 | admin-web 兼容测试和后端回归；真实 MFA 仪式仍需补充 |
| 列表查询 | 字段名称、分页 `items/page/size/total`、筛选参数、空结果 | Native/Phoenix 控制器契约测试；需用同一 admin-web 页面双后端核验 |
| 写操作 | 请求字段、201/200/204、`deleted`/`triggered` 结果、验证错误 | Native/Phoenix HTTP 回归；需覆盖发布版本构建 |
| 错误处理 | `success/data/message/error`、401/403/404/422/503 分类 | admin-web 仅对网络错误允许开发 Mock 回退；HTTP 错误必须显示 |
| 路由集合 | 业务方法与路径集合相同，无重复和过时入口 | 109 条业务路由集合核对已通过 |

## 页面验收条件

对每个后端重复以下流程。页面、操作顺序和筛选条件保持一致，结果分别记录：

- 登录、刷新页面、注销和会话失效返回登录页。
- 监控页读取真实状态，显示后端来源和未提供指标；空在线会话显示明确空态。
- 用户页使用用户名和展示名筛选，打开新增/编辑，验证 enabled、角色、数据范围错误反馈。
- 角色、部门、岗位、菜单页验证筛选、层级、状态、删除确认和错误反馈。
- API Key 页验证元数据列表、签发一次性密钥、轮换、撤销和 AAL2 step-up。
- 审计页验证用户、动作、资源筛选、分页和导出；页面保持只读交互。
- 任务页验证筛选、编辑、启停、执行、日志和批量删除。
- 配置、字典、公告页验证筛选、CRUD、启用状态、公告发布/取消发布和空态。
- 个人资料页验证资料保存、密码更新的 AAL2 step-up 和会话失效提示。

Phoenix LiveView 管理页面同时以 admin-web 的颜色、布局、筛选栏、表格、卡片、徽标、空态、错误反馈、分页和模态框为视觉基准。LiveView 重实现不改变 `/api/v1` 接口约定。

2026-11-15 的真实窗口记录使用同一份 admin-web 构建分别连接 Native 和 Phoenix，且设置
`VITE_ENABLE_MOCK=false`。两个后端均已完成登录、监控、总览、用户、角色、组织、岗位、菜单、
API Key、审计、任务、配置、字典、公告和个人资料页面的真实导航；Phoenix 还完成了任务日志和
登录日志页面的导航。Native 监控页返回 `PARTIAL`，Phoenix 监控页返回 BEAM/OTP 运行时数据。
这项记录确认后端可以替换使用同一份 admin-web 页面，不能代替每个写操作的逐项验收。

Phoenix LiveView 已完成共享壳、登录、账号组织和系统页面的主要视觉重实现。侧栏宽度、顶栏高度、
颜色令牌、卡片、筛选区、按钮、表格、徽标、用户图形个人资料入口和侧栏菜单结构已经按 admin-web
对齐。窄屏布局已改为侧边抽屉，顶栏按钮、遮罩关闭和页面切换后的自动收起已通过真实窗口操作验证。
发布前必须补做最新提交后的完整 LiveView 真实窗口矩阵，并逐页记录筛选、导出、批量操作、空态、
错误反馈、分页和模态框结果。

## 发布前证据

每个正式版本必须保留以下证据：

1. Native 和 Phoenix 各自的完整测试、严格编译和源码行数结果。
2. 同一 admin-web commit 的 `pnpm test:run`、`pnpm typecheck` 和 `pnpm build`。
3. `VITE_ENABLE_MOCK=false` 下分别连接 Native、Phoenix 的真实窗口截图或操作记录。
4. 两个后端的路由集合差异、旧接口搜索和数据库迁移状态。
5. 未完成的 OIDC、公钥硬件 Passkey、CSRF/Cookie、多节点和生产代理检查必须单独标记为证据缺口，不能写成页面通过。

当前状态：后端业务路由集合、DTO 适配和 Native/Phoenix HTTP 接口对齐已完成；旧接口和重复接口已从正式业务路由集合删除；admin-web 已在 `VITE_ENABLE_MOCK=false` 下分别连接两个后端并完成真实窗口页面矩阵。Phoenix LiveView 的共享壳、登录、账号组织、系统页面和响应式侧边导航已完成主要视觉重实现，但最新提交后的完整 LiveView 真实窗口矩阵、真实 MFA 仪式以及 OIDC、硬件 Passkey、CSRF/Cookie、多节点和生产代理链仍是发布证据缺口。
