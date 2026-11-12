# Keystone Phoenix 最终认证与授权架构设计

更新日期：2026-11-12。本文件是最终架构基线，后续实现不保留菜单权限回退或双重授权来源。

## 1. 总体架构

系统将认证、授权、资源范围和审计分层：

~~~text
OIDC/OAuth2
  -> Principal
  -> RBAC 基础权限
  -> ABAC/ReBAC 数据范围
  -> Authz PDP
  -> HTTP / LiveView / Domain PEP
  -> 审计与缓存
~~~

认证回答“你是谁、会话是否有效”。授权回答“你能执行什么动作、能操作哪项资源”。菜单只负责展示入口，不承担安全边界。

## 2. 身份认证

外部身份使用 OIDC/OAuth2：

- 浏览器和移动端使用 Authorization Code + PKCE。
- 服务间调用使用 Client Credentials、mTLS 或工作负载身份。
- Access Token 短期有效，Refresh Token 轮换并可撤销。
- 每个请求验证签发方、受众、过期时间、令牌类型和会话状态。
- 认证层不根据 URL、菜单名称或前端字段授权。

## 3. Principal

所有授权决策只接受统一主体：

~~~elixir
%Principal{
  subject_id: 123,
  tenant_id: 10,
  roles: [%{id: 2, version: 7}],
  department_id: 20,
  session_id: "session-id",
  authentication_method: :oidc,
  claims: %{}
}
~~~

主体必须包含租户、角色版本、部门、会话和认证方式。is_admin 只作为最终切换前的兼容字段，最终由系统角色或显式系统能力替代。

## 4. 授权模型

### RBAC

RBAC 提供基础动作能力：

~~~text
subject -> role -> permission
~~~

权限采用稳定的 resource:action 字符串：

- system:user:list
- system:user:edit
- system:user:remove
- system:job:run
- monitor:online:forceLogout

### ABAC

ABAC 根据主体、资源和环境属性判断数据范围：

- 租户。
- 部门和部门树。
- 自定义部门集合。
- 资源所有者。
- 请求来源、时间和风险等级。

### ReBAC

ReBAC 表示主体与资源的关系：

- 用户是项目成员。
- 用户是文档所有者。
- 用户属于部门。
- 用户是任务维护者。

RBAC、ABAC、ReBAC 可以同时参与一次决策，任一层拒绝即拒绝。

## 5. PDP 与 PEP

KeystonePhoenix.Authz 是统一 PDP 适配层，未来可替换为 OPA、Cedar、SpiceDB 或 Authzed。

执行点：

1. HTTP PEP：Authenticate Plug。
2. LiveView PEP：事件入口。
3. Domain PEP：事务写入前。

统一接口：

~~~elixir
Authz.authorize(principal, permission, resource, context)
Authz.allowed?(principal, permission, context)
Authz.scope_allowed?(principal, scope, resource, context)
~~~

结果固定为：

- :ok
- {:error, :permission_denied}
- {:error, :data_scope_denied}
- {:error, :authorization_unavailable}

缺少权限映射、主体无效或资源上下文不完整时默认拒绝。

## 6. 最终数据模型

### 权限目录

sys_permission 是唯一权限目录：

~~~text
permission_id
permission unique
resource
domain
action
description
risk
status
deprecated
version
~~~

### 角色授权

sys_role_permission 是唯一角色授权关系：

~~~text
role_id
permission_id
~~~

API、LiveView、领域命令和服务账号都从这条关系读取权限。

### 菜单能力

菜单是 UI 投影，不是授权事实来源。保留 sys_role_menu 控制导航可见性，使用 sys_menu_permission 关联菜单展示所需权限。

菜单能力类型：

- page：页面入口。
- button：页面操作。
- api：没有页面入口的 API 能力。
- system：任务、刷新缓存、强制下线等系统能力。

API-only 能力可以是隐藏节点，但必须登记在 sys_permission。菜单路径和排序变化不能改变角色实际拥有的 API 权限。

### 数据范围

统一支持：

- all
- tenant
- department
- department_tree
- custom_departments
- self
- owner
- member

批量操作必须逐个检查目标，任一目标越界时整个事务回滚。

## 7. 各入口规则

### HTTP

Controller 只声明权限映射：

~~~elixir
permissions: %{
  update: "system:user:edit",
  delete: "system:user:remove"
}
~~~

Plug 调用 Authz。Controller 不自行实现管理员例外，也不从菜单表读取 API 权限。

### LiveView

菜单和按钮显隐只是展示优化。事件执行前必须再次调用 Authz。

### Domain

所有写命令接收主体授权上下文：

~~~elixir
User.update_user(user_id, attrs,
  authorization: %{
    principal: principal,
    permission: "system:user:edit"
  }
)
~~~

领域层在事务内检查权限、数据范围、资源关系和批量目标。只传 actor_id 的写入口删除。

## 8. 缓存与审计

策略缓存键包含：

~~~text
policy_version:tenant_id:role_id:permission
~~~

权限目录、角色权限、角色状态、用户角色、数据范围或菜单能力变更时递增版本并清理缓存。缓存或策略存储不可用时管理写操作默认拒绝。

授权审计记录：

- subject_id
- session_id
- tenant_id
- permission
- resource_type
- resource_id
- scope
- decision
- reason
- request_id
- created_at

不记录密码、Token、验证码、完整请求参数、文件内容或敏感 Claim。

Telemetry 事件：

~~~text
[:keystone_phoenix, :authz, :decision]
~~~

至少统计允许、权限拒绝、数据范围拒绝和策略不可用。

## 9. 一步到位实施计划

1. 建立最终权限目录、角色权限和菜单能力关联。
2. 将登录权限列表、菜单树、HTTP、LiveView 和 Domain 全部切换到规范化模型。
3. 删除 sys_menu.permission 授权读取和所有旧回退逻辑。
4. 删除只传 actor_id 的写入口。
5. 启用版本化缓存、授权审计和拒绝原因指标。
6. 执行迁移前数据检查、重复迁移、越权回归和三入口一致性测试。

本次迁移允许破坏性更新。执行前必须完成数据库备份、权限冲突检查和迁移演练；迁移失败时停止发布，不自动降级到旧授权模型。
