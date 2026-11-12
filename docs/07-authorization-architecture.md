# Keystone Phoenix 授权架构设计

更新日期：2026-11-12。本文是后续授权改造的设计基线。当前系统继续使用已有的角色、菜单权限字符串和数据范围；实现按本文逐步收敛到统一授权决策服务。

## 实施状态

阶段一的兼容切片已经落地：`KeystonePhoenix.Authz`、`Principal` 和 `PolicyStore` 已建立，策略读取继续适配现有 `sys_role`、`sys_menu` 和 `sys_role_menu` 表。HTTP Authenticate Plug、管理 LiveView、角色/菜单元数据控制器和用户导入入口的权限、管理员识别、角色分配及用户数据范围判断都通过 Authz API；保留原有 `40302` 和 `40303` 错误码。用户 LiveView 的保存、状态切换、删除和密码重置事件会在写入前检查目标范围，并按当前主体范围刷新列表。用户和角色的范围查询也经由 Authz 的查询适配器，避免业务查询直接依赖旧策略模块。阶段二已为用户、角色、部门、岗位、配置、字典、公告和任务写命令增加主体授权选项，HTTP 与管理 LiveView 已传递主体和权限上下文；个人资料、改密和头像更新也增加了主体自身范围检查。通用上传资源使用用户所有者命名空间，受保护资源只允许所有者或管理员访问。

本阶段仍保留旧领域函数签名和布尔兼容入口，便于逐步迁移直接领域调用。权限目录兼容验证、规范化权限表、策略存储异常返回、版本化策略缓存、主体自身范围判断、授权决策 Telemetry 和持久化审计已加入。

## 目标

授权系统需要同时回答两个问题：

1. 当前主体是否拥有执行某个动作的权限字符串？
2. 当前主体是否有权访问或修改目标资源？

RBAC 负责主体与角色、角色与权限的关系。数据范围负责目标资源边界。接口路径、LiveView 事件和领域命令都必须经过同一套授权语义，默认拒绝，失败时返回稳定的权限或数据范围错误。

架构保留现有 HTTP 路径、响应字段和权限字符串，逐步替换散落在控制器、LiveView 和领域模块中的重复判断。现有 `sys_role`、`sys_menu` 和 `sys_role_menu` 是第一阶段的策略存储，不立即进行破坏性迁移。

## 核心模型

### 主体

`Principal` 表示发起操作的主体，当前包括本地用户和管理员用户。后续可以扩展服务账号，但服务账号必须明确绑定角色或机器权限，不能通过特殊分支绕过策略。

主体上下文至少包含：

- `subject_id`：用户 ID 或服务主体 ID。
- `roles`：有效角色及角色版本。
- `is_admin`：系统级管理员标志，仅作为最高级 RBAC 角色的兼容字段。
- `department_id`：主体所属部门。
- `session_id`：当前认证会话，用于审计和会话失效检查。

### 权限

权限字符串采用稳定的 `resource:action` 形式，例如：

- `system:user:list`
- `system:user:edit`
- `system:user:remove`
- `system:dict:refresh`
- `monitor:online:forceLogout`

权限字符串代表动作能力，不代表具体 URL。一个动作可以被多个 HTTP 路径或多个 LiveView 事件调用；入口只负责提取资源和上下文，授权服务负责决策。

权限目录应逐步从菜单记录中的自由文本收敛为可审计的权限目录。第一阶段继续读取 `sys_menu.permission`，新增或修改权限元数据必须经过权限元数据专属权限，避免普通业务写权限植入新的授权标识。

### 数据范围

数据范围是动作通过权限字符串检查后的第二层判断：

- `all`：所有资源。
- `department`：主体当前部门。
- `department_tree`：当前部门及下级部门。
- `custom_departments`：角色配置的部门集合。
- `self`：主体自身资源。

数据范围判断必须基于数据库查询或目标资源快照，不能只依赖客户端列表。批量操作必须对所有目标逐一检查，任何一个目标越界时整批失败并回滚。

## 目标架构

### 统一授权决策点

新增 `KeystonePhoenix.Authz` 作为唯一授权入口，提供以下接口：

```elixir
Authz.authorize(principal, "system:user:edit", resource, context)
Authz.allowed?(principal, "system:user:list", context)
Authz.scope_allowed?(principal, :user, user_id, context)
```

返回值保持简单且可组合：

- `:ok`
- `{:error, :permission_denied}`
- `{:error, :data_scope_denied}`
- `{:error, :authorization_unavailable}`

授权服务只负责策略判断，不执行领域写入。领域命令在事务边界内再次调用授权服务，防止绕过 HTTP 或 LiveView 直接调用领域函数。

### 策略存储与缓存

第一阶段使用现有表结构：

- `sys_role`：角色状态、数据范围和部门集合。
- `sys_menu`：权限字符串目录和菜单元数据。
- `sys_role_menu`：角色到权限字符串的绑定。
- `sys_user.role_id`：用户当前角色。

后续可增加规范化的 `sys_permission` 和 `sys_role_permission` 表，将菜单展示与动作授权分离。迁移期间由 `PolicyStore` 同时读取旧菜单权限和新权限目录，决策结果保持一致。

权限和角色策略可以使用 ETS 做节点内缓存，但缓存键必须包含角色或权限版本。角色、菜单、角色菜单、用户角色和数据范围变更时必须使相关版本递增并清理缓存；缓存不可用时默认拒绝管理写操作。

### 三个强制执行点

1. **HTTP Plug**：认证后提取 `principal`，按 Phoenix action 映射权限字符串和资源参数，调用 `Authz.authorize/4`。
2. **LiveView 事件入口**：所有管理事件先检查具体权限字符串，再检查目标资源和数据范围。面板可见性只决定是否显示入口，不承担动作授权。
3. **领域命令**：接收 `principal` 或授权上下文，在事务内检查目标资源。现有接收 `actor_id` 的函数逐步增加兼容重载，旧调用方迁移完成后移除只传 ID 的写入口。

## 入口约定

### HTTP

控制器声明动作到权限字符串的映射，Plug 负责统一校验：

```elixir
permissions: %{
  update: "system:user:edit",
  delete: "system:user:remove"
},
data_scope: %{
  update: {:user_update, "user_id"},
  delete: {:users, "user_ids"}
}
```

控制器不再自行决定管理员例外。管理员通过 RBAC 角色获得全量权限和 `all` 数据范围；兼容性的 `is_admin` 只在策略存储迁移期间映射为系统管理员角色。

### LiveView

事件名称不是权限。事件必须显式映射到权限字符串，例如：

| LiveView 事件 | 权限字符串 | 数据范围 |
| --- | --- | --- |
| `save-user` | `system:user:add` 或 `system:user:edit` | 创建部门、更新用户 |
| `toggle-user-status` | `system:user:edit` | 目标用户 |
| `delete-user` | `system:user:remove` | 目标用户 |
| `reset-user-password` | `system:user:resetPwd` | 目标用户 |
| `run-job` | `system:job:run` | 任务资源 |
| `force-logout` | `monitor:online:forceLogout` | 在线会话 |

事件成功后重新加载数据时必须使用当前主体的数据范围。禁止使用无主体参数的全量加载函数向普通用户返回列表。

### 领域层

领域层接收授权上下文的推荐形态：

```elixir
User.update_user(user_id, attrs, principal: principal, permission: "system:user:edit")
```

授权失败必须在写入前返回，批量命令必须将授权检查和写入放入同一个事务。审计日志记录主体、权限字符串、资源 ID、数据范围、结果和拒绝原因，但不记录密码、令牌、验证码或服务器路径。

## 迁移步骤

### 阶段一：统一决策 API（已完成兼容切片）

- 新增 `Authz`、`Principal` 和 `PolicyStore`，兼容读取现有角色菜单权限。
- 将 `Authenticate` Plug 的权限和数据范围判断改为调用 `Authz`。
- 将 LiveView 的 `permission_socket?` 和目标范围判断改为调用 `Authz`。
- 将角色/菜单元数据、角色分配和用户/角色范围查询改为通过 `Authz` 的策略适配器。
- 保留现有错误码：权限拒绝 `40302`，数据范围拒绝 `40303`。

### 阶段二：领域写入收口（主要业务写入已迁移）

- 用户写命令已增加 `authorization: %{principal: principal, permission: permission}` 入口，并在领域写入前检查权限、目标数据范围和角色分配；个人资料、改密和头像命令使用主体自身范围检查。
- 部门、岗位、角色、菜单、配置、字典、公告和任务写命令已增加主体上下文，旧 actor ID 调用保留为短期兼容入口。
- 删除、状态切换、密码重置、角色分配和批量导入统一检查目标范围。
- 保留旧函数作为短期兼容入口，并在调用路径迁移完成后标记为内部函数。

### 阶段三：权限目录规范化（已完成兼容迁移）

- 建立权限目录，记录资源、动作、描述、风险等级和废弃状态；`sys_permission` 与 `sys_role_permission` 已建立并回填旧菜单权限。
- 将 `sys_menu.permission` 映射到权限目录，检测重复、空值和未登记权限；运行时优先读取规范化绑定，目录缺失时兼容旧菜单策略。
- 角色编辑只允许绑定已登记权限；权限目录变更写入审计日志。

### 阶段四：缓存、审计和验证（核心切片已完成）

- 为角色、权限和数据范围增加版本号与 ETS 缓存失效机制；角色和菜单写入会使策略版本递增。
- 增加授权决策审计事件和拒绝原因指标；当前已发出 `[:keystone_phoenix, :authz, :decision]` Telemetry 事件，并写入脱敏授权操作日志。
- 建立每个权限入口的五类契约测试：成功、未登录、无权限、参数错误、目标不存在或越界。
- 增加 HTTP、LiveView、领域直调三条路径的越界回归测试，保证入口不同但决策一致。

## 当前切片与回滚

当前已完成统一决策 API、领域写入收口、资源所有者隔离、规范化权限读取、版本化策略缓存和授权审计观测：拥有 `system:user:edit` 等权限字符串的非管理员用户仍必须通过角色数据范围检查，成功刷新使用范围内列表；直接领域调用缺少权限、目标越界或资源所有者不匹配时会在写入/读取前拒绝。`Authz` 单元测试、规范化策略回归、缓存失效回归、审计脱敏回归、领域直调回归、LiveView 越界回归、资源路径回归、Telemetry 事件测试和 HTTP 集成授权测试均已通过。该切片增加权限目录表及其回填迁移，保留旧菜单策略兼容读取；回滚时优先回退策略适配层，不回退已经写入的业务数据和审计记录。

每个迁移阶段单独提交和推送。策略存储迁移先读旧表再写新表，保留向后兼容读取；出现问题时回退策略读取适配层，不回退已经写入的业务数据和审计记录。
