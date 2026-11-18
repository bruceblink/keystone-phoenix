# 跨项目业务错误码目录

更新日期：2026-11-18。

本文是 `keystone-phoenix`、`keystone-native` 和 `keystone-admin-web` 共用的业务错误码目录。Phoenix 的 `KeystonePhoenixWeb.ErrorCatalog` 保存目录项；Native 的 `app.keystone.ErrorCode` 和 admin-web 的 `BUSINESS_ERROR_CATALOG` 必须保持相同的服务端代码集合和默认 HTTP 状态。

## 术语与命名规则

| 名称 | 英文或标识符 | 职责 | 不负责的内容 |
| --- | --- | --- | --- |
| 业务错误码 | business error code | 标识一个可反查的业务条件，供接口响应、日志和排错使用 | 不替代 HTTP 状态，也不承载可读提示全文 |
| HTTP 状态码 | HTTP status code | 表示本次接口结果的传输状态和既有接口约定 | 不用来反向推断唯一业务条件 |
| 目录反查 | catalog lookup | 按错误码查找业务条件、默认状态和处理建议 | 不从 `message` 文本猜测错误码 |
| `legacy` 兼容代码 | legacy compatibility code | 在已列出的旧边界继续保持外部兼容 | 新入口不得继续扩大使用范围 |
| 客户端本地错误码 | client-local error code | 表示网络、响应解析或前端状态机失败 | 不作为服务端 `error.code` 发布 |

代码使用小写 `snake_case`。同一个代码只能对应一个业务条件。可读 `message` 可以按界面语言变化，但不能改变代码含义。

## 统一接口规则

1. 服务端响应使用 `{success, data, message, error}`；失败响应的 `error.code` 必须来自本目录。
2. 目录项的 `httpStatus` 或 `status` 是该业务条件的默认记录。接口迁移时必须保持原 HTTP 状态；替换代码不能同时改变状态，除非另有独立接口变更记录。
3. 调用方先按错误码反查业务条件，再按 HTTP 状态处理认证、重试或页面反馈。不能把同一个状态（例如 `503`）当作一个业务错误码。
4. 领域层内部原子错误可以不同。边界层负责把内部结果映射为本目录代码；内部原子错误名称不直接发布给客户端。
5. `retryable` 只表示处理建议。它不授权对有副作用的请求进行盲目重试；调用方仍需遵守幂等性、退避和用户确认规则。

## 规范服务端错误码

| 代码 | 默认 HTTP 状态 | 可反查的业务条件 | 处理建议 |
| --- | ---: | --- | --- |
| `authentication_required` | 401 | 请求没有有效认证信息 | 先完成登录或认证，不自动重复原请求 |
| `invalid_credential` | 401 | 凭据无效、过期或不能通过核验 | 修正凭据或重新登录 |
| `mfa_required` | 401 | 当前操作需要完成多因素认证 | 完成 MFA 后重新提交 |
| `mfa_invalid_code` | 401 | MFA 验证码不正确 | 重新输入有效验证码 |
| `mfa_step_up_required` | 403 | 当前敏感操作需要近期的 MFA 升级 | 完成 step-up 后重新提交 |
| `mfa_state_conflict` | 409 | MFA 当前状态不允许该操作 | 先修正或完成 MFA 状态 |
| `mfa_challenge_invalid` | 401 | MFA 请求不存在、已过期或已被消费 | 重新开始认证请求 |
| `active_session_conflict` | 409 | 账号已有活动会话，需要用户选择继续策略 | 明确取消或确认接管后再提交 |
| `permission_denied` | 403 | 主体没有执行该操作的权限 | 不重试，改用有权限的主体或操作 |
| `data_scope_denied` | 403 | 主体不能访问目标数据范围 | 不重试，调整数据范围或主体 |
| `session_revoked` | 401 | 当前会话已撤销或失效 | 清理会话并重新登录 |
| `resource_not_found` | 404 | 请求的资源不存在或按安全策略不可见 | 检查资源标识，不重复提交相同请求 |
| `resource_conflict` | 409 | 资源状态或唯一约束与本次操作冲突 | 刷新状态并修正请求 |
| `role_has_members` | 422 | 角色仍分配给未删除用户，不能删除 | 移除用户的主角色或关联角色后重试 |
| `role_protected` | 422 | 系统管理员角色受保护，不能删除 | 保留系统管理员角色 |
| `rate_limited` | 429 | 请求频率超过当前限制 | 按 `Retry-After` 或退避时间重试 |
| `precondition_required` | 428 | 缺少继续操作所需的前置条件 | 先完成前置条件 |
| `payload_too_large` | 413 | 请求内容超过接口允许大小 | 缩小请求内容后重试 |
| `https_required` | 426 | 请求必须通过 HTTPS 传输 | 切换到 HTTPS 后重试 |
| `validation_failed` | 422 | 参数、格式或业务规则校验失败 | 修正字段或业务输入 |
| `password_same_as_current` | 422 | 新密码与已验证的当前密码相同 | 选择与当前密码不同的新密码 |
| `password_required` | 422 | 必填密码入口的密码缺失、为 null、空字符串或只包含 Java 空白字符 | 输入非空白密码 |
| `password_too_short` | 422 | 密码的 Unicode code point 数量小于配置的最小长度 | 增加密码长度 |
| `password_disallowed` | 422 | 密码与不区分大小写的禁用列表项相同 | 选择不在禁用列表中的密码 |
| `password_contains_username` | 422 | 密码包含长度至少为 4 个 Java UTF-16 code unit 的用户名 | 选择不包含用户名的密码 |
| `password_missing_uppercase` | 422 | 策略要求大写字母，但密码没有大写字母 | 添加大写字母 |
| `password_missing_lowercase` | 422 | 策略要求小写字母，但密码没有小写字母 | 添加小写字母 |
| `password_missing_digit` | 422 | 策略要求十进制数字，但密码没有数字 | 添加数字 |
| `password_missing_special` | 422 | 策略要求特殊字符，但密码只含字母和十进制数字 | 添加特殊字符 |
| `api_key_name_invalid` | 422 | API Key 名称缺失、空白或超过 128 个字符 | 输入 1 到 128 个字符的名称 |
| `profile_display_name_required` | 422 | 个人资料展示名缺失或为空白 | 输入展示名后重试 |
| `profile_avatar_required` | 422 | 单独更新头像时地址缺失或为空白 | 输入头像地址后重试 |
| `api_key_expiry_invalid` | 422 | API Key 到期时间格式无法解析 | 重新选择有效的到期时间 |
| `api_key_expiry_out_of_range` | 422 | API Key 到期时间不晚于当前时间或超过 90 天 | 选择当前时间之后、90 天以内的时间 |
| `api_key_expired` | 409 | 已过期的 API Key 不能轮换 | 新建 API Key |
| `service_unavailable` | 503 | 服务暂时不能处理请求，但不属于特定授权状态 | 按退避策略重试 |
| `authorization_unavailable` | 503 | 认证、授权或其依赖状态暂时不可用 | 按退避策略重试；见兼容范围 |
| `internal_error` | 500 | 未分类的服务端处理失败 | 记录请求标识，避免盲目重复有副作用的请求 |

目录当前包含 37 个代码。密码策略按固定顺序返回第一个失败规则：密码缺失、长度不足、命中禁用列表、包含用户名、缺少大写字母、缺少小写字母、缺少数字、缺少特殊字符。密码创建、用户资料更新、密码重置、个人改密、首次改密和 Excel 用户导入都保留这些专用代码，并保持原有 `422` HTTP 状态。用户资料更新中缺失、`null`、空字符串或仅 Java 空白字符的可选密码会被忽略；非空密码会经过相同策略检查。用户资料更新失败时，资料、密码和会话都保持不变。成功更新密码时，现有会话继续有效，和 Native 一致。API Key 签发使用独立代码区分名称错误、到期时间格式错误和到期范围错误，三种情况都保持原有 `422` HTTP 状态。角色删除使用 `role_has_members` 和 `role_protected` 区分两种不可删除条件；它们也保持原有 `422` HTTP 状态。`resource_conflict` 仍用于其他资源冲突。`https_required`、`mfa_state_conflict` 和 `mfa_invalid_code` 也是规范代码，不属于客户端本地代码。

## `legacy` 兼容范围

### `authorization_unavailable`

`authorization_unavailable` 保留用于尚未完成边界迁移的暂时不可用结果。当前允许的旧边界包括：

- Phoenix 的旧限流服务失败、JWK、Passkey、OIDC、任务、监控、个人资料、用户认证会话和 API Key 授权服务映射；领域授权存储或策略服务返回的不可用结果也由边界映射到此代码。
- Native 的认证会话、JWK、OIDC、WebAuthn、MFA 状态、权限拦截器和数据范围服务的旧不可用映射。

这些边界继续返回原有 `503` 状态。迁移到更具体的代码时，只替换 `error.code`，不改变 HTTP 状态。新的入口应优先使用 `service_unavailable` 或其他能准确反查业务条件的代码。`authorization_unavailable` 不表示“任意 503”，也不能作为新增入口的通用兜底。

### 前端输入兼容

admin-web 只把 `invalid_credential` 作为当前服务端凭据错误码。旧客户端可能发送或接收 `invalid_credentials`（复数）；该字符串只能保留在旧 MFA 处理的兼容分支，不能加入 `SERVER_ERROR_CODES`，也不能由新接口发布。

## 项目实现映射

| 项目 | 目录实现 | 反查入口 | 约束 |
| --- | --- | --- | --- |
| Phoenix | `lib/keystone_phoenix_web/error_catalog.ex` | `ErrorCatalog.lookup/1`、`ErrorCatalog.metadata/1`、`ErrorCatalog.valid?/1` | `lookup` 返回代码和业务条件；`ApiResponse.error/3` 拒绝未登记代码；`status` 保持接口现有值 |
| Native | `src/main/java/app/keystone/ErrorCode.java` | `ErrorCode.find(String)`、`ErrorCode.fromCode(String)`、`ErrorCode.isRegistered(String)` | `find` 返回可区分未知代码的目录项；`httpStatus()` 只记录默认状态，资源入口决定实际响应状态 |
| admin-web | `src/shared/api/errors.ts` | `lookupBusinessError(code)`、`getBusinessErrorDefinition(code)`、`SERVER_ERROR_CODES` | `lookupBusinessError` 返回代码和业务含义；`ApiError` 原样保留服务端状态和代码；客户端本地代码放在 `CLIENT_ERROR_CODES` |

admin-web 不执行授权判断，也不根据代码重写 HTTP 状态。页面只使用反查结果生成安全提示和诊断标识。

## 静态一致性检查

`keystone-phoenix/scripts/check_error_code_catalog.py` 只读取三个仓库的源码和本文表格。它不启动运行时，不连接数据库，也不调用接口。检查内容如下：

- 目录表格仍为 37 个代码，并且每个代码只有一行和一个默认状态。
- Phoenix、Native 和 admin-web 的服务端代码集合与目录完全相同，没有重复项或遗漏项。
- Phoenix 和 Native 的状态值与目录一致。
- admin-web 的 `BUSINESS_ERROR_CATALOG`、`SERVER_ERROR_CODES` 和安全可读提示覆盖全部规范代码。
- 三个实现都保留代码到业务条件的反查入口；`CLIENT_ERROR_CODES` 不混入服务端目录。

在三个仓库的父目录执行：

```sh
python3 keystone-phoenix/scripts/check_error_code_catalog.py \
  --native-root keystone-native \
  --admin-root keystone-admin-web
```

脚本失败时先修正目录或文档，再运行项目自身测试。静态检查通过不能替代真实 HTTP、数据库、浏览器或生产代理验收。
