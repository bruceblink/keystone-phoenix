defmodule KeystonePhoenixWeb.LoginLive do
  use Phoenix.LiveView

  import Phoenix.Component

  alias KeystonePhoenix.Auth

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       username: "",
       password: "",
       login_error: nil,
       current_user: nil,
       access_token: nil,
       refresh_token: nil
     )}
  end

  @impl true
  def handle_event("login", %{"username" => username, "password" => password}, socket) do
    username = String.trim(username)

    case Auth.login_plaintext(username, password) do
      {:ok, tokens} ->
        {:noreply,
         assign(socket,
           username: username,
           password: "",
           login_error: nil,
           current_user: tokens.current_user,
           access_token: tokens.token,
           refresh_token: tokens.refresh_token
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
  def handle_event("logout", _params, socket) do
    Auth.logout(socket.assigns.refresh_token)

    {:noreply,
     assign(socket,
       password: "",
       login_error: nil,
       current_user: nil,
       access_token: nil,
       refresh_token: nil
     )}
  end

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
          @media (max-width: 720px) { .shell { grid-template-columns: 1fr; } main { padding: 32px 0; } .brand h1 { font-size: 34px; } }
        </style>
      </head>
      <body>
        <main>
          <section class="shell">
            <div class="brand">
              <p>Keystone Phoenix</p>
              <h1>管理后台正在迁移到 LiveView</h1>
              <p>
                这个页面运行在 Phoenix LiveView 上，认证和业务数据由 Elixir、PostgreSQL 与 Redis 提供。
                后续管理页面会继续在这里逐步替换原来的 Java 前端。
              </p>
            </div>
            <div class="card">
              <%= if @current_user do %>
                <div class="user">
                  <div>
                    <strong>{@current_user["nickname"] || @current_user["username"]}</strong>
                    <span>@{@current_user["username"]}</span>
                  </div>
                  <span>已登录</span>
                </div>
                <button type="button" class="secondary" phx-click="logout">退出登录</button>
              <% else %>
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
              <% end %>
            </div>
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
