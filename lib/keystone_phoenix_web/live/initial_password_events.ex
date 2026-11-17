defmodule KeystonePhoenixWeb.Live.InitialPasswordEvents do
  @moduledoc "处理首次改密表单事件，并避免把密码写入 LiveView assigns。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.LoginLimiter
  alias KeystonePhoenix.Log

  # 密码只存在于本次事件参数中；表单不使用 phx-change，因此不会进入 assigns。
  def change(params, socket, remote_ip) do
    current_password = params["currentPassword"]
    new_password = params["newPassword"]
    confirm_password = params["confirmPassword"]
    username = String.trim(socket.assigns.username || "")

    cond do
      not socket.assigns.initial_password_required ->
        {:noreply, socket}

      username == "" or not non_empty_binary?(current_password) or
          not non_empty_binary?(new_password) ->
        error(socket, "请填写当前密码和新密码")

      new_password != confirm_password ->
        error(socket, "两次输入的新密码不一致")

      true ->
        update_password(username, current_password, new_password, remote_ip, socket)
    end
  end

  def cancel(socket) do
    {:noreply,
     assign(socket,
       initial_password_required: false,
       initial_password_error: nil,
       login_error: nil,
       login_notice: nil,
       password: ""
     )}
  end

  defp update_password(username, current_password, new_password, remote_ip, socket) do
    case LoginLimiter.check_liveview(username, remote_ip) do
      :allow ->
        Auth.change_initial_password(username, current_password, new_password)
        |> password_result(socket, username)

      {:deny, retry_after} ->
        Log.record_login_event(username, 0, "初始密码修改尝试过于频繁")
        error(socket, "操作过于频繁，请在 #{retry_after} 秒后重试")

      {:error, reason} when reason in [:capacity, :unavailable] ->
        error(socket, "密码修改服务暂不可用，请稍后重试")
    end
  end

  defp password_result({:ok, _result}, socket, username) do
    Log.record_login_event(username, 1, "初始密码修改成功")

    {:noreply,
     assign(socket,
       initial_password_required: false,
       initial_password_error: nil,
       login_error: nil,
       login_notice: "密码已更新，请使用新密码登录",
       password: ""
     )}
  end

  defp password_result({:error, :invalid_credentials}, socket, username) do
    Log.record_login_event(username, 0, "初始密码校验失败")
    error(socket, "当前密码不正确，请重试")
  end

  defp password_result({:error, :password_change_not_required}, socket, _username) do
    {:noreply,
     assign(socket,
       initial_password_required: false,
       initial_password_error: nil,
       login_notice: "账号状态已更新，请使用当前密码登录"
     )}
  end

  defp password_result({:error, :same_password}, socket, _username),
    do: error(socket, "新密码不能与当前密码相同")

  defp password_result({:error, %Ecto.Changeset{}}, socket, _username),
    do: error(socket, "新密码不符合系统密码要求，请检查后重试")

  defp password_result({:error, :validation_failed}, socket, _username),
    do: error(socket, "提交的数据无效，请检查后重试")

  defp password_result(_result, socket, _username),
    do: error(socket, "密码修改服务暂不可用，请稍后重试")

  defp error(socket, message),
    do: {:noreply, assign(socket, initial_password_error: message)}

  defp non_empty_binary?(value), do: is_binary(value) and value != ""
end
