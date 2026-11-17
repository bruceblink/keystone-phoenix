defmodule KeystonePhoenixWeb.Live.Authentication do
  @moduledoc "Checks current authentication before protected LiveView callbacks."

  import Phoenix.Component, only: [assign: 2]

  require Logger

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Mfa.RecentAuthentication
  alias KeystonePhoenix.Auth.Captcha
  alias KeystonePhoenix.Role
  alias KeystonePhoenixWeb.Live.LoginState

  @public_events ~w(login force-login cancel-force-login verify-login-mfa cancel-login-mfa refresh-captcha logout change-initial-password cancel-initial-password)
  @step_up_events ~w(begin-liveview-step-up verify-liveview-step-up cancel-liveview-step-up)

  # 用户导入对应 REST 的显式 enforce；其他敏感事件按账号 MFA 策略处理。
  @enforced_step_up_events ~w(import-users)

  # 这些事件会改变身份、授权结果、API Key 或在线会话，需要检查相应 REST 策略。
  @aal2_events ~w(
    import-users
    save-user
    toggle-user-status
    delete-user
    reset-user-password
    save-role
    toggle-role-status
    delete-role
    assign-role-user
    unassign-role-user
    save-api-key
    rotate-api-key
    revoke-api-key
    logout-online-user
  )

  def guard_event(event, _params, socket) when event in @public_events, do: {:cont, socket}

  def guard_event(event, _params, socket) when event in @step_up_events,
    do: authenticate(socket)

  def guard_event(event, _params, socket) do
    with {:cont, socket} <- authenticate(socket) do
      case if(
             event in @aal2_events,
             do: step_up_status(socket, event in @enforced_step_up_events),
             else: :allowed
           ) do
        :allowed ->
          {:cont, assign(socket, mfa_step_up_notice: nil)}

        :required ->
          {:halt,
           socket
           |> close_role_delete_confirmation(event)
           |> require_step_up(step_up_message(event))}

        :unavailable ->
          {:halt,
           socket
           |> close_role_delete_confirmation(event)
           |> require_step_up("认证服务暂不可用，请稍后重试")}
      end
    end
  end

  # 删除确认后的二次认证面板必须可见；认证完成后由用户重新确认删除。
  defp close_role_delete_confirmation(
         %{assigns: %{active_modal: "role-delete"}} = socket,
         "delete-role"
       ),
       do: assign(socket, active_modal: nil)

  defp close_role_delete_confirmation(socket, _event), do: socket

  def guard_info(_message, socket), do: authenticate(socket)

  @doc "核验当前 LiveView 会话是否完成有效的 TOTP 或恢复码 step-up。"
  def step_up_status(socket, enforce?) when is_boolean(enforce?) do
    case Auth.session_context(socket.assigns[:access_token]) do
      {:ok, context} ->
        user_id = Map.get(context.user, :user_id)

        RecentAuthentication.check(
          %{
            "sub" => user_id,
            "sid" => context.session_id,
            "client_id" => context.client_id,
            "jti" => context.access_token_id,
            "aal" => context.authentication_level,
            "amr" => context.amr
          },
          enforce?,
          false
        )

      _ ->
        :required
    end
  end

  # 个人改密沿用账号 MFA 策略；策略关闭时保持现有放行行为。
  def profile_password_step_up(socket), do: step_up_status(socket, false)

  # LiveView 事件和通用 AAL2 守卫共用相同的 step-up 面板状态。
  def require_step_up(socket, message) when is_binary(message) do
    assign(socket,
      mfa_step_up_required: true,
      mfa_step_up_challenge: nil,
      mfa_step_up_code: "",
      mfa_step_up_error: message,
      mfa_step_up_notice: nil
    )
  end

  @doc "Captures permission and data-scope fields; display-only profile changes remain valid."
  def context(user, permissions) do
    %{
      user: Map.take(user, ~w(userId roleId deptId)),
      roles: role_codes(user),
      permissions: Enum.sort(permissions),
      role: role_context(user["roleId"])
    }
  end

  def refresh_captcha(socket) do
    case Captcha.generate() do
      {:ok, captcha} ->
        assign(socket,
          captcha_enabled: is_binary(captcha.captcha_code_key),
          captcha_key: captcha.captcha_code_key,
          captcha_image: captcha.captcha_code_img
        )

      {:error, :unavailable} ->
        assign(socket,
          captcha_enabled: true,
          captcha_key: nil,
          captcha_image: nil,
          login_error: "验证码暂不可用，请刷新后重试"
        )
    end
  end

  def expire(socket, message) do
    socket
    |> LoginState.reset()
    |> refresh_captcha()
    |> assign(login_error: message)
  end

  defp authenticate(%{assigns: %{current_user: nil}} = socket), do: {:halt, socket}

  defp authenticate(socket) do
    with {:ok, user} <- Auth.authenticate_access_token(socket.assigns.access_token),
         current <- Auth.current_login_user(user),
         true <-
           context(current["userInfo"], current["permissions"]) == socket.assigns.auth_context do
      {:cont, assign(socket, current_user: current["userInfo"])}
    else
      _ ->
        Logger.info(
          "LiveView authentication expired user_id=#{socket.assigns.current_user["userId"]}"
        )

        Auth.logout(socket.assigns.refresh_token)
        {:halt, expire(socket, "登录状态已失效，请重新登录")}
    end
  end

  defp step_up_message("import-users"), do: "导入用户需要完成二次认证"
  defp step_up_message("change-profile-password"), do: "修改密码需要完成二次认证"
  defp step_up_message(_event), do: "此操作需要完成二次认证"

  defp role_context(nil), do: nil

  defp role_context(role_id) do
    case Role.get_role(role_id) do
      {:ok, role} -> Map.take(role, [:role_key, :data_scope, :dept_id_set, :status, :deleted])
      {:error, :not_found} -> nil
    end
  end

  # 角色关联变更可能不改变首选 role_id；保存完整角色编码集合，确保 LiveView
  # 的显式权限快照不会在角色集合变化后继续沿用。
  defp role_codes(user) when is_map(user) do
    user
    |> Map.get("roles", Map.get(user, "roleCodes", []))
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp role_codes(_user), do: []
end
