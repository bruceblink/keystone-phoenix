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
    socket =
      allow_upload(socket, :avatar,
        accept: ~w(.bmp .gif .jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 50 * 1024 * 1024
      )

    {:ok,
     socket
     |> LoginState.reset()
     |> Authentication.refresh_captcha()
     |> attach_hook(:authenticate_event, :handle_event, &Authentication.guard_event/3)
     |> attach_hook(:authenticate_info, :handle_info, &Authentication.guard_info/2)}
  end

  @impl true
  def handle_event("login", %{"username" => username, "password" => password} = params, socket) do
    username = String.trim(username)

    result =
      with :allow <- LoginLimiter.check_liveview(username),
           :ok <- Captcha.validate(params["captchaCode"], socket.assigns.captcha_key) do
        Auth.login_plaintext(username, password)
      else
        {:deny, retry_after} -> {:error, {:rate_limited, retry_after}}
        error -> error
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

      {:error, :unavailable} ->
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
    {:noreply, Authentication.refresh_captcha(socket)}
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
        <style>
          :root {
            color-scheme: light;
            font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            --ink: #12213d;
            --muted: #63708a;
            --line: #d9e0eb;
            --surface: #ffffff;
            --surface-soft: #f6f8fc;
            --canvas: #eef2f7;
            --navy: #0e2144;
            --primary: #185ee8;
            --primary-dark: #0d46b5;
            --success: #087443;
            --danger: #b42318;
            --shadow: 0 18px 48px rgba(14, 33, 68, 0.12);
          }
          * { box-sizing: border-box; }
          body { margin: 0; min-height: 100vh; background: var(--canvas); color: var(--ink); }
          main { width: min(1240px, calc(100% - 40px)); margin: 0 auto; padding: 48px 0; }
          .shell { display: grid; grid-template-columns: minmax(0, 1.15fr) minmax(360px, 0.85fr); gap: 48px; align-items: center; }
          .brand { padding: 24px 0; }
          .brand p:first-child { margin: 0 0 16px; color: var(--primary); font-size: 13px; font-weight: 800; letter-spacing: 0.14em; text-transform: uppercase; }
          .brand h1 { max-width: 620px; margin: 0 0 18px; font-size: clamp(36px, 5vw, 62px); line-height: 1.08; letter-spacing: -0.045em; }
          .brand p { max-width: 560px; margin: 0; color: var(--muted); font-size: 17px; line-height: 1.75; }
          .card { padding: 32px; border: 1px solid var(--line); border-radius: 20px; background: var(--surface); box-shadow: var(--shadow); }
          .card h2 { margin: 0 0 24px; font-size: 24px; letter-spacing: -0.02em; }
          label { display: block; margin: 16px 0 7px; color: var(--ink); font-size: 14px; font-weight: 700; }
          input { box-sizing: border-box; width: 100%; min-height: 46px; padding: 11px 13px; border: 1px solid #b9c5d6; border-radius: 10px; background: var(--surface); color: var(--ink); font: inherit; transition: border-color 160ms ease, box-shadow 160ms ease; }
          input::placeholder, textarea::placeholder { color: #8b98ad; }
          input:focus, select:focus, textarea:focus, button:focus-visible { outline: 3px solid rgba(24, 94, 232, 0.28); outline-offset: 2px; border-color: var(--primary); }
          button { min-height: 42px; width: 100%; margin-top: 20px; padding: 10px 15px; border: 1px solid transparent; border-radius: 10px; background: var(--primary); color: white; font: inherit; font-weight: 750; cursor: pointer; transition: background 160ms ease, transform 160ms ease, box-shadow 160ms ease; }
          button:hover { background: var(--primary-dark); box-shadow: 0 8px 18px rgba(24, 94, 232, 0.2); }
          button:active { transform: translateY(1px); }
          button:disabled, button.phx-submit-loading, button.phx-click-loading { cursor: wait; opacity: 0.68; box-shadow: none; }
          button.secondary { border-color: #c2ccda; background: var(--surface); color: var(--ink); }
          button.secondary:hover { background: var(--surface-soft); }
          .error { display: flex; gap: 8px; align-items: flex-start; margin: 16px 0 0; padding: 11px 13px; border: 1px solid #f1b6b1; border-radius: 10px; background: #fff1f0; color: var(--danger); font-size: 14px; line-height: 1.45; }
          .user { display: flex; justify-content: space-between; gap: 16px; align-items: center; }
          .user > div { min-width: 0; overflow-wrap: anywhere; }
          .user button { width: auto; margin: 0; flex-shrink: 0; }
          .user strong { display: block; font-size: 18px; }
          .user span { display: block; margin-top: 4px; color: var(--muted); font-size: 14px; }
          .dashboard { grid-column: 1 / -1; }
          .topbar { display: flex; justify-content: space-between; gap: 24px; align-items: center; margin-bottom: 24px; }
          .topbar > div:first-child p { margin: 0 0 7px; color: var(--primary); font-size: 13px; font-weight: 800; letter-spacing: 0.12em; text-transform: uppercase; }
          .topbar h2 { margin: 0; font-size: clamp(28px, 4vw, 38px); letter-spacing: -0.04em; }
          nav { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 18px; padding: 8px; border: 1px solid var(--line); border-radius: 14px; background: var(--surface); box-shadow: 0 6px 18px rgba(14, 33, 68, 0.05); }
          nav button { width: auto; min-height: 38px; margin: 0; padding: 8px 13px; border-color: transparent; background: transparent; color: var(--muted); font-size: 14px; }
          nav button:hover { background: #edf3ff; color: var(--primary-dark); box-shadow: none; }
          nav button.active { background: var(--navy); color: white; }
          nav button.danger { background: #fff1f0; color: var(--danger); }
          .panel { overflow-x: auto; padding: 24px; border: 1px solid var(--line); border-radius: 16px; background: var(--surface); box-shadow: 0 8px 22px rgba(14, 33, 68, 0.05); }
          .panel h3 { margin: 18px 0 10px; }
          .form-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px 14px; margin-bottom: 16px; }
          .form-grid .wide { grid-column: 1 / -1; }
          .form-grid input, .form-grid select, .form-grid textarea, select, textarea { box-sizing: border-box; width: 100%; min-height: 42px; padding: 10px 12px; border: 1px solid #b9c5d6; border-radius: 9px; background: var(--surface); color: var(--ink); font: inherit; transition: border-color 160ms ease, box-shadow 160ms ease; }
          .form-grid textarea { min-height: 88px; resize: vertical; }
          .form-actions { display: flex; gap: 8px; flex-wrap: wrap; margin: 10px 0 16px; }
          .form-actions button, table button { width: auto; min-height: 38px; margin: 0; padding: 8px 12px; }
          .form-actions button.secondary, table button.secondary { background: var(--surface-soft); }
          .danger-action { background: #c83d35 !important; }
          .danger-action:hover { background: #a92d28 !important; }
          .feedback { margin: 8px 0 14px; padding: 10px 12px; border: 1px solid #a9dfc2; border-radius: 10px; background: #effbf4; color: var(--success); }
          .table-actions { display: flex; gap: 6px; flex-wrap: wrap; }
          .monitor-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; margin: 14px 0 24px; }
          .monitor-grid.details { grid-template-columns: repeat(2, minmax(0, 1fr)); }
          .metric, .details > div { padding: 16px; border: 1px solid var(--line); border-radius: 12px; background: var(--surface-soft); }
          .metric span, .metric small { display: block; color: var(--muted); }
          .metric strong { display: block; margin: 8px 0; color: var(--ink); font-size: 24px; }
          .details h3 { margin-top: 0; }
          .details p { margin: 8px 0; color: var(--muted); }
          table { width: 100%; border-collapse: collapse; font-size: 14px; }
          th, td { padding: 12px 9px; border-bottom: 1px solid var(--line); text-align: left; white-space: nowrap; }
          tbody tr:hover { background: #f7faff; }
          th { color: var(--muted); font-weight: 700; background: var(--surface-soft); }
          .muted { color: var(--muted); }
          .refresh { width: auto; margin: 0 0 14px; padding: 8px 12px; }
          @media (prefers-reduced-motion: reduce) {
            *, *::before, *::after { scroll-behavior: auto !important; transition-duration: 0.01ms !important; animation-duration: 0.01ms !important; }
          }
          @media (max-width: 720px) {
            main { width: min(100% - 24px, 620px); padding: 24px 0 40px; }
            .shell { grid-template-columns: 1fr; gap: 24px; }
            .brand { padding: 8px 0; }
            .brand h1 { font-size: 38px; }
            .brand p { font-size: 16px; }
            .card, .panel { padding: 20px; border-radius: 14px; }
            .monitor-grid, .monitor-grid.details { grid-template-columns: 1fr; }
            .form-grid { grid-template-columns: 1fr; }
            .form-grid .wide { grid-column: auto; }
            .topbar { flex-direction: column; align-items: stretch; gap: 16px; }
            .user { justify-content: space-between; }
            nav { overflow-x: auto; flex-wrap: nowrap; scrollbar-width: thin; }
            nav button { flex: 0 0 auto; }
            .panel { overflow-x: auto; }
          }
        </style>
      </head>
      <body>
        <main>
          <section class="shell">
            <%= if @current_user do %>
              <div class="dashboard">
                <div class="topbar">
                  <div>
                    <p class="muted">Keystone Phoenix</p>
                    <h2><%= if @current_user["isAdmin"] == 1, do: "管理概览", else: "个人中心" %></h2>
                  </div>
                  <div class="user">
                    <div>
                      <strong><%= @current_user["nickname"] || @current_user["username"] %></strong>
                      <span>@<%= @current_user["username"] %></span>
                    </div>
                    <button type="button" class="secondary" phx-click="logout" phx-disable-with="退出中…">退出</button>
                  </div>
                </div>
                <%= if @current_user["isAdmin"] == 1 or Enum.any?(Map.values(@panel_access)) do %>
                  <nav aria-label="管理模块">
                    <button type="button" class={if @active_panel == "overview", do: "active", else: ""} phx-click="show-panel" phx-value-panel="overview">概览</button>
                    <button :if={@panel_access["depts"]} type="button" class={if @active_panel == "depts", do: "active", else: ""} phx-click="show-panel" phx-value-panel="depts">部门</button>
                    <button :if={@panel_access["posts"]} type="button" class={if @active_panel == "posts", do: "active", else: ""} phx-click="show-panel" phx-value-panel="posts">岗位</button>
                    <button :if={@panel_access["roles"]} type="button" class={if @active_panel == "roles", do: "active", else: ""} phx-click="show-panel" phx-value-panel="roles">角色</button>
                    <button :if={@panel_access["menus"]} type="button" class={if @active_panel == "menus", do: "active", else: ""} phx-click="show-panel" phx-value-panel="menus">菜单</button>
                    <button :if={@panel_access["users"]} type="button" class={if @active_panel == "users", do: "active", else: ""} phx-click="show-panel" phx-value-panel="users">用户</button>
                    <button :if={@panel_access["configs"]} type="button" class={if @active_panel == "configs", do: "active", else: ""} phx-click="show-panel" phx-value-panel="configs">配置</button>
                    <button :if={@panel_access["dicts"]} type="button" class={if @active_panel == "dicts", do: "active", else: ""} phx-click="show-panel" phx-value-panel="dicts">字典</button>
                    <button :if={@panel_access["notices"]} type="button" class={if @active_panel == "notices", do: "active", else: ""} phx-click="show-panel" phx-value-panel="notices">公告</button>
                    <button :if={@panel_access["logs"]} type="button" class={if @active_panel == "logs", do: "active", else: ""} phx-click="show-panel" phx-value-panel="logs">日志</button>
                    <button :if={@panel_access["jobs"]} type="button" class={if @active_panel == "jobs", do: "active", else: ""} phx-click="show-panel" phx-value-panel="jobs">定时任务</button>
                    <button :if={@panel_access["job-logs"]} type="button" class={if @active_panel == "job-logs", do: "active", else: ""} phx-click="show-panel" phx-value-panel="job-logs">任务日志</button>
                    <button :if={@panel_access["monitor"]} type="button" class={if @active_panel == "monitor", do: "active", else: ""} phx-click="show-panel" phx-value-panel="monitor">监控</button>
                    <button type="button" class={if @active_panel == "profile", do: "active", else: ""} phx-click="show-panel" phx-value-panel="profile">个人资料</button>
                  </nav>
                  <%= case @active_panel do %>
                    <% "overview" -> %>
                      <div class="panel">
                        <p>当前登录用户：<strong><%= @current_user["username"] %></strong></p>
                        <p class="muted">部门：<%= length(@dept_rows) %>　岗位：<%= length(@post_rows) %>　角色：<%= length(@role_rows) %>　菜单：<%= length(@menu_rows) %>　公告：<%= length(@notice_rows) %>　用户：<%= length(@user_rows) %>　配置：<%= length(@config_rows) %>　字典：<%= length(@dict_type_rows) %>　任务：<%= length(@job_rows) %></p>
                      </div>
                    <% "depts" -> %>
                      <.departments dept_rows={@dept_rows} dept_form={@dept_form} dept_feedback={@dept_feedback} read_only={@read_only} />
                    <% "posts" -> %>
                      <.posts post_rows={@post_rows} post_form={@post_form} post_feedback={@post_feedback} read_only={@read_only} />
                    <% "roles" -> %>
                      <.roles role_rows={@role_rows} role_form={@role_form} role_feedback={@role_feedback} selected_role_id={@selected_role_id} selected_role_name={@selected_role_name} allocated_role_user_rows={@allocated_role_user_rows} unallocated_role_user_rows={@unallocated_role_user_rows} role_user_feedback={@role_user_feedback} read_only={@read_only} />
                    <% "menus" -> %>
                      <.menus menu_rows={@menu_rows} menu_form={@menu_form} menu_feedback={@menu_feedback} read_only={@read_only} />
                    <% "users" -> %>
                      <.users user_rows={@user_rows} user_form={@user_form} user_feedback={@user_feedback} dept_rows={@dept_rows} post_rows={@post_rows} role_rows={@role_rows} read_only={@read_only} />
                    <% "configs" -> %>
                      <.configs config_rows={@config_rows} config_form={@config_form} config_feedback={@config_feedback} read_only={@read_only} />
                    <% "dicts" -> %>
                      <.dicts dict_type_rows={@dict_type_rows} dict_data_rows={@dict_data_rows} dict_type_form={@dict_type_form} dict_data_form={@dict_data_form} selected_dict_type={@selected_dict_type} dict_feedback={@dict_feedback} read_only={@read_only} />
                    <% "notices" -> %>
                      <.notices notice_rows={@notice_rows} notice_form={@notice_form} notice_feedback={@notice_feedback} read_only={@read_only} />
                    <% "logs" -> %>
                      <.logs login_log_rows={@login_log_rows} operation_log_rows={@operation_log_rows} log_feedback={@log_feedback} read_only={@read_only} />
                    <% "jobs" -> %>
                      <.jobs job_rows={@job_rows} job_form={@job_form} job_targets={@job_targets} job_feedback={@job_feedback} read_only={@read_only} />
                    <% "job-logs" -> %>
                      <.job_logs job_log_rows={@job_log_rows} job_log_feedback={@job_log_feedback} read_only={@read_only} />
                    <% "monitor" -> %>
                      <.monitor monitor_server_info={@monitor_server_info} monitor_cache_info={@monitor_cache_info} online_user_rows={@online_user_rows} network_status={@network_status} monitor_feedback={@monitor_feedback} read_only={@read_only} />
                    <% "profile" -> %>
                      <.profile profile_form={@profile_form} password_form={@password_form} profile_feedback={@profile_feedback} avatar_upload={@uploads.avatar} />
                    <% _ -> %>
                      <div class="panel"><p>请选择一个管理模块。</p></div>
                  <% end %>
                <% else %>
                  <nav aria-label="个人模块">
                    <button type="button" class={if @active_panel == "profile", do: "active", else: ""} phx-click="show-panel" phx-value-panel="profile">个人资料</button>
                  </nav>
                  <%= if @active_panel == "profile" do %>
                    <.profile profile_form={@profile_form} password_form={@password_form} profile_feedback={@profile_feedback} avatar_upload={@uploads.avatar} />
                  <% else %>
                    <div class="card">
                      <h2>登录成功</h2>
                      <p class="muted">当前账号没有管理后台权限。</p>
                      <button type="button" class="secondary" phx-click="show-panel" phx-value-panel="profile">打开个人资料</button>
                    </div>
                  <% end %>
                <% end %>
              </div>
            <% else %>
              <div class="brand">
                <p>Keystone Phoenix</p>
                <h1>管理后台正在迁移到 LiveView</h1>
                <p>这个页面运行在 Phoenix LiveView 上，认证和业务数据由 Elixir、PostgreSQL 与 ETS 提供。</p>
              </div>
              <div class="card">
                <form id="login-form" phx-submit="login">
                  <h2>登录</h2>
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
        <script>
          const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
          const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
            params: { _csrf_token: csrfToken }
          });
          liveSocket.connect();
          window.liveSocket = liveSocket;
        </script>
      </body>
    </html>
    """
  end
end
