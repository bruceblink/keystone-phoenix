defmodule KeystonePhoenixWeb.LoginLive do
  use Phoenix.LiveView

  import Phoenix.Component

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       username: "",
       password: "",
       login_error: nil,
       current_user: nil,
       access_token: nil,
       refresh_token: nil,
       active_panel: "overview",
       user_rows: [],
       config_rows: [],
       dict_type_rows: [],
       job_rows: [],
       job_feedback: nil
     )}
  end

  @impl true
  def handle_event("login", %{"username" => username, "password" => password}, socket) do
    username = String.trim(username)

    case Auth.login_plaintext(username, password) do
      {:ok, tokens} ->
        dashboard =
          if tokens.current_user["isAdmin"] == 1 do
            load_dashboard()
          else
            empty_dashboard()
          end

        {:noreply,
         assign(socket,
           username: username,
           password: "",
           login_error: nil,
           current_user: tokens.current_user,
           access_token: tokens.token,
           refresh_token: tokens.refresh_token,
           active_panel: "overview",
           user_rows: dashboard.user_rows,
           config_rows: dashboard.config_rows,
           dict_type_rows: dashboard.dict_type_rows,
           job_rows: dashboard.job_rows,
           job_feedback: nil
         )}

      {:error, :already_logged_in} ->
        {:noreply, assign(socket, login_error: "该账号已经登录，请先退出或使用 API 的 forceLogin 接管")}

      {:error, :unavailable} ->
        {:noreply, assign(socket, login_error: "认证会话暂不可用，请稍后重试")}

      _ ->
        {:noreply, assign(socket, login_error: "用户名或密码错误")}
    end
  end

  def handle_event("login", _params, socket) do
    {:noreply, assign(socket, login_error: "请输入用户名和密码")}
  end

  @impl true
  def handle_event("show-panel", %{"panel" => panel}, socket)
      when panel in ["overview", "users", "configs", "dicts", "jobs"] do
    if admin_socket?(socket) do
      {:noreply, assign(socket, active_panel: panel)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("show-panel", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("refresh-config", _params, socket) do
    if admin_socket?(socket) do
      Config.refresh_cache()
      {:noreply, assign(socket, config_rows: Config.list_configs(%{"pageSize" => 50}).rows)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh-jobs", _params, socket) do
    if admin_socket?(socket) do
      {:noreply, assign(socket, job_rows: load_jobs(), job_feedback: nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("run-job", %{"job-id" => job_id}, socket) do
    if admin_socket?(socket) do
      feedback =
        case Job.run_job(job_id) do
          :ok -> "任务已执行并写入运行日志"
          {:error, :not_found} -> "找不到指定任务"
          {:error, reason} -> "任务执行失败：#{inspect(reason)}"
        end

      {:noreply, assign(socket, job_rows: load_jobs(), job_feedback: feedback)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle-job-status", %{"job-id" => job_id, "status" => status}, socket) do
    if admin_socket?(socket) do
      feedback =
        case Job.update_job_status(job_id, status) do
          {:ok, _job} -> "任务状态已更新"
          {:error, reason} -> "任务状态更新失败：#{inspect(reason)}"
        end

      {:noreply, assign(socket, job_rows: load_jobs(), job_feedback: feedback)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("logout", _params, socket) do
    Auth.logout(socket.assigns.refresh_token)

    {:noreply,
     assign(socket,
       password: "",
       login_error: nil,
       current_user: nil,
       access_token: nil,
       refresh_token: nil,
       active_panel: "overview",
       user_rows: [],
       config_rows: [],
       dict_type_rows: [],
       job_rows: [],
       job_feedback: nil
     )}
  end

  defp load_dashboard do
    %{
      user_rows: User.list_users(%{"pageSize" => 50}).rows,
      config_rows: Config.list_configs(%{"pageSize" => 50}).rows,
      dict_type_rows: Dictionary.list_dict_types(%{"pageSize" => 50}).rows,
      job_rows: load_jobs()
    }
  end

  defp empty_dashboard,
    do: %{user_rows: [], config_rows: [], dict_type_rows: [], job_rows: []}

  defp load_jobs, do: Job.list_jobs(%{"pageSize" => 50}).rows

  defp admin_socket?(socket),
    do: is_map(socket.assigns.current_user) and socket.assigns.current_user["isAdmin"] == 1

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
          :root { color-scheme: dark; font-family: Inter, system-ui, sans-serif; }
          body { margin: 0; min-height: 100vh; background: #101827; color: #e5edf7; }
          main { width: min(920px, calc(100% - 32px)); margin: 0 auto; padding: 72px 0; }
          .shell { display: grid; grid-template-columns: 1.2fr 1fr; gap: 32px; align-items: center; }
          .brand h1 { margin: 0 0 12px; font-size: 42px; letter-spacing: -1px; }
          .brand p { max-width: 520px; color: #9aacbf; line-height: 1.7; }
          .card { padding: 28px; border: 1px solid #27354a; border-radius: 16px; background: #172235; box-shadow: 0 18px 60px #050a1380; }
          label { display: block; margin: 14px 0 6px; color: #a9b9cc; font-size: 14px; }
          input { box-sizing: border-box; width: 100%; padding: 12px 14px; border: 1px solid #3a4c65; border-radius: 8px; background: #0f1828; color: #e5edf7; }
          button { width: 100%; margin-top: 20px; padding: 12px 14px; border: 0; border-radius: 8px; background: #4f8cff; color: white; font-weight: 700; cursor: pointer; }
          button.secondary { background: #31435c; }
          .error { margin: 14px 0 0; color: #ff9b9b; font-size: 14px; }
          .user { display: flex; justify-content: space-between; gap: 12px; align-items: center; }
          .user strong { display: block; font-size: 20px; }
          .user span { color: #9aacbf; }
          .dashboard { grid-column: 1 / -1; }
          .topbar { display: flex; justify-content: space-between; gap: 16px; align-items: center; margin-bottom: 20px; }
          .topbar h2 { margin: 0; }
          nav { display: flex; gap: 8px; flex-wrap: wrap; }
          nav button { width: auto; margin: 0; padding: 8px 12px; background: #243650; }
          nav button.active { background: #4f8cff; }
          nav button.danger { background: #8b4a55; }
          .panel { overflow-x: auto; padding: 20px; border: 1px solid #27354a; border-radius: 12px; background: #172235; }
          table { width: 100%; border-collapse: collapse; font-size: 14px; }
          th, td { padding: 10px 8px; border-bottom: 1px solid #293a52; text-align: left; white-space: nowrap; }
          th { color: #9aacbf; font-weight: 600; }
          .muted { color: #9aacbf; }
          .refresh { width: auto; margin: 0 0 14px; padding: 8px 12px; }
          @media (max-width: 720px) { .shell { grid-template-columns: 1fr; } main { padding: 32px 0; } .brand h1 { font-size: 34px; } }
        </style>
      </head>
      <body>
        <main>
          <section class="shell">
            <%= if @current_user do %>
              <%= if @current_user["isAdmin"] == 1 do %>
                <div class="dashboard">
                <div class="topbar">
                  <div>
                    <p class="muted">Keystone Phoenix</p>
                    <h2>管理概览</h2>
                  </div>
                  <div class="user">
                    <div>
                      <strong>{@current_user["nickname"] || @current_user["username"]}</strong>
                      <span>@{@current_user["username"]}</span>
                    </div>
                    <button type="button" class="secondary" phx-click="logout">退出</button>
                  </div>
                </div>
                <nav aria-label="管理模块">
                  <button type="button" class={if @active_panel == "overview", do: "active", else: ""} phx-click="show-panel" phx-value-panel="overview">概览</button>
                  <button type="button" class={if @active_panel == "users", do: "active", else: ""} phx-click="show-panel" phx-value-panel="users">用户</button>
                  <button type="button" class={if @active_panel == "configs", do: "active", else: ""} phx-click="show-panel" phx-value-panel="configs">配置</button>
                  <button type="button" class={if @active_panel == "dicts", do: "active", else: ""} phx-click="show-panel" phx-value-panel="dicts">字典</button>
                  <button type="button" class={if @active_panel == "jobs", do: "active", else: ""} phx-click="show-panel" phx-value-panel="jobs">定时任务</button>
                </nav>
                <%= case @active_panel do %>
                  <% "overview" -> %>
                    <div class="panel">
                      <p>当前登录用户：<strong>{@current_user["username"]}</strong></p>
                      <p class="muted">用户总数：{@user_rows |> length()}　配置项：{@config_rows |> length()}　字典类型：{@dict_type_rows |> length()}　定时任务：{@job_rows |> length()}</p>
                    </div>
                  <% "users" -> %>
                    <div class="panel">
                      <table>
                        <thead><tr><th>用户名</th><th>昵称</th><th>邮箱</th><th>状态</th></tr></thead>
                        <tbody>
                          <%= for user <- @user_rows do %>
                            <tr><td>{user["username"]}</td><td>{user["nickname"]}</td><td>{user["email"]}</td><td>{if user["status"] == 1, do: "正常", else: "停用"}</td></tr>
                          <% end %>
                        </tbody>
                      </table>
                    </div>
                  <% "configs" -> %>
                    <div class="panel">
                      <button type="button" class="refresh" phx-click="refresh-config">刷新配置缓存</button>
                      <table>
                        <thead><tr><th>名称</th><th>键</th><th>值</th><th>允许修改</th></tr></thead>
                        <tbody>
                          <%= for config <- @config_rows do %>
                            <tr><td>{config["configName"]}</td><td>{config["configKey"]}</td><td>{config["configValue"]}</td><td>{config["isAllowChangeStr"]}</td></tr>
                          <% end %>
                        </tbody>
                      </table>
                    </div>
                  <% "dicts" -> %>
                    <div class="panel">
                      <table>
                        <thead><tr><th>名称</th><th>类型</th><th>状态</th><th>备注</th></tr></thead>
                        <tbody>
                          <%= for dict <- @dict_type_rows do %>
                            <tr><td>{dict["dictName"]}</td><td>{dict["dictType"]}</td><td>{if dict["status"] == 1, do: "正常", else: "停用"}</td><td>{dict["remark"]}</td></tr>
                          <% end %>
                        </tbody>
                      </table>
                    </div>
                  <% "jobs" -> %>
                    <div class="panel">
                      <button type="button" class="refresh" phx-click="refresh-jobs">刷新任务</button>
                      <%= if @job_feedback do %>
                        <p class="muted" role="status">{@job_feedback}</p>
                      <% end %>
                      <table>
                        <thead><tr><th>任务名称</th><th>分组</th><th>调用目标</th><th>Cron</th><th>状态</th><th>操作</th></tr></thead>
                        <tbody>
                          <%= for job <- @job_rows do %>
                            <tr>
                              <td>{job["jobName"]}</td>
                              <td>{job["jobGroup"]}</td>
                              <td>{job["invokeTarget"]}</td>
                              <td>{job["cronExpression"]}</td>
                              <td>{job["statusStr"]}</td>
                              <td>
                                <button type="button" class="refresh" phx-click="run-job" phx-value-job-id={job["jobId"]}>立即执行</button>
                                <button type="button" class="refresh" phx-click="toggle-job-status" phx-value-job-id={job["jobId"]} phx-value-status={if job["status"] == 1, do: 0, else: 1}>
                                  {if job["status"] == 1, do: "暂停", else: "启用"}
                                </button>
                              </td>
                            </tr>
                          <% end %>
                        </tbody>
                      </table>
                    </div>
                <% end %>
                </div>
              <% else %>
                <div class="card">
                  <h2>登录成功</h2>
                  <p class="muted">当前账号没有管理后台权限。</p>
                  <button type="button" class="secondary" phx-click="logout">退出</button>
                </div>
              <% end %>
            <% else %>
              <div class="brand">
                <p>Keystone Phoenix</p>
                <h1>管理后台正在迁移到 LiveView</h1>
                <p>
                  这个页面运行在 Phoenix LiveView 上，认证和业务数据由 Elixir、PostgreSQL 与 Redis 提供。
                  后续管理页面会继续在这里逐步替换原来的 Java 前端。
                </p>
              </div>
              <div class="card">
                <form id="login-form" phx-submit="login">
                  <h2>登录</h2>
                  <label for="username">用户名</label>
                  <input id="username" name="username" value={@username} autocomplete="username" required />
                  <label for="password">密码</label>
                  <input id="password" name="password" type="password" autocomplete="current-password" required />
                  <%= if @login_error do %>
                    <p class="error" role="alert">{@login_error}</p>
                  <% end %>
                  <button type="submit">登录</button>
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
