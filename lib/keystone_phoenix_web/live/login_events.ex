defmodule KeystonePhoenixWeb.Live.LoginEvents do
  @moduledoc "认证相关 LiveView 事件，包括登录 MFA 和敏感操作的 step-up。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Captcha
  alias KeystonePhoenix.Auth.LoginLimiter
  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Log
  alias KeystonePhoenixWeb.Live.AdminSupport
  alias KeystonePhoenixWeb.Live.Authentication
  alias KeystonePhoenixWeb.Live.InitialPasswordEvents
  alias KeystonePhoenixWeb.LoginNotifications

  def handle_login(%{"username" => username, "password" => password} = params, socket, remote_ip) do
    username = String.trim(username)
    socket = assign(socket, login_notice: nil, initial_password_error: nil)

    result =
      case LoginLimiter.check_liveview(username, remote_ip) do
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

    handle_login_result(result, username, password, false, socket)
  end

  def handle_login(_params, socket, _remote_ip),
    do: {:noreply, assign(socket, login_error: "请输入用户名和密码")}

  # 密码只存在于本次事件参数中；表单不使用 phx-change，因此不会进入 assigns。
  def handle_initial_password(
        params,
        socket,
        remote_ip
      ),
      do: InitialPasswordEvents.change(params, socket, remote_ip)

  def cancel_initial_password(socket), do: InitialPasswordEvents.cancel(socket)

  def handle_force_login(_params, socket) do
    case socket.assigns[:pending_login] do
      %{username: username, password: password} ->
        handle_login_result(
          Auth.login_plaintext(username, password, true),
          username,
          password,
          true,
          socket
        )

      _ ->
        handle_force_mfa_login(socket)
    end
  end

  defp handle_force_mfa_login(socket) do
    challenge = socket.assigns[:mfa_challenge]
    resolved_challenge_id = challenge_id(challenge)

    if socket.assigns[:pending_mfa_login] and is_binary(socket.assigns[:mfa_code]) and
         resolved_challenge_id do
      client_id =
        Map.get(challenge || %{}, :client_id) || Map.get(challenge || %{}, "clientId") || "web"

      case Auth.complete_mfa_login(
             socket.assigns.mfa_username,
             resolved_challenge_id,
             client_id,
             String.trim(socket.assigns.mfa_code),
             true,
             liveview_ip(socket)
           ) do
        {:ok, %{tokens: tokens}} ->
          {:noreply, authenticated_socket(socket, socket.assigns.mfa_username, tokens)}

        {:error, reason} ->
          {:noreply, assign(socket, mfa_error: login_mfa_error(reason))}
      end
    else
      {:noreply,
       assign(socket,
         login_confirm_open: false,
         pending_mfa_login: false,
         login_error: "登录确认已失效，请重新提交登录"
       )}
    end
  end

  defp handle_login_result({:ok, tokens}, username, _password, _force_login, socket),
    do: {:noreply, authenticated_socket(socket, username, tokens)}

  defp handle_login_result(
         {:error, :precondition_required},
         username,
         _password,
         _force_login,
         socket
       ) do
    Log.record_login_event(username, 0, "需要修改初始密码")

    {:noreply,
     assign(socket,
       username: username,
       password: "",
       login_error: nil,
       login_notice: nil,
       initial_password_required: true,
       initial_password_error: nil,
       login_confirm_open: false,
       pending_login: nil,
       pending_mfa_login: false,
       mfa_challenge: nil,
       mfa_username: "",
       mfa_code: "",
       mfa_error: nil
     )}
  end

  defp handle_login_result(
         {:mfa_required, %{challenge: challenge, username: challenge_username}},
         _username,
         password,
         force_login,
         socket
       ) do
    {:noreply,
     assign(socket,
       username: challenge_username,
       password: password,
       login_error: nil,
       login_confirm_open: false,
       pending_login: nil,
       pending_mfa_login: false,
       mfa_challenge: challenge,
       mfa_username: challenge_username,
       mfa_force_login: force_login,
       mfa_code: "",
       mfa_error: nil
     )}
  end

  defp handle_login_result({:error, :already_logged_in}, username, password, _force_login, socket) do
    Log.record_login_event(username, 0, "该账号已经登录")

    {:noreply,
     assign(socket,
       login_confirm_open: true,
       pending_login: %{username: username, password: password},
       pending_mfa_login: false,
       login_error: nil
     )}
  end

  defp handle_login_result(
         {:error, {:rate_limited, retry_after}},
         username,
         _password,
         _force_login,
         socket
       ) do
    Log.record_login_event(username, 0, "登录尝试过于频繁")
    login_error(socket, username, "登录尝试过于频繁，请在 #{retry_after} 秒后重试")
  end

  defp handle_login_result(
         {:error, :login_limiter_unavailable},
         username,
         _password,
         _force_login,
         socket
       ) do
    Log.record_login_event(username, 0, "限流服务暂不可用")
    login_error(socket, username, "登录服务暂不可用，请稍后重试")
  end

  defp handle_login_result({:error, reason}, username, _password, _force_login, socket)
       when reason in [:capacity, :unavailable] do
    Log.record_login_event(username, 0, "认证会话暂不可用")
    login_error(socket, username, "认证会话暂不可用，请稍后重试")
  end

  defp handle_login_result(
         {:error, :mfa_enrollment_required},
         username,
         _password,
         _force_login,
         socket
       ) do
    Log.record_login_event(username, 0, "账号尚未完成 MFA 注册")
    login_error(socket, username, "账号需要先完成 MFA 注册")
  end

  defp handle_login_result({:error, reason}, username, _password, _force_login, socket)
       when reason in [:captcha_required, :captcha_invalid, :captcha_expired] do
    message = captcha_error(reason)
    Log.record_login_event(username, 0, message)
    login_error(socket, username, message)
  end

  defp handle_login_result(_result, username, _password, _force_login, socket) do
    Log.record_login_event(username, 0, "用户名或密码错误")
    login_error(socket, username, "用户名或密码错误")
  end

  defp login_error(socket, username, message) do
    {:noreply,
     socket
     |> Authentication.refresh_captcha()
     |> assign(
       username: username,
       password: "",
       login_error: message,
       login_notice: nil,
       initial_password_required: false,
       initial_password_error: nil,
       login_confirm_open: false,
       pending_login: nil,
       pending_mfa_login: false
     )}
  end

  defp captcha_error(:captcha_required), do: "请输入验证码"
  defp captcha_error(:captcha_invalid), do: "验证码错误，请重试"
  defp captcha_error(:captcha_expired), do: "验证码已过期，请重试"

  def handle_event("verify-login-mfa", %{"code" => code}, socket) when is_binary(code) do
    challenge = socket.assigns[:mfa_challenge]

    case challenge_id(challenge) do
      nil ->
        {:noreply, assign(socket, mfa_error: "MFA 验证请求已失效，请重新登录")}

      challenge_id ->
        client_id = Map.get(challenge, :client_id) || Map.get(challenge, "clientId") || "web"

        case Auth.complete_mfa_login(
               socket.assigns.mfa_username,
               challenge_id,
               client_id,
               String.trim(code),
               socket.assigns[:mfa_force_login] || false,
               liveview_ip(socket)
             ) do
          {:ok, %{tokens: tokens}} ->
            {:noreply, authenticated_socket(socket, socket.assigns.mfa_username, tokens)}

          {:error, :already_logged_in} ->
            Log.record_login_event(socket.assigns.mfa_username, 0, "该账号已经登录")

            {:noreply,
             assign(socket,
               login_confirm_open: true,
               pending_mfa_login: true,
               mfa_error: nil,
               mfa_code: String.trim(code)
             )}

          {:error, reason} ->
            {:noreply, assign(socket, mfa_error: login_mfa_error(reason), mfa_code: "")}
        end
    end
  end

  def handle_event("verify-login-mfa", _params, socket),
    do: {:noreply, assign(socket, mfa_error: "请输入 MFA 验证码")}

  def handle_event("cancel-login-mfa", _params, socket) do
    {:noreply,
     socket
     |> Authentication.refresh_captcha()
     |> assign(
       mfa_challenge: nil,
       mfa_username: "",
       mfa_force_login: false,
       mfa_code: "",
       mfa_error: nil,
       pending_mfa_login: false,
       login_error: nil
     )}
  end

  def handle_event("begin-liveview-step-up", _params, socket) do
    with {:ok, context} <- Auth.session_context(socket.assigns.access_token),
         {:ok, challenge} <-
           Mfa.begin_step_up(context.user.user_id, context.client_id, context.session_id) do
      {:noreply,
       assign(socket,
         mfa_step_up_required: true,
         mfa_step_up_challenge: challenge,
         mfa_step_up_code: "",
         mfa_step_up_error: nil
       )}
    else
      {:error, :mfa_not_enrolled} ->
        {:noreply, assign(socket, mfa_step_up_error: "当前账号尚未启用 MFA，无法完成二次认证")}

      {:error, reason} ->
        {:noreply, assign(socket, mfa_step_up_error: step_up_error(reason))}
    end
  end

  def handle_event("verify-liveview-step-up", %{"code" => code}, socket)
      when is_binary(code) do
    case challenge_id(socket.assigns[:mfa_step_up_challenge]) do
      nil ->
        {:noreply, assign(socket, mfa_step_up_error: "MFA 验证请求已失效，请重新开始")}

      challenge_id ->
        case Auth.complete_mfa_step_up(
               socket.assigns.access_token,
               challenge_id,
               String.trim(code),
               liveview_ip(socket)
             ) do
          {:ok, result} ->
            {:noreply,
             assign(socket,
               access_token: result.token,
               mfa_step_up_required: false,
               mfa_step_up_challenge: nil,
               mfa_step_up_code: "",
               mfa_step_up_error: nil,
               mfa_step_up_notice: "二次认证已完成，请重新提交刚才的操作"
             )}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               mfa_step_up_error: step_up_error(reason),
               mfa_step_up_code: ""
             )}
        end
    end
  end

  def handle_event("verify-liveview-step-up", _params, socket),
    do: {:noreply, assign(socket, mfa_step_up_error: "请输入 MFA 验证码")}

  def handle_event("cancel-liveview-step-up", _params, socket) do
    {:noreply,
     assign(socket,
       mfa_step_up_required: false,
       mfa_step_up_challenge: nil,
       mfa_step_up_code: "",
       mfa_step_up_error: nil,
       mfa_step_up_notice: nil
     )}
  end

  # 登录和登录 MFA 共用同一条会话初始化路径，避免两种认证结果产生不同的面板数据。
  def authenticated_socket(socket, username, tokens) do
    Log.record_login_event(username, 1, "登录成功")
    current_user = Map.get(tokens.current_user, "userInfo", tokens.current_user)
    permissions = Map.get(tokens.current_user, "permissions", [])

    admin? = Authz.admin?(Map.put(current_user, :permissions, permissions))

    dashboard =
      if admin?,
        do: AdminSupport.load_dashboard(),
        else: AdminSupport.load_dashboard_for_permissions(current_user, permissions)

    panel_access = AdminSupport.panel_access(permissions, current_user)

    socket
    |> LoginNotifications.cancel()
    |> assign(
      username: username,
      password: "",
      login_error: nil,
      login_notice: nil,
      initial_password_required: false,
      initial_password_error: nil,
      login_confirm_open: false,
      pending_login: nil,
      pending_mfa_login: false,
      mfa_challenge: nil,
      mfa_username: "",
      mfa_force_login: false,
      mfa_code: "",
      mfa_error: nil,
      mfa_step_up_required: false,
      mfa_step_up_challenge: nil,
      mfa_step_up_code: "",
      mfa_step_up_error: nil,
      mfa_step_up_notice: nil,
      current_user: current_user,
      permissions: permissions,
      auth_context: Authentication.context(current_user, permissions),
      panel_access: panel_access,
      read_only: not admin?,
      access_token: tokens.token,
      refresh_token: tokens.refresh_token,
      active_panel: "monitor",
      notifications_open: false,
      notifications_loading: false,
      notifications_error: nil,
      notification_read_error: nil,
      notification_read_error_action: nil,
      notification_read_error_label: nil,
      notifications_async_name: nil,
      selected_notification_id: nil,
      notifications_user_id: Map.get(current_user, "userId") || Map.get(current_user, :user_id),
      notifications_unread_count: 0,
      in_app_notifications: [],
      active_modal: nil,
      user_rows: dashboard.user_rows,
      user_total: dashboard[:user_total] || length(dashboard.user_rows),
      dept_rows: dashboard.dept_rows,
      dept_feedback: nil,
      dept_form: AdminSupport.empty_dept_form(),
      post_rows: dashboard.post_rows,
      post_total: dashboard[:post_total] || length(dashboard.post_rows),
      post_feedback: nil,
      post_form: AdminSupport.empty_post_form(),
      config_rows: dashboard.config_rows,
      config_total: length(dashboard.config_rows),
      config_feedback: nil,
      config_form: AdminSupport.empty_config_form(),
      dict_type_rows: dashboard.dict_type_rows,
      dict_data_rows: dashboard.dict_data_rows,
      dict_data_total: length(dashboard.dict_data_rows),
      dict_feedback: nil,
      dict_type_form: AdminSupport.empty_dict_type_form(),
      dict_data_form: AdminSupport.empty_dict_data_form(dashboard.selected_dict_type),
      dict_data_filter: %{"keyword" => ""},
      selected_dict_type: dashboard.selected_dict_type,
      job_rows: dashboard.job_rows,
      job_total: dashboard[:job_total] || length(dashboard.job_rows),
      job_feedback: nil,
      job_form: AdminSupport.empty_job_form(),
      job_targets: Job.invoke_targets(),
      job_log_rows: dashboard.job_log_rows,
      job_log_total: dashboard[:job_log_total] || length(dashboard.job_log_rows),
      job_log_feedback: nil,
      role_rows: dashboard.role_rows,
      role_page_rows: Enum.take(dashboard.role_rows, 20),
      role_total: length(dashboard.role_rows),
      selected_role_id: "",
      selected_role_name: "",
      allocated_role_user_rows: [],
      unallocated_role_user_rows: [],
      role_user_feedback: nil,
      role_feedback: nil,
      role_form: AdminSupport.empty_role_form(),
      role_permission_query: "",
      menu_rows: dashboard.menu_rows,
      menu_feedback: nil,
      menu_form: AdminSupport.empty_menu_form(),
      notice_rows: dashboard.notice_rows,
      notice_total: length(dashboard.notice_rows),
      notice_feedback: nil,
      notice_form: AdminSupport.empty_notice_form(),
      login_log_rows: dashboard.login_log_rows,
      login_log_total: dashboard[:login_log_total] || length(dashboard.login_log_rows),
      operation_log_rows: dashboard.operation_log_rows,
      operation_log_total:
        dashboard[:operation_log_total] || length(dashboard.operation_log_rows),
      log_feedback: nil,
      user_form: AdminSupport.empty_user_form(),
      user_feedback: nil,
      profile_form: current_user,
      password_form: AdminSupport.empty_password_form(),
      profile_loaded: false,
      profile_feedback: nil,
      monitor_loading: false,
      monitor_initial_error: nil
    )
    |> load_initial_monitor()
    |> LoginNotifications.refresh()
  end

  # 登录成功后立即读取默认监控面板，失败时保留可重试状态。
  defp load_initial_monitor(socket) do
    if AdminSupport.monitor_access?(socket),
      do:
        socket
        |> assign(monitor_loading: true, monitor_initial_error: nil)
        |> AdminSupport.assign_monitor(),
      else: socket
  end

  defp challenge_id(%{} = challenge) do
    Map.get(challenge, :id) || Map.get(challenge, :challenge_id) || Map.get(challenge, "id") ||
      Map.get(challenge, "challengeId")
  end

  defp challenge_id(_challenge), do: nil

  defp login_mfa_error(:invalid_mfa_code), do: "MFA 验证码错误，请重试"
  defp login_mfa_error(:invalid_challenge), do: "MFA 验证请求已失效，请重新登录"
  defp login_mfa_error(:rate_limited), do: "MFA 验证尝试过于频繁，请稍后重试"
  defp login_mfa_error(:unavailable), do: "认证服务暂不可用，请稍后重试"
  defp login_mfa_error(_reason), do: "MFA 验证失败，请重试"

  defp step_up_error(:invalid_mfa_code), do: "MFA 验证码错误，请重试"
  defp step_up_error(:invalid_challenge), do: "MFA 验证请求已失效，请重新开始"
  defp step_up_error(:rate_limited), do: "MFA 验证尝试过于频繁，请稍后重试"
  defp step_up_error(:invalid_token), do: "登录状态已失效，请重新登录"
  defp step_up_error(:unavailable), do: "认证服务暂不可用，请稍后重试"
  defp step_up_error(_reason), do: "二次认证失败，请重试"

  defp liveview_ip(socket), do: Map.get(socket.assigns, :remote_ip)
end
