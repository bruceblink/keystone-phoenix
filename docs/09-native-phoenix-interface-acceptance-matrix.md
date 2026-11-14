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

## 当前未通过的 DTO 验收

以下项目的 HTTP 路径已经存在，但响应或写入字段仍不能作为 Native 的可替换实现：

| 资源 | 当前问题 | 需要完成的验收 |
| --- | --- | --- |
| 用户 | Phoenix 使用 `userId`、`nickname`、`status` 和 `rows`；Native 使用 `id`、`displayName`、`enabled` 和 `items`。创建、修改、状态、密码和删除响应也不完全一致。 | 用真实用户读写 HTTP 测试核验字段、页码、删除数量和角色编码。 |
| 角色 | Phoenix 使用旧角色字段和分页结构；Native 返回角色数组，并要求实体写入响应和角色用户 ID 数组。 | 核验角色数组、写入实体、权限集合和角色成员 ID 数组。 |
| 部门 | Phoenix 数据表没有 Native 的部门 `code` 字段。只在 HTTP 层生成 `code` 会丢失写入语义。 | 先增加持久化字段和迁移，再核验创建、修改、列表和删除。 |
| 菜单 | Phoenix 数据表没有 Native 的菜单 `code` 字段，菜单字段和树结构也不同。 | 增加字段映射和持久化迁移，再核验菜单树、下拉列表和角色绑定。 |
| 岗位 | 字段可以映射，但当前响应和写入仍使用 Phoenix 旧字段。 | 核验 `id/code/name/sortOrder/enabled` 和实体写入响应。 |
| 配置和字典 | Phoenix 的 `isAllowChange`、`status` 与 Native 的 `enabled` 语义不同，不能直接当作同一字段。 | 明确字段含义后更新模型、响应和写入测试。 |
| 任务 | 任务定义和执行日志字段仍有旧名称；执行结果和删除数量需要逐项核验。 | 核验任务数组、实体写入、触发结果和日志分页。 |
| 审计、个人资料和监控 | Phoenix 返回旧日志字段、旧个人资料结构和 BEAM 监控结构；Native 使用不同 DTO。 | 按 admin-web schema 执行真实 HTTP 响应解析和权限测试。 |

因此，当前提交完成的是接口路径、方法、旧入口清理、公告特殊语义和敏感写权限边界。它还不能证明 Phoenix 可以直接替换 Native 作为 admin-web 的后端。DTO 和 Phoenix 数据模型差异必须完成后，才能给出“所有接口已对齐”的结论。

## UI 验收边界

Native 与 admin-web 的真实 HTTP 联调已经覆盖健康检查、RSA 公钥、登录、监控、角色、API Key、登出和 AAL2 step-up。admin-web 的 `pnpm test:run`、`pnpm typecheck` 和 `pnpm build` 均通过。

Phoenix LiveView 已覆盖用户、角色、部门、岗位、菜单、配置、字典、公告、日志、任务、监控、个人资料和 API Key 面板。当前没有可用的真实浏览器窗口证据；MFA 登录挑战、OIDC 按钮和 WebAuthn 页面也不是两个前端共同提供的功能，不能作为 Phoenix 单边已完成项。
