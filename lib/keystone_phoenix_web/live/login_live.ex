defmodule KeystonePhoenixWeb.LoginLive do
  use Phoenix.LiveView

  import Phoenix.Component
  import KeystonePhoenixWeb.Live.AdminPages.Accounts
  import KeystonePhoenixWeb.Live.AdminPages.Operations
  import KeystonePhoenixWeb.Live.AdminPages.Organization
  import KeystonePhoenixWeb.Live.AdminPages.System

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Captcha
  alias KeystonePhoenix.Auth.LoginLimiter
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Log
  alias KeystonePhoenixWeb.Live.AdminSupport
  alias KeystonePhoenixWeb.Live.Authentication
  alias KeystonePhoenixWeb.Live.LoginState
  alias KeystonePhoenixWeb.Live.AdminEvents.Accounts, as: AccountsEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.Operations, as: OperationsEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.Organization, as: OrganizationEvents
  alias KeystonePhoenixWeb.Live.AdminEvents.System, as: SystemEvents

  @impl true
  def mount(_params, _session, socket) do
    remote_ip = connect_remote_ip(socket)

    socket =
      allow_upload(socket, :avatar,
        accept: ~w(.bmp .gif .jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 50 * 1024 * 1024
      )

    {:ok,
     socket
     |> LoginState.reset()
     |> assign(remote_ip: remote_ip)
     |> Authentication.refresh_captcha()
     |> attach_hook(:authenticate_event, :handle_event, &Authentication.guard_event/3)
     |> attach_hook(:authenticate_info, :handle_info, &Authentication.guard_info/2)}
  end

  @impl true
  def handle_event("login", %{"username" => username, "password" => password} = params, socket) do
    username = String.trim(username)

    result =
      case LoginLimiter.check_liveview(username, liveview_ip(socket)) do
        :allow ->
          case Captcha.validate(params["captchaCode"], socket.assigns.captcha_key) do
            :ok -> Auth.login_plaintext(username, password)
            error -> error
          end

        {:deny, retry_after} ->
          {:error, {:rate_limited, retry_after}}

        {:error, reason} when reason in [:capacity, :unavailable] ->
          {:error, :login_limiter_unavailable}
      end

    case result do
      {:ok, tokens} ->
        Log.record_login_event(username, 1, "登录成功")
        current_user = Map.get(tokens.current_user, "userInfo", tokens.current_user)
        permissions = Map.get(tokens.current_user, "permissions", [])

        is_admin = current_user["isAdmin"] == 1

        dashboard =
          if is_admin,
            do: load_dashboard(),
            else: load_dashboard_for_permissions(current_user, permissions)

        panel_access = AdminSupport.panel_access(permissions, is_admin)

        {:noreply,
         assign(socket,
           username: username,
           password: "",
           login_error: nil,
           current_user: current_user,
           permissions: permissions,
           auth_context: Authentication.context(current_user, permissions),
           panel_access: panel_access,
           read_only: not is_admin,
           access_token: tokens.token,
           refresh_token: tokens.refresh_token,
           active_panel: "overview",
           user_rows: dashboard.user_rows,
           dept_rows: dashboard.dept_rows,
           dept_feedback: nil,
           dept_form: empty_dept_form(),
           post_rows: dashboard.post_rows,
           post_feedback: nil,
           post_form: empty_post_form(),
           config_rows: dashboard.config_rows,
           config_feedback: nil,
           config_form: empty_config_form(),
           dict_type_rows: dashboard.dict_type_rows,
           dict_data_rows: dashboard.dict_data_rows,
           dict_feedback: nil,
           dict_type_form: empty_dict_type_form(),
           dict_data_form: empty_dict_data_form(dashboard.selected_dict_type),
           selected_dict_type: dashboard.selected_dict_type,
           job_rows: dashboard.job_rows,
           job_feedback: nil,
           job_form: empty_job_form(),
           job_targets: Job.invoke_targets(),
           job_log_rows: dashboard.job_log_rows,
           job_log_feedback: nil,
           role_rows: dashboard.role_rows,
           selected_role_id: "",
           selected_role_name: "",
           allocated_role_user_rows: [],
           unallocated_role_user_rows: [],
           role_user_feedback: nil,
           role_feedback: nil,
           role_form: empty_role_form(),
           menu_rows: dashboard.menu_rows,
           menu_feedback: nil,
           menu_form: empty_menu_form(),
           notice_rows: dashboard.notice_rows,
           notice_feedback: nil,
           notice_form: empty_notice_form(),
           login_log_rows: dashboard.login_log_rows,
           operation_log_rows: dashboard.operation_log_rows,
           log_feedback: nil,
           user_form: empty_user_form(),
           user_feedback: nil,
           profile_form: current_user,
           password_form: empty_password_form(),
           profile_feedback: nil
         )}

      {:error, :already_logged_in} ->
        Log.record_login_event(username, 0, "该账号已经登录")
        login_error(socket, username, "该账号已经登录，请先退出或使用 API 的 forceLogin 接管")

      {:error, {:rate_limited, retry_after}} ->
        Log.record_login_event(username, 0, "登录尝试过于频繁")
        login_error(socket, username, "登录尝试过于频繁，请在 #{retry_after} 秒后重试")

      {:error, :login_limiter_unavailable} ->
        Log.record_login_event(username, 0, "限流服务暂不可用")
        login_error(socket, username, "登录服务暂不可用，请稍后重试")

      {:error, reason} when reason in [:capacity, :unavailable] ->
        Log.record_login_event(username, 0, "认证会话暂不可用")
        login_error(socket, username, "认证会话暂不可用，请稍后重试")

      {:error, reason} when reason in [:captcha_required, :captcha_invalid, :captcha_expired] ->
        message = captcha_error(reason)
        Log.record_login_event(username, 0, message)
        login_error(socket, username, message)

      _ ->
        Log.record_login_event(username, 0, "用户名或密码错误")
        login_error(socket, username, "用户名或密码错误")
    end
  end

  def handle_event("login", _params, socket) do
    {:noreply, assign(socket, login_error: "请输入用户名和密码")}
  end

  def handle_event("refresh-captcha", _params, socket) do
    case LoginLimiter.check_captcha(liveview_ip(socket)) do
      :allow ->
        {:noreply, Authentication.refresh_captcha(socket)}

      {:deny, retry_after} ->
        {:noreply, assign(socket, login_error: "验证码刷新过于频繁，请在 #{retry_after} 秒后重试")}

      {:error, reason} when reason in [:capacity, :unavailable] ->
        {:noreply, assign(socket, login_error: "验证码服务暂不可用，请稍后重试")}
    end
  end

  @impl true
  def handle_event("show-panel", %{"panel" => panel}, socket)
      when panel in [
             "overview",
             "depts",
             "posts",
             "roles",
             "menus",
             "notices",
             "logs",
             "users",
             "configs",
             "dicts",
             "jobs",
             "job-logs",
             "profile",
             "monitor"
           ] do
    if AdminSupport.panel_allowed?(socket, panel) do
      cond do
        panel == "profile" ->
          {:noreply, assign_profile(socket)}

        panel == "monitor" ->
          socket = assign(socket, page_nums: Map.put(socket.assigns.page_nums, "online-users", 1))
          {:noreply, assign_monitor(socket)}

        panel == "job-logs" ->
          {:noreply, assign(socket, active_panel: panel, job_log_rows: load_job_logs())}

        panel == "logs" ->
          logs = AdminSupport.load_logs_for_socket(socket)

          {:noreply,
           assign(socket,
             active_panel: panel,
             login_log_rows: logs.login_log_rows,
             operation_log_rows: logs.operation_log_rows
           )}

        panel == "users" and not admin_socket?(socket) ->
          {:noreply,
           assign(socket,
             active_panel: panel,
             user_rows: AdminSupport.load_users_for_socket(socket)
           )}

        true ->
          {:noreply, assign(socket, active_panel: panel)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("show-panel", _params, socket), do: {:noreply, socket}

  def handle_event("paginate", %{"panel" => panel, "page" => page}, socket)
      when panel in [
             "users",
             "jobs",
             "job-logs",
             "dict-data",
             "login-logs",
             "operation-logs",
             "online-users",
             "role-users-allocated",
             "role-users-unallocated"
           ] do
    case Integer.parse(to_string(page)) do
      {page, ""} when page > 0 ->
        socket = assign(socket, page_nums: Map.put(socket.assigns.page_nums, panel, page))

        if panel == "online-users" and AdminSupport.panel_allowed?(socket, "monitor") do
          {:noreply, assign_monitor(socket)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("paginate", _params, socket), do: {:noreply, socket}

  @organization_events ~w(refresh-depts new-dept edit-dept save-dept toggle-dept-status delete-dept refresh-posts new-post edit-post save-post toggle-post-status delete-post refresh-roles new-role edit-role save-role toggle-role-status delete-role select-role assign-role-user unassign-role-user refresh-menus new-menu edit-menu save-menu toggle-menu-status delete-menu)
  @accounts_events ~w(refresh-users new-user edit-user save-user toggle-user-status delete-user reset-user-password save-profile change-profile-password update-profile-avatar save-profile-avatar-upload)
  @system_events ~w(refresh-config new-config edit-config save-config refresh-dicts select-dict-type new-dict-type edit-dict-type save-dict-type delete-dict-type new-dict-data edit-dict-data save-dict-data delete-dict-data refresh-logs edit-notice cancel-notice save-notice toggle-notice-status delete-notice refresh-notices delete-login-log delete-operation-log)
  @operations_events ~w(refresh-jobs new-job edit-job save-job delete-job run-job cancel-job toggle-job-status refresh-job-logs refresh-monitor logout-online-user)

  @impl true
  def handle_event(event, params, socket) when event in @organization_events,
    do: OrganizationEvents.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @accounts_events,
    do: AccountsEvents.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @system_events,
    do: SystemEvents.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @operations_events,
    do: OperationsEvents.handle_event(event, params, socket)

  @impl true
  def handle_event("logout", _params, socket) do
    Auth.logout(socket.assigns.refresh_token)
    {:noreply, socket |> LoginState.reset() |> Authentication.refresh_captcha()}
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:admin_job_finished, _job_id, result}, socket) do
    if admin_socket?(socket) do
      feedback =
        case result do
          :ok -> "任务已执行并写入运行日志"
          {:skipped, :already_running} -> "任务正在执行，本次触发已跳过"
          {:error, :not_found} -> "找不到指定任务"
          {:error, reason} -> "任务执行失败：#{inspect(reason)}"
          _ -> "任务状态未知，请检查运行日志"
        end

      {:noreply,
       assign(socket,
         job_rows: load_jobs(),
         job_log_rows: load_job_logs(),
         job_feedback: feedback
       )}
    else
      {:noreply, socket}
    end
  end

  defp login_error(socket, username, message) do
    {:noreply,
     socket
     |> Authentication.refresh_captcha()
     |> assign(username: username, password: "", login_error: message)}
  end

  defp captcha_error(:captcha_required), do: "请输入验证码"
  defp captcha_error(:captcha_invalid), do: "验证码错误，请重试"
  defp captcha_error(:captcha_expired), do: "验证码已过期，请重试"

  defp liveview_ip(socket) do
    Map.get(socket.assigns, :remote_ip)
  end

  defp connect_remote_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> address
      _ -> nil
    end
  end

  defp load_dashboard, do: AdminSupport.load_dashboard()

  defp load_dashboard_for_permissions(user, permissions),
    do: AdminSupport.load_dashboard_for_permissions(user, permissions)

  defp load_jobs, do: AdminSupport.load_jobs()
  defp load_job_logs, do: AdminSupport.load_job_logs()
  defp empty_notice_form, do: AdminSupport.empty_notice_form()
  defp empty_dept_form, do: AdminSupport.empty_dept_form()
  defp empty_post_form, do: AdminSupport.empty_post_form()
  defp empty_role_form, do: AdminSupport.empty_role_form()
  defp empty_menu_form, do: AdminSupport.empty_menu_form()
  defp empty_user_form, do: AdminSupport.empty_user_form()
  defp empty_config_form, do: AdminSupport.empty_config_form()
  defp empty_dict_type_form, do: AdminSupport.empty_dict_type_form()
  defp empty_job_form, do: AdminSupport.empty_job_form()
  defp empty_password_form, do: AdminSupport.empty_password_form()
  defp empty_dict_data_form(dict_type), do: AdminSupport.empty_dict_data_form(dict_type)
  defp assign_monitor(socket, feedback \\ nil), do: AdminSupport.assign_monitor(socket, feedback)
  defp assign_profile(socket), do: AdminSupport.assign_profile(socket)
  defp admin_socket?(socket), do: AdminSupport.admin_socket?(socket)

  # 将内部面板标识映射为面向管理员的正式页面标题。
  defp panel_title("overview"), do: "平台概览"
  defp panel_title("depts"), do: "部门管理"
  defp panel_title("posts"), do: "岗位管理"
  defp panel_title("roles"), do: "角色管理"
  defp panel_title("menus"), do: "菜单管理"
  defp panel_title("users"), do: "用户管理"
  defp panel_title("configs"), do: "配置管理"
  defp panel_title("dicts"), do: "字典管理"
  defp panel_title("notices"), do: "公告管理"
  defp panel_title("logs"), do: "日志审计"
  defp panel_title("jobs"), do: "定时任务"
  defp panel_title("job-logs"), do: "任务日志"
  defp panel_title("monitor"), do: "运行监控"
  defp panel_title("profile"), do: "个人资料"
  defp panel_title(_panel), do: "管理模块"

  @impl true
  def render(assigns) do
    ~H"""
    <!doctype html>
    <html lang="zh-CN">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Keystone Phoenix</title>
        <link rel="stylesheet" href="/css/keystone.css" />
      </head>
      <body>
        <main class="app-main">
          <section class={if @current_user, do: "shell app-shell dashboard-shell", else: "shell app-shell login-shell"}>
            <%= if @current_user do %>
              <div class="dashboard">
                <div class="sidebar-brand">
                  <div class="brand-mark" aria-hidden="true">KP</div>
                  <div>
                    <strong>Keystone Phoenix</strong>
                    <span>企业运营管理平台</span>
                  </div>
                </div>
                <div class="topbar dashboard-topbar">
                  <div>
                    <p class="eyebrow">Keystone Phoenix · 管理平台</p>
                    <h2><%= if @current_user["isAdmin"] == 1, do: "管理概览", else: "个人中心" %></h2>
                  </div>
                  <div class="user">
                    <span class="user-avatar" aria-hidden="true">KP</span>
                    <div>
                      <strong><%= @current_user["nickname"] || @current_user["username"] %></strong>
                      <span>@<%= @current_user["username"] %></span>
                    </div>
                    <button type="button" class="secondary" phx-click="logout" phx-disable-with="退出中…">退出</button>
                  </div>
                </div>
                <%= if @current_user["isAdmin"] == 1 or Enum.any?(Map.values(@panel_access)) do %>
                  <nav class="module-nav" aria-label="管理模块">
                    <span class="nav-section-title">工作台</span>
                    <button data-icon="⌂" type="button" class={if @active_panel == "overview", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "overview", do: "page"} phx-value-panel="overview">概览</button>
                    <span class="nav-section-title">组织与权限</span>
                    <button :if={@panel_access["depts"]} data-icon="◇" type="button" class={if @active_panel == "depts", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "depts", do: "page"} phx-value-panel="depts">部门</button>
                    <button :if={@panel_access["posts"]} data-icon="▦" type="button" class={if @active_panel == "posts", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "posts", do: "page"} phx-value-panel="posts">岗位</button>
                    <button :if={@panel_access["roles"]} data-icon="♢" type="button" class={if @active_panel == "roles", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "roles", do: "page"} phx-value-panel="roles">角色</button>
                    <button :if={@panel_access["menus"]} data-icon="☷" type="button" class={if @active_panel == "menus", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "menus", do: "page"} phx-value-panel="menus">菜单</button>
                    <button :if={@panel_access["users"]} data-icon="●" type="button" class={if @active_panel == "users", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "users", do: "page"} phx-value-panel="users">用户</button>
                    <span class="nav-section-title">系统设置</span>
                    <button :if={@panel_access["configs"]} data-icon="⚙" type="button" class={if @active_panel == "configs", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "configs", do: "page"} phx-value-panel="configs">配置</button>
                    <button :if={@panel_access["dicts"]} data-icon="≡" type="button" class={if @active_panel == "dicts", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "dicts", do: "page"} phx-value-panel="dicts">字典</button>
                    <button :if={@panel_access["notices"]} data-icon="▤" type="button" class={if @active_panel == "notices", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "notices", do: "page"} phx-value-panel="notices">公告</button>
                    <span class="nav-section-title">运维审计</span>
                    <button :if={@panel_access["logs"]} data-icon="◌" type="button" class={if @active_panel == "logs", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "logs", do: "page"} phx-value-panel="logs">日志</button>
                    <button :if={@panel_access["jobs"]} data-icon="↻" type="button" class={if @active_panel == "jobs", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "jobs", do: "page"} phx-value-panel="jobs">定时任务</button>
                    <button :if={@panel_access["job-logs"]} data-icon="≋" type="button" class={if @active_panel == "job-logs", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "job-logs", do: "page"} phx-value-panel="job-logs">任务日志</button>
                    <button :if={@panel_access["monitor"]} data-icon="◉" type="button" class={if @active_panel == "monitor", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "monitor", do: "page"} phx-value-panel="monitor">监控</button>
                    <span class="nav-section-title">账号</span>
                    <button data-icon="◎" type="button" class={if @active_panel == "profile", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "profile", do: "page"} phx-value-panel="profile">个人资料</button>
                  </nav>
                  <div class="page-content">
                    <div class="page-context">
                      <div>
                        <p class="eyebrow">管理模块</p>
                        <h3><%= panel_title(@active_panel) %></h3>
                      </div>
                      <span class="access-chip"><%= if @read_only, do: "只读模式", else: "管理员模式" %></span>
                    </div>
                  <%= case @active_panel do %>
                    <% "overview" -> %>
                      <div class="panel overview-panel">
                        <div class="overview-heading">
                          <div>
                            <p class="eyebrow">平台概览</p>
                            <h3>当前登录用户：<strong><%= @current_user["username"] %></strong></h3>
                          </div>
                          <span class="status-chip">系统运行正常</span>
                        </div>
                        <!-- 概览卡只展示当前会话已加载的数据数量。 -->
                        <div class="overview-grid">
                          <div class="stat-card"><span>部门</span><strong><%= length(@dept_rows) %></strong></div>
                          <div class="stat-card"><span>岗位</span><strong><%= length(@post_rows) %></strong></div>
                          <div class="stat-card"><span>角色</span><strong><%= length(@role_rows) %></strong></div>
                          <div class="stat-card"><span>菜单</span><strong><%= length(@menu_rows) %></strong></div>
                          <div class="stat-card"><span>公告</span><strong><%= length(@notice_rows) %></strong></div>
                          <div class="stat-card"><span>用户</span><strong><%= length(@user_rows) %></strong></div>
                          <div class="stat-card"><span>配置</span><strong><%= length(@config_rows) %></strong></div>
                          <div class="stat-card"><span>字典</span><strong><%= length(@dict_type_rows) %></strong></div>
                          <div class="stat-card"><span>任务</span><strong><%= length(@job_rows) %></strong></div>
                        </div>
                      </div>
                    <% "depts" -> %>
                      <.departments dept_rows={@dept_rows} dept_form={@dept_form} dept_feedback={@dept_feedback} read_only={@read_only} />
                    <% "posts" -> %>
                      <.posts post_rows={@post_rows} post_form={@post_form} post_feedback={@post_feedback} read_only={@read_only} />
                    <% "roles" -> %>
                      <.roles role_rows={@role_rows} role_form={@role_form} role_feedback={@role_feedback} selected_role_id={@selected_role_id} selected_role_name={@selected_role_name} allocated_role_user_rows={@allocated_role_user_rows} unallocated_role_user_rows={@unallocated_role_user_rows} role_user_feedback={@role_user_feedback} allocated_page_num={@page_nums["role-users-allocated"]} unallocated_page_num={@page_nums["role-users-unallocated"]} role_user_page_size={@page_sizes["role-users-allocated"]} read_only={@read_only} />
                    <% "menus" -> %>
                      <.menus menu_rows={@menu_rows} menu_form={@menu_form} menu_feedback={@menu_feedback} read_only={@read_only} />
                    <% "users" -> %>
                      <.users user_rows={@user_rows} user_form={@user_form} user_feedback={@user_feedback} dept_rows={@dept_rows} post_rows={@post_rows} role_rows={@role_rows} page_num={@page_nums["users"]} page_size={@page_sizes["users"]} read_only={@read_only} />
                    <% "configs" -> %>
                      <.configs config_rows={@config_rows} config_form={@config_form} config_feedback={@config_feedback} read_only={@read_only} />
                    <% "dicts" -> %>
                      <.dicts dict_type_rows={@dict_type_rows} dict_data_rows={@dict_data_rows} dict_type_form={@dict_type_form} dict_data_form={@dict_data_form} selected_dict_type={@selected_dict_type} dict_feedback={@dict_feedback} dict_data_page_num={@page_nums["dict-data"]} dict_data_page_size={@page_sizes["dict-data"]} read_only={@read_only} />
                    <% "notices" -> %>
                      <.notices notice_rows={@notice_rows} notice_form={@notice_form} notice_feedback={@notice_feedback} read_only={@read_only} />
                    <% "logs" -> %>
                      <.logs login_log_rows={@login_log_rows} operation_log_rows={@operation_log_rows} log_feedback={@log_feedback} login_page_num={@page_nums["login-logs"]} operation_page_num={@page_nums["operation-logs"]} page_size={@page_sizes["login-logs"]} read_only={@read_only} />
                    <% "jobs" -> %>
                      <.jobs job_rows={@job_rows} job_form={@job_form} job_targets={@job_targets} job_feedback={@job_feedback} page_num={@page_nums["jobs"]} page_size={@page_sizes["jobs"]} read_only={@read_only} />
                    <% "job-logs" -> %>
                      <.job_logs job_log_rows={@job_log_rows} job_log_feedback={@job_log_feedback} page_num={@page_nums["job-logs"]} page_size={@page_sizes["job-logs"]} read_only={@read_only} />
                    <% "monitor" -> %>
                      <.monitor monitor_server_info={@monitor_server_info} monitor_cache_info={@monitor_cache_info} online_user_rows={@online_user_rows} online_user_total={@online_user_total} online_user_page_num={@page_nums["online-users"]} online_user_page_size={@page_sizes["online-users"]} network_status={@network_status} monitor_feedback={@monitor_feedback} read_only={@read_only} />
                    <% "profile" -> %>
                      <.profile profile_form={@profile_form} password_form={@password_form} profile_feedback={@profile_feedback} avatar_upload={@uploads.avatar} />
                    <% _ -> %>
                      <div class="panel"><p>请选择一个管理模块。</p></div>
                  <% end %>
                  </div>
                <% else %>
                  <nav class="module-nav" aria-label="个人模块">
                    <span class="nav-section-title">账号</span>
                    <button data-icon="◎" type="button" class={if @active_panel == "profile", do: "active", else: ""} phx-click="show-panel" aria-current={if @active_panel == "profile", do: "page"} phx-value-panel="profile">个人资料</button>
                  </nav>
                  <div class="page-content">
                    <div class="page-context">
                      <div>
                        <p class="eyebrow">个人中心</p>
                        <h3>个人资料</h3>
                      </div>
                      <span class="access-chip">个人账号</span>
                    </div>
                  <%= if @active_panel == "profile" do %>
                    <.profile profile_form={@profile_form} password_form={@password_form} profile_feedback={@profile_feedback} avatar_upload={@uploads.avatar} />
                  <% else %>
                    <div class="card">
                      <h2>登录成功</h2>
                      <p class="muted">当前账号没有管理后台权限。</p>
                      <button type="button" class="secondary" phx-click="show-panel" aria-current={if @active_panel == "profile", do: "page"} phx-value-panel="profile">打开个人资料</button>
                    </div>
                  <% end %>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="brand hero-copy">
                <p>Keystone Phoenix</p>
                <h1>企业运营管理平台</h1>
                <p>统一管理组织架构、账号权限与系统运营，为日常业务提供清晰、可靠的工作入口。</p>
                <div class="hero-points" aria-label="平台能力">
                  <span>实时状态</span><span>细粒度权限</span><span>安全审计</span>
                </div>
              </div>
              <div class="card login-card">
                <div class="login-card-heading">
                  <span class="login-badge">安全登录</span>
                  <span class="muted">欢迎回来</span>
                </div>
                <form id="login-form" class="login-form" phx-submit="login">
                  <h2>账号登录</h2>
                  <label for="username">用户名</label>
                  <input id="username" name="username" value={@username} autocomplete="username" required />
                  <label for="password">密码</label>
                  <input id="password" name="password" type="password" autocomplete="current-password" required />
                  <div :if={@captcha_enabled}>
                    <label for="captcha-code">验证码</label>
                    <img :if={@captcha_image} src={"data:image/gif;base64," <> @captcha_image} alt="登录验证码" width="160" height="60" />
                    <button type="button" class="secondary" phx-click="refresh-captcha">刷新验证码</button>
                    <input id="captcha-code" name="captchaCode" value="" autocomplete="off" required />
                  </div>
                  <%= if @login_error do %><p class="error" role="alert"><%= @login_error %></p><% end %>
                  <button type="submit" phx-disable-with="登录中…">登录</button>
                </form>
              </div>
            <% end %>
          </section>
        </main>
        <script src="/assets/phoenix/phoenix.min.js"></script>
        <script src="/assets/phoenix_live_view/phoenix_live_view.min.js"></script>
        <script src="/js/live_socket.js"></script>
      </body>
    </html>
    """
  end
end
