# Native 与 Phoenix 接口验收矩阵

## 术语和命名

| 术语 | English | 职责和边界 |
| --- | --- | --- |
| 接口路径 | endpoint path | HTTP 方法与 URL 的组合。本文只记录 `/api/v1` 对外入口。 |
| 响应结构 | DTO | `success`、`data`、`message`、`error` 信封内的字段结构。路径一致不表示 DTO 一致。 |
| AAL2 | Authentication Assurance Level 2 | 已完成当前会话二次认证的短时访问令牌。敏感写操作必须使用 AAL2。 |

## 已完成的路径和权限对齐

Native 作为 HTTP 入口基准，Phoenix 已完成以下路径处理：

- 删除 Native 没有的用户导入模板、部门详情、岗位详情、菜单详情、角色详情、旧字典读取、角色状态和数据范围入口。
- 删除旧 `/system/*` 和 `/logs/*` 管理路径，保留 Native 同样存在的登录日志和操作日志删除入口。
- 保留并补齐任务单项删除 `DELETE /api/v1/jobs/{id}`。
- 补齐菜单角色绑定 `PUT /api/v1/menus/{id}/roles`。
- 对齐公告公开读取、管理读取和发布：
  `GET /api/v1/notices`、`GET /api/v1/notices/manage`、
  `POST /api/v1/notices/{id}/publish`。
- 用户、角色、API Key、在线会话下线和个人密码写操作要求 AAL2；API Key 不进入人类认证路径。
- Native 的任务触发路径 `/api/v1/jobs/{id}/trigger` 已删除旧的重复 `/run` 入口。

Phoenix 证据：`mix phx.routes` 未发现 `/system`、`/logs`、`auth/passkey`、`health/ready`、`monitor/networkStatus` 和用户导入模板旧入口。路由和权限修改已在 `f8d3db9` 提交。

### 路由集合验收

2026-11-15 对两个后端的业务路由做了静态集合核对。Native 的 JAX-RS 类级路径与
`quarkus.http.root-path=/api` 合并后，再与 Phoenix 的 `mix phx.routes` 结果比较；参数
占位符 `{id}` 与 `:id` 先归一为同一形状。两边均有 109 条业务路由，方法分布均为
`GET 41`、`POST 29`、`PUT 20`、`DELETE 19`。归一化后 Native-only 和 Phoenix-only
业务路由均为 0，也没有重复的 `HTTP method + path`。Phoenix 额外的 3 条 GET 路由是
LiveView 页面和头像资源，不属于后端业务接口。

Native 还有 `/api/openapi` 和 `/api/swagger` 文档入口。它们由 Quarkus 生成，不纳入
业务接口集合。参数占位符的语言差异不表示接口缺失。

## DTO 和数据模型验收结果

Phoenix HTTP 控制器现在按 Native/admin-web 的响应结构返回数据。用户、角色、部门、岗位、菜单、配置、字典、公告、任务、审计、个人资料和监控均有对应的字段适配和回归测试。列表接口按 Native 约定返回数组或 `items/page/size/total`，创建和更新返回实体，删除返回 `deleted`，任务触发返回 `triggered`。

为保存 Native 所需的业务字段，新增并应用了部门编码、菜单编码、菜单排序、配置启用状态、任务编码和字典字符串值迁移。部门和菜单保留旧 LiveView 原始写入的数据库触发器。任务编码另有更高版本修复迁移，覆盖“迁移记录已存在但列未创建”的旧安装状态。

仍有三个明确边界：Phoenix 用户表只有一个 `role_id`，HTTP 写入支持零个或一个 `roleCodes`，多个角色编码返回校验错误；Phoenix 任务列表的 `lastStatus` 和 `lastRunAt` 没有独立持久化来源，返回空值；Phoenix 的 BEAM 运行时按 Native 监控字段提供结构化结果，Java 专属含义不适用。以上边界不会静默丢弃请求字段。

## UI 验收边界

Native 与 admin-web 的真实 HTTP 联调已经覆盖健康检查、RSA 公钥、登录、监控、角色、API Key、登出和 AAL2 step-up。admin-web 的 `pnpm test:run`、`pnpm typecheck` 和 `pnpm build` 均通过。Phoenix `mix test --include integration` 已通过 365 项。

Phoenix LiveView 已覆盖用户、角色、部门、岗位、菜单、配置、字典、公告、日志、任务、监控、个人资料和 API Key 面板。当前没有可用的真实浏览器窗口证据；MFA 登录挑战、OIDC 按钮和 WebAuthn 页面也不是两个前端共同提供的功能，不能作为 Phoenix 单边已完成项。
