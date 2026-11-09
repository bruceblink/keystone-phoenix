# Keystone Phoenix 代码审查记录

审查日期：2026-11-07。代码基线：`455cf82`。

下文保留 2026-11-07 的原始审查与当时的验证限制。2026-11-08 的代码修复、数据库测试及内置浏览器验收结果单独追加在文末，不改写历史证据。

## 当前提交与工作区

2026-11-09 核验时，`work` 与 `origin/main` 均为 `492205d`。R05 限流修复由 `cc4ced0` 交付，R09 批量角色写入由 `2917acf` 交付，用户范围由 `53a21ca` 和 `492205d` 交付，认证和 LiveView 修复分别由 `01656cd`、`b0efb18` 交付，任务并发入口由 `d727113` 交付。本文后续没有注明提交的测试结果均指当时的工作区或快照，不自动代表当前发布版本。

干净的 `9457759` 归档通过格式、源码行数、dev/prod 严格编译及 77 项含集成测试的本地测试。使用该归档构建的应用镜像配合独立 PostgreSQL 18 测试容器，通过空库迁移、重复迁移、首页与健康检查、文件卷重启持久化和数据库备份恢复检查。认证上传下载和认证端到端检查未完成。该镜像早于 `b0efb18`，不能证明当前代码的镜像验收通过。镜像与性能证据见 [`05-image-performance-2026-11-08.md`](05-image-performance-2026-11-08.md)。

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

`Job.run_job/1` 同步调用 `Runner.run/2`。`24004d7` 已将非并发任务的自动与手动执行纳入同一跳过语义；本地 `Job.Lock` 通过 GenServer 监控持有进程，使进程终止后可以清理锁。当前已验证手动与自动执行重叠、取消、超时、进程异常、日志保存失败和允许并发任务。资源上限、多节点调度和生产镜像中的执行路径仍需发布前检查。

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

## 2026-11-08 修复与验收补充

### 同步与修复范围

本轮开始时，`main` 与 `origin/main` 均为 `62fa1e6`。下表记录本轮修复和验收；代码提交及最终收尾状态见“当前提交与工作区”和文末补充。没有修改依赖或共享迁移。

| 问题 | 本轮状态 | 实现与结果 |
| --- | --- | --- |
| R01 | 已修复并验收 | `Auth` 完整传递会话冲突，重复登录返回 `409/10210`；原连接保持有效 |
| R02 | 已修复并验收 | `Permission.scope_users/2` 在计数与分页前限制查询；管理员角色分配、非管理员范围读取和导入逐行授权已通过回归测试 |
| R03 | 已修复并通过定向检查 | `Live.Authentication` 在受保护事件与异步回调前重新核验令牌、会话、账号及权限上下文；失效时由 `LoginState` 清空数据。密码重置并发缺口的复现和后续修复见文末 |
| R04 | 已修复并验收 | 页面使用服务器保存的验证码 key，拒绝缺失、错误、过期和重放；`filter_parameters` 过滤密码、令牌和验证码 |
| R05 | 已修复并推送 | `cc4ced0` 修复限流窗口与同键并发重置；保留单节点接口与既有失败行为 |
| R06 | 已修复并推送 | `492205d` 修复客户端文件名校验、真实 multipart 解析和逐行部门范围检查 |
| R07 | 已修复并验收 | 配置、角色和菜单编辑保留原 ID；修正字典默认值、操作日志目标 ID 与任务结束时间 |
| R08 | 已修复并验收 | 普通用户可进入资料和概览；读取权限控制刷新、字典选择、日志与单项监控。管理写入仍只允许管理员 |
| R09 | 已修复并推送 | `2917acf` 将批量角色分配与取消放入事务，并增加混合目标回归测试 |
| V01 刷新会话 | 已修复并通过定向检查 | `Session.rotate/3` 与登录、密码更新及账号会话撤销使用同一用户级数据库事务锁 |
| V01 任务执行 | 已修复并验收 | `d727113` 加入执行入口反馈和 `Job.Lock` 进程监控锁。5 项定向测试、默认 126 项测试和包含集成测试的 134 项测试通过 |
| V02 发布 | 部分完成 | prod release、迁移、健康检查、RSA 登录、文件上传下载、volume 持久化和备份恢复已通过；标准 Dockerfile 网络访问和完整认证端到端仍未完成 |

原始实现的重复登录 `WithClauseError`、并发刷新失败请求异常和无角色账号 `ArgumentError` 已在真实数据库路径中复现。修复后，相同测试不再抛异常。真实并发测试使用独立数据库连接，不使用同一沙箱连接模拟竞争；同一 refresh token 最多一个请求成功，失败请求返回无效令牌，成功的新会话仍有效。并发测试另重复运行 3 次，均通过。

没有角色的普通账号仍可登录，权限与菜单为空。管理员、正常资料更新、强制登录、正常刷新、允许范围内的查询和编辑仍可使用。未通过降低授权或测试检查来消除失败。

### 测试环境和命令

- Windows 主机通过 WSL `Ubuntu-24.04` 运行构建与 Docker。Elixir/Mix 为 `1.20.5`，Erlang/OTP 为 `29.1.2`，Docker Engine 为 `29.1.3`。
- 使用独立容器 `keystone-phoenix-acceptance-20261108`，镜像 `postgres:18`，实际数据库版本 `18.6`。镜像 ID 为 `sha256:e3d24f6906d0760bf4da0dae872415391ededefad23fd471c47dc53b0ddf3c42`。
- 数据库端口仅映射 `127.0.0.1:25432`。已检查容器健康、`pg_isready`、数据库版本及实际连接。该临时环境仅用于本机测试，不是生产配置。
- 最终测试库为 `keystone_phoenix_validation_20261108_test`；浏览器使用 `keystone_phoenix_acceptance_20261108`。没有复用既有开发库。
- 原复现库中有早期失败测试留下的 3 条数据，因此改用全新测试库。最终测试结束后，测试库基础用户与认证会话数量均为 `0`。
- 既有 PostgreSQL 17 容器与 Redis 的数据和运行状态没有修改。

以下命令在 WSL 项目目录执行，`POSTGRES_HOST=127.0.0.1`、`POSTGRES_PORT=25432`、`POSTGRES_DB=keystone_phoenix_validation_20261108_test`、`MIX_BUILD_ROOT=_build/wsl`：

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 格式 | `mix format --check-formatted` | 通过 |
| 源文件限制 | `mix check.source_lines` | 通过，均不超过 600 行 |
| 开发严格编译 | `MIX_ENV=dev mix compile --warnings-as-errors` | 通过 |
| 生产严格编译 | `MIX_ENV=prod mix compile --warnings-as-errors` | 通过 |
| 默认测试 | `MIX_ENV=test mix test` | 106 项通过，7 项集成测试排除 |
| 完整测试 | `MIX_ENV=test mix test --include integration` | 113 项通过 |
| 页面聚焦回归 | AdminEditing、LiveAuthentication、ReadonlyPanels | 32 项通过 |
| 文本与差异 | UTF-8、LF、`git diff --check` | 通过 |

首次编译依赖时仍输出第三方弃用或维护警告。应用自身的最终严格编译退出码为 `0`。本轮没有降低警告级别、添加忽略规则或修改锁文件。

新增的回归文件覆盖真实 Auth/HTTP 登录、刷新竞争、无角色菜单、用户范围、编辑保存、长连接认证和只读面板。既有限流测试还覆盖过期窗口、ETS 清理、同键并发，以及 plug 的 `429` 和 `Retry-After`。

### Codex 内置浏览器验收

页面地址为 `http://localhost:4400/`，使用隐藏启动的本地开发实例、独立验收库和合成测试账号。任务调度器已关闭，避免验收数据触发后台任务。它不是生产镜像性能测量对象。页面身份、有效内容、错误覆盖层、控制台、截图和交互结果均已核验。

| 操作 | 页面与数据库证据 |
| --- | --- |
| 首次与重复登录 | 首次进入管理概览；第二个页面显示已登录提示，不终止原页面 |
| 配置编辑保存 | 原名称、键、可选值和 ID 保留；保存显示“配置已更新”，原记录值改变，匹配的记录数仍为 1 |
| 菜单编辑 | 显示原名称、路径、路由名称及权限；编辑后的保存另由 LiveView 数据库测试验证 |
| 字典非默认项 | 编辑选择仍为“否”；保存后目标记录的 `is_default=false` |
| 会话撤销 | 保持页面连接，在验收库撤销该账号会话；点击受保护按钮后返回登录页，显示失效原因并清空原页面 |
| 普通用户资料 | 无管理权限账号可进入资料页并保存昵称；退出可回到登录页 |
| 数据范围与刷新 | 只读角色只看到允许部门的 2 个用户，没有编辑按钮；数据库修改后点击刷新，显示新昵称，不显示范围外管理员 |
| 验证码开关与错误输入 | 开启后出现 `160×60` 图片和必填输入；图片实际加载且刷新后改变；错误输入被拒绝。没有代解验证码；正确值消费与重放由入口测试验证 |
| 响应式布局 | 检查 `1280×900` 与 `390×844`；修复页头昵称被退出按钮挤压。窄屏无页面横向溢出，结束时恢复浏览器尺寸 |

没有发现相关控制台错误或框架错误覆盖层。完成后已退出测试账号、恢复验证码关闭状态，并保留内置浏览器登录页。截图保存在当前任务的本机可视化目录，不加入仓库。

本轮按用户指定使用 Codex 内置浏览器。此前外部 Windows 浏览器因无法核验 URL 而停止操作；该限制不能被描述为外部 Chrome 窗口验收通过。未执行其他操作系统、文件上传下载、长时间运行或生产流量验收。

本地页面进程和临时数据库保留供用户检查。页面进程的本轮 PID 为 `14480`，可用 `Stop-Process -Id 14480` 停止；停止前应重新核验 PID 对应的验收脚本。临时数据库容器只在不再需要页面与后续测量时清理，不删除既有持久服务。

### 独立候选复核

一次独立只读复核提出了密码重置与刷新重叠的候选问题。后续使用真实数据库路径确认了该问题；当时尚未修改运行代码，后续修复见“今日收尾”。

发生前提：`Session.rotate/3` 持有用户级事务锁，并已删除旧会话但尚未提交。另一连接提交密码更新，随后调用不取得相同锁的 `Session.revoke_account/1`。撤销语句在刷新提交前开始，可能只覆盖旧行而漏掉新插入的会话。

受控复现使用独立 PostgreSQL 18 数据库 `keystone_phoenix_rotation_race_20261108` 和独立连接，不共享测试沙箱连接。测试先调用真实 `Auth.login_plaintext`，再用仅测试用的数据库触发器暂停真实 `Auth.refresh` 的旧会话删除，启动真实 `User.reset_password`，确认数据库锁等待后释放刷新。一次复现通过以下断言：刷新成功、密码重置成功、新会话 ID 与旧会话不同，而 `Auth.Session.active?/2` 对新会话仍返回 `true`。这证明密码重置返回成功不总能保证全部会话已失效。它不证明停用账号后仍能通过账号状态校验。

该测试刻意延长重叠窗口。实际请求发生频率和窗口长度尚未测量，不能据此给出线上概率。复现脚本位于当前任务的本地证据目录 `keystone-metrics/` 同级文件 `refresh_password_race_test.exs`，不属于仓库测试套件。测试结束后已删除触发器、函数和合成账号，释放等待连接；独立库中的 `sys_user` 与 `auth_sessions` 数量均为 `0`。当时的 113 项测试通过不能替代该问题的后续修复验收。

角色分配规则仍是原有未关闭项，不将所有 `roleId` 变更直接认定为本次补丁产生的越权。镜像大小与性能的单独测量见 [`05-image-performance-2026-11-08.md`](05-image-performance-2026-11-08.md)，不替代认证或发布验收。

### 今日收尾

`01656cd` 将登录、刷新、密码重置和改密的相关操作置于同一用户级 PostgreSQL 事务锁内。密码写入和撤销会话在同一事务中，写入失败会回滚。认证定向测试共 13 项通过，覆盖密码重置与刷新、旧密码登录重叠，以及数据库写入失败。认证文件的格式、源码行数和严格编译检查通过。

独立快照基于 `53a21ca`，叠加当时的 `lib/`、`test/` 工作区改动和 `config/config.exs`。测试使用 WSL Ubuntu 24.04 中的 Elixir `1.20.5`、OTP `29.1.2`，连接本机端口 `25432` 的 PostgreSQL `18.6` 和专用测试库。非集成测试为 123/124 项通过；包含集成测试为 130/131 项通过。两次唯一失败均为 `Job.RunnerTest` 的终止手动任务后释放锁测试等待超时。该快照含未提交的任务代码，不是干净提交的完整测试结果。

`b0efb18` 提交 LiveView 会话复核、验证码入口、只读面板与相关测试。此前的内置浏览器验收覆盖多个已登录操作；收尾时再次打开 `http://localhost:4400/`，确认登录页正常显示，错误账号显示“用户名或密码错误”。收尾时没有重新执行全部浏览器流程。

`d727113` 已将任务并发改动、`Job.Lock`、应用监督树和任务测试提交到远端。`492205d` 继续提交角色分配授权和 Excel multipart 导入。该锁管理器使用进程监控清理异常终止的持有者。任务定向测试 5 项通过，默认全量测试为 126 项通过、8 项排除，包含集成测试为 134 项通过。格式、源码行数和开发严格编译通过。

用户提供的 GitHub Actions 运行 `42479319497`（提交 `24004d7`）在步骤 8 的 `runner_test.exs:62` 失败。失败断言是“被终止的手动调用者释放任务锁”在 500 毫秒内未观察到锁。该运行没有进入 LiveView 集成测试。`d727113` 的 `Job.Lock` 改动已覆盖该路径，并在宿主机上通过同一测试和全量测试。`492205d` 的角色分配和 Excel multipart 回归也已通过。

宿主机通过用户级工具链运行 Elixir `1.20.5`、Mix `1.20.5` 和 Erlang/OTP `29`。Hex 证书路径已配置为宿主机 CA 文件。运行时仍输出可选 `libsctp.so.1` 缺失警告；该警告未影响本项目编译和测试。没有修改 `mix.lock`，没有创建新标签或 release。V02 已完成主要本地路径，但标准 Dockerfile 构建、认证刷新/退出、LiveView 失效会话和生产流量检查仍未完成。现有最新 release 为 `v0.2.0`。
