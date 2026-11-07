# Keystone Phoenix 代码审查记录

审查日期：2026-11-07。代码基线：`455cf82`。

## 范围与结论

本轮将当前 `main` 从 `1fd08b5` 快进到远端 `455cf82`，同步 47 个提交。同步前工作区干净，没有改写提交历史。审查范围包括认证、会话、权限、领域数据、文件、Excel、LiveView、定时任务、部署和测试配置。

本轮没有重新审查 Java 项目或运行旧前端，也不是一次完整安全扫描。下面的问题来自当前 Phoenix 源码与测试的调用链检查。除验证部分明确说明的复现外，不把静态结论描述为运行测试通过。

现有模块覆盖了主要功能，但认证、授权和常用操作仍有明确缺陷。应先关闭 P1 问题，再完成发布前检查。旧报告中的“功能完成”和历史测试通过记录不能证明 `455cf82` 已通过本轮验收。

后续执行顺序、验收命令和回滚边界见 [`01-development-plan.md`](01-development-plan.md)。本轮只提交这两份文档，不修改业务实现。

## 已确认问题

### R01｜P1：重复登录会话冲突缺少错误分支

位置：[`auth.ex:125`](../lib/keystone_phoenix/auth.ex#L125)，相关入口为 `AuthController.login/2` 和 `LoginLive.handle_event/3`。

- 同一账号已有有效会话时，`Session.occupy/4` 返回 `{:error, :already_logged_in}`。
- `issue_pair/2` 的 `with ... else` 只处理密钥配置错误和服务不可用，没有匹配该值，会抛出 `WithClauseError`。
- 外层 `login_plaintext/3` 的元组匹配不会捕获异常。HTTP 不能返回已有的 `409/10210`；LiveView 登录事件也可能终止连接。
- 测试只直接验证 `Session.occupy/4` 的冲突结果，没有经真实登录入口连续登录两次。

关闭条件：重复登录返回已有错误，LiveView 连接保持有效，原会话不被破坏；强制登录仍替换原会话。

### R02｜P1：用户读写入口没有完整应用数据范围

位置：[`user_controller.ex:17`](../lib/keystone_phoenix_web/controllers/user_controller.ex#L17)、[`user.ex:40`](../lib/keystone_phoenix/user.ex#L40)、[`authenticate.ex:73`](../lib/keystone_phoenix_web/plugs/authenticate.ex#L73)。

- `show` 和 `export` 有操作权限检查，但没有目标数据范围检查。持有对应权限的受限用户可以查询范围外用户，或导出未按范围过滤的数据。
- `update` 只检查目标用户当前所属范围。请求中的新 `deptId` 只校验部门存在，因而可以把范围内用户移动到范围外部门。
- 列表把可选 `deptId` 当作必须通过部门范围检查的目标。仅本人范围不能通过该检查；其他受限范围省略部门时也无法自然取得授权集合。
- `User.list_users/1` 只接受客户端筛选条件，没有当前操作人的范围查询。LiveView 又先取全局最新 50 条再过滤，可能遗漏较早的范围内用户。
- `import` 同样未配置范围检查。目前普通 HTTP 导入先受 R06 阻断；修复 R06 后，若不同时补齐逐行授权，就会开放范围外导入。当前不能声称普通 multipart 上传已成功触发此写入。

补充决策：`roleId` 当前只校验角色存在，未定义受限用户可分配哪些角色。需要明确分配规则，再为创建、更新、导入和批量授权增加拒绝测试。没有业务规则证据时，不将所有角色编辑行为一概认定为越权。

关闭条件：范围 1–5 的查询、总数、分页、详情、导出和写入一致；越界写入不改变数据库；超过 50 条用户时仍能查到允许范围内的较早记录。

### R03｜P1：LiveView 继续信任已经失效的登录快照

位置：[`admin_support.ex:479`](../lib/keystone_phoenix_web/live/admin_support.ex#L479)、[`login_live.ex:238`](../lib/keystone_phoenix_web/live/login_live.ex#L238)。

- 登录把用户、权限和令牌保存到 socket。后续 `admin_socket?/1` 与 `authenticated_socket?/1` 只检查旧赋值，不重新验证会话和账号状态。
- 管理员连接建立后，另一入口撤销会话、强制下线、停用账号或修改权限，旧连接仍可向领域函数提交管理操作。
- HTTP 每次调用 `Auth.authenticate_access_token/1`，会重新查询活跃会话和账号状态；LiveView 没有采用同样的失效检查。
- 现有集成测试覆盖正常管理员操作，但没有验证另一入口撤销后的事件。实现只在当前连接主动停用自身或修改自身密码等少数事件中清除认证状态。

关闭条件：已有连接在会话撤销、停用、密码重置、权限变更和到期后不能继续执行受保护操作；下一次操作明确失败并清理认证状态，不写数据库。

### R04｜P1：LiveView 登录绕过验证码开关

位置：[`login_live.ex:96`](../lib/keystone_phoenix_web/live/login_live.ex#L96)、[`auth.ex:15`](../lib/keystone_phoenix/auth.ex#L15)。

- HTTP 登录先调用 `Captcha.validate/2`；LiveView 直接调用 `Auth.login_plaintext/3`。
- 即使配置开启验证码，LiveView 表单也只提交用户名和密码。因此同一账号可从页面入口绕过 HTTP 登录要求。
- 现有验证码测试验证生成与消费，没有覆盖验证码开启后的 LiveView 登录。

关闭条件：两种入口遵守同一验证码策略；缺失、错误、过期及已消费的验证码均拒绝登录。领域层明文入口只供已完成入口检查的调用方使用。

### R05｜P1：限流记录到期后没有建立新窗口

位置：[`rate_limiter.ex:25`](../lib/keystone_phoenix/rate_limiter.ex#L25)。

- `check/3` 先计算新的 `expires_at`，但过期分支的模式又把同名变量绑定为表中的旧值。
- 该分支将旧到期时间写回。下一次串行请求仍进入过期分支并放行，直到周期清理删除这条记录。
- `/getConfig`、`/captchaImage`、RSA 公钥入口和公告防重复提交共同使用该实现。现有测试只覆盖首个未到期窗口。

关闭条件：过期后的首个请求建立未来到期时间，后续请求受正常限额约束；覆盖清理前后和同键并发请求。

### R06｜P2：正常 multipart Excel 上传被临时路径检查拒绝

位置：[`user_controller.ex:165`](../lib/keystone_phoenix_web/controllers/user_controller.ex#L165)、[`excel.ex:129`](../lib/keystone_phoenix/excel.ex#L129)。

- 控制器将 `upload.path` 传给 `Excel.import_rows/1`，而文件校验要求该路径扩展名是 `.xlsx`。
- 当前 Plug multipart 实现用 `Plug.Upload.random_file!("multipart")` 创建临时文件。生成路径不带客户端文件扩展名，客户端原名另存在 `upload.filename`。
- 因此普通 `.xlsx` 上传在解析工作簿前被拒绝。Excel 单元测试自行创建 `.xlsx` 路径，无法覆盖真实上传。

关闭条件：通过真实 multipart 解析成功导入合法工作簿；无效内容和超限文件仍被拒绝，并同时通过 R02 的逐行授权测试。

### R07｜P2：部分 LiveView 编辑表单清空 ID，字段使用不一致

位置：

- [`admin_events_system.ex:43`](../lib/keystone_phoenix_web/live/admin_events_system.ex#L43)：配置编辑用默认表单覆盖已有记录，清空 `configId`、名称、键和值。
- [`admin_events_organization.ex:228`](../lib/keystone_phoenix_web/live/admin_events_organization.ex#L228)：角色编辑有同样的覆盖方向问题。
- [`admin_events_organization.ex:370`](../lib/keystone_phoenix_web/live/admin_events_organization.ex#L370)：菜单编辑有同样的问题。

保存事件依靠 ID 是否为空区分创建和更新。点击这些编辑按钮后，页面实际进入了创建状态，无法按原 ID 完成更新。现有集成测试主要提交新建表单，没有覆盖这些编辑按钮后的保存。

同一切片还需关闭以下字段问题：

- 字典输出 `isDefault=0/1`，页面和编辑事件使用普通真假判断。在 Elixir 中 `0` 为真，因此“非默认”会显示或回填为“默认”。位置：[`admin_events_system.ex:224`](../lib/keystone_phoenix_web/live/admin_events_system.ex#L224)、[`admin_pages/system.ex:76`](../lib/keystone_phoenix_web/live/admin_pages/system.ex#L76)。
- 操作日志输出 `operationId`，删除按钮却取 `operId` 或 `id`，不能传递正确目标。位置：[`admin_pages/system.ex:126`](../lib/keystone_phoenix_web/live/admin_pages/system.ex#L126)。
- 任务日志输出 `endTime`，页面使用 `stopTime`，结束时间为空。位置：[`admin_pages/operations.ex:45`](../lib/keystone_phoenix_web/live/admin_pages/operations.ex#L45)。

关闭条件：点击编辑后原 ID 和值保持正确；提交只修改原记录，不增加行；字典默认值、删除目标和任务结束时间经真实字段测试确认。

### R08｜P2：普通用户的面板入口和只读交互不完整

位置：[`admin_support.ex:120`](../lib/keystone_phoenix_web/live/admin_support.ex#L120)、[`admin_support.ex:492`](../lib/keystone_phoenix_web/live/admin_support.ex#L492)、[`login_live.ex:220`](../lib/keystone_phoenix_web/live/login_live.ex#L220)。

- `panel_access/2` 将 `profile`、`overview` 设为可见，但 `panel_allowed?/2` 不认识这两个键，普通用户点击个人资料或概览会被拒绝。登录后默认显示概览不代表切换事件有效。
- 普通用户可见的列表刷新和字典选择事件仍大多只允许管理员，显示的按钮无效。
- 监控权限可以让普通用户看到入口，但首次进入不加载数据，刷新事件也只允许管理员。这里是功能缺失，不是已确认的监控数据泄露。
- 全部管理表单当前按管理员身份决定可写。是否让拥有写权限的普通角色使用 LiveView 写操作，应单独确定；本轮不擅自扩大写权限。

关闭条件：普通用户可以打开个人资料；单项读取权限只加载并刷新允许的数据；未授权事件仍拒绝。补充普通用户端到端交互测试，而不只测试面板显隐 helper。

### R09｜P2：批量角色分配失败时存在部分写入

位置：[`role.ex:200`](../lib/keystone_phoenix/role.ex#L200)、[`role.ex:217`](../lib/keystone_phoenix/role.ex#L217)、[`role.ex:256`](../lib/keystone_phoenix/role.ex#L256)。

- 分配和取消先执行 `Repo.update_all`，之后才检查更新数是否等于请求 ID 数。
- 请求同时包含存在与不存在的有效整数 ID 时，存在用户已经更新，函数却返回 `{:error, :not_found}`。未使用事务回滚这次部分写入。
- 角色分配有单用户成功路径测试，但没有混合目标失败时的原子性测试。

关闭条件：任一用户不存在或已软删除时，分配与取消均不修改整批用户；全部有效时才提交。

## 待验证事项

### V01：认证刷新和任务执行的并发行为

`Auth.refresh/1` 在多个步骤中校验旧会话、删除旧会话和创建新会话。`Session.occupy/4` 的用户级数据库事务锁只覆盖占用步骤，不覆盖完整刷新。需要真实数据库并发测试确认轮换、撤销和失败后的状态，不能将占用测试当作完整刷新测试。

`Job.run_job/1` 同步调用 `Runner.run/2`；HTTP 手动执行和 LiveView 手动任务没有注册到调度器的 `running` 状态。自动调度的超时、取消与禁止并发机制不等于所有执行入口共享这些限制。先明确预期，再测试手动与自动执行重叠、取消、超时、进程异常、资源上限和日志失败。

### V02：部署和发布验证

测试工作流与镜像发布工作流独立。镜像发布工作流未声明必须等待测试成功，也没有实际容器启动检查。因此构建成功不能证明该提交通过集成或发布验收。

本轮不发布、不监测 GitHub Actions。后续需要使用实际构建镜像验证迁移、受控初始化、就绪、认证、文件持久化及备份恢复。`0.3.0` 是代码版本，不代表已经创建或验证了 `v0.3.0` 发布。

## 已核查的实现边界

- HTTP access token 校验包含签名、类型、有效期、`sid` 对应的活跃会话和账号状态。
- 菜单权限按精确字符串匹配，已停用或删除的角色、菜单不授予 HTTP 权限。
- `Session.occupy/4` 使用 PostgreSQL 用户级事务锁和活跃会话唯一索引，串行处理同账号会话占用；这不代表刷新全过程已经验证。
- 部门移动在同一事务内更新本部门与后代的 `ancestors`；角色菜单替换在事务内检查目标后执行。
- 本轮按仓库 Mix 任务的计数口径扫描 138 个 Elixir 源文件，均不超过 600 行；最大文件为 `login_live.ex`，553 行，计入末尾空行。

## 本轮验证记录

### 工具与本地服务

- WSL 发行版：`Ubuntu-24.04`。Docker Engine：`29.1.3`。构建使用 Elixir/Mix `1.20.5` 和 Erlang/OTP `29.1.2`。
- 已有 `keystone-persistent-postgres` 使用 `postgres:17-alpine`，映射端口 `15432`，容器运行且 `pg_isready` 接受连接。本轮只读取状态，没有执行数据写入，没有创建或停止任何容器。
- 仓库和 CI 使用 PostgreSQL 18。WSL 没有缓存 `postgres:18` 镜像，本轮没有拉取新镜像或复用现有开发库。默认测试配置的 `localhost:5432` 没有测试实例，因此未完成数据库和完整集成测试。Docker 本身可用，不能将测试缺口归因于 Windows 缺少 Docker。
- `mix deps.get` 按既有锁文件获取缺失依赖，`mix.lock` 没有变化。Windows 编译曾因 bcrypt 本地扩展缺少 C 头文件失败，后续改用 WSL 并完成严格编译。

### 已完成检查

在 WSL 项目目录执行：

```bash
mix format --check-formatted
mix check.source_lines
MIX_ENV=dev mix compile --warnings-as-errors
```

三项均通过。严格编译退出码为 `0`；工具输出仍有部分第三方依赖和旧配置的弃用警告，不据此声称依赖没有维护问题。本轮没有修改或压低警告配置。

单独执行不依赖数据库的 `test/keystone_phoenix/excel_test.exs`，3 项通过。执行方式如下，它不运行默认 `mix test` 的数据库别名，也不加载数据库测试环境：

```bash
MIX_ENV=test mix run --no-start --no-compile --no-deps-check -e \
  'ExUnit.start(autorun: false); {:ok, _} = Application.ensure_all_started(:xlsxir); Code.require_file("test/keystone_phoenix/excel_test.exs"); ExUnit.run()'
```

这 3 项只证明现有 Excel 单元测试通过，不证明真实 multipart 导入可用。

### 缺陷复现与未完成项

- R05：加载真实 `RuntimeStore` 和 `RateLimiter`，在 ETS 插入一条过期记录，连续三次调用 `check(key, 1, 60)`。三次均返回 `:allow`，记录始终保留旧到期时间，确认窗口重置缺陷。
- R01：真实登录数据库路径未运行。用相同的 `with ... else` 结构传入 `{:error, :already_logged_in}`，确认 Elixir 抛出 `WithClauseError`；目标代码的实际失败路径仍需数据库回归测试。
- `mix test` 和 `mix test --include integration` 未完成。尝试默认测试别名时，测试数据库连接失败，不能记录为通过。
- 真实浏览器验收未执行；本轮只有文档变更，不声称已获得窗口或页面操作证据。
- 实际 release 镜像、生产迁移、文件持久化和备份恢复未执行；本轮不发布，也未监测 GitHub CI。

文档提交前检查 UTF-8、LF、Markdown 结构、相对链接、源码行号和 `git diff --check`。本轮的局部检查与静态结论不能替代上述未完成验收。
