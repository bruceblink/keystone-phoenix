defmodule KeystonePhoenixWeb.Live.LoginEvents do
  @moduledoc "认证相关 LiveView 事件，包括登录 MFA 和敏感操作的 step-up。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Log
  alias KeystonePhoenixWeb.Live.AdminSupport
  alias KeystonePhoenixWeb.Live.Authentication

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
               false,
               liveview_ip(socket)
             ) do
          {:ok, %{tokens: tokens}} ->
            {:noreply, authenticated_socket(socket, socket.assigns.mfa_username, tokens)}

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
       mfa_code: "",
       mfa_error: nil,
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

    assign(socket,
      username: username,
      password: "",
      login_error: nil,
      mfa_challenge: nil,
      mfa_username: "",
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
      selected_notification_id: nil,
      in_app_notifications: dashboard.in_app_notifications,
      active_modal: nil,
      user_rows: dashboard.user_rows,
      dept_rows: dashboard.dept_rows,
      dept_feedback: nil,
      dept_form: AdminSupport.empty_dept_form(),
      post_rows: dashboard.post_rows,
      post_feedback: nil,
      post_form: AdminSupport.empty_post_form(),
      config_rows: dashboard.config_rows,
      config_feedback: nil,
      config_form: AdminSupport.empty_config_form(),
      dict_type_rows: dashboard.dict_type_rows,
      dict_data_rows: dashboard.dict_data_rows,
      dict_feedback: nil,
      dict_type_form: AdminSupport.empty_dict_type_form(),
      dict_data_form: AdminSupport.empty_dict_data_form(dashboard.selected_dict_type),
      selected_dict_type: dashboard.selected_dict_type,
      job_rows: dashboard.job_rows,
      job_feedback: nil,
      job_form: AdminSupport.empty_job_form(),
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
      role_form: AdminSupport.empty_role_form(),
      menu_rows: dashboard.menu_rows,
      menu_feedback: nil,
      menu_form: AdminSupport.empty_menu_form(),
      notice_rows: dashboard.notice_rows,
      notice_feedback: nil,
      notice_form: AdminSupport.empty_notice_form(),
      login_log_rows: dashboard.login_log_rows,
      operation_log_rows: dashboard.operation_log_rows,
      log_feedback: nil,
      user_form: AdminSupport.empty_user_form(),
      user_feedback: nil,
      profile_form: current_user,
      password_form: AdminSupport.empty_password_form(),
      profile_feedback: nil
    )
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
