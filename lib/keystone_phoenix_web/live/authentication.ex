defmodule KeystonePhoenixWeb.Live.Authentication do
  @moduledoc "Checks current authentication before protected LiveView callbacks."

  import Phoenix.Component, only: [assign: 2]

  require Logger

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Captcha
  alias KeystonePhoenix.Role
  alias KeystonePhoenixWeb.Live.LoginState

  @public_events ~w(login refresh-captcha logout)

  def guard_event(event, _params, socket) when event in @public_events, do: {:cont, socket}
  def guard_event(_event, _params, socket), do: authenticate(socket)
  def guard_info(_message, socket), do: authenticate(socket)

  @doc "Captures permission and data-scope fields; display-only profile changes remain valid."
  def context(user, permissions) do
    %{
      user: Map.take(user, ~w(userId isAdmin roleId deptId)),
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

  defp role_context(nil), do: nil

  defp role_context(role_id) do
    case Role.get_role(role_id) do
      {:ok, role} -> Map.take(role, [:role_key, :data_scope, :dept_id_set, :status, :deleted])
      {:error, :not_found} -> nil
    end
  end
end
