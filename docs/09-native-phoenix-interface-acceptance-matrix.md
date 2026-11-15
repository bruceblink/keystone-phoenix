# Native 与 Phoenix 接口验收矩阵

正式版本的同一份 admin-web 必须能够替换连接 Native 或 Phoenix。发布验收条件、双后端页面流程和证据要求见 [`10-admin-web-backend-interchangeability-acceptance.md`](10-admin-web-backend-interchangeability-acceptance.md)。

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

Native 与 admin-web 的真实 HTTP 联调已经覆盖健康检查、RSA 公钥、登录、监控、角色、API Key、登出和 AAL2 step-up。admin-web 的 `pnpm test:run`、`pnpm typecheck` 和 `pnpm build` 均通过。Phoenix `mix test --include integration` 已通过 366 项。

### 真实窗口验收记录

2026-11-15 使用 Codex 内置浏览器，在本机启动 Native、Phoenix 和 admin-web 开发服务后完成页面验收。Native 使用 MySQL 8.4，Phoenix 使用本地 PostgreSQL，admin-web 使用 Vite 代理访问 Native `http://127.0.0.1:8080`。

- admin-web 使用 `admin` 登录成功，进入 `/monitor`。监控页显示 `PARTIAL`，Java 堆和在线会话有数据；CPU、磁盘和网络字段显示 Native 未提供。侧栏、总览别名、用户、角色、组织、岗位、菜单、API Key、操作审计、登录日志、定时任务、系统配置、字典和通知公告页面均能通过真实导航打开，并显示 Native 返回的数据。
- admin-web 用户页的用户名筛选返回 2 条记录；新增用户模态框能打开和关闭。角色新增模态框、API Key 签发模态框和通知公告筛选控件均能打开或使用。未在验收中签发真实 API Key，也未提交会改变业务数据的表单。
- Phoenix 使用 `ag1` 登录成功，概览显示部门、岗位、角色、菜单、公告、用户、配置、字典和任务统计。概览、部门、岗位、角色、菜单、用户、API Key、配置、字典、公告、登录日志、操作审计、定时任务、任务日志、监控和个人资料面板均通过真实导航打开；用户新增表单能打开和关闭。

本次真实窗口验收仍有明确限制：监控页的部分指标由 Native 接口未提供，admin-web 仍显示静态“Native API 正常”标签；Phoenix 与 admin-web 的页面筛选、导出、批量删除和加载状态并未因此自动等价。MFA 登录挑战已覆盖接口和前端错误兼容测试，但本次没有触发真实 MFA 挑战；OIDC、公钥硬件 Passkey、CSRF/Cookie、多节点和生产代理链不属于本地窗口验收，不能据此判定通过。
