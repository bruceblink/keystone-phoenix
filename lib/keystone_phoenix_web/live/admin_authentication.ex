defmodule KeystonePhoenixWeb.Live.AdminAuthentication do
  @moduledoc "管理页面认证会话的失效处理。"

  alias KeystonePhoenix.Auth
  alias KeystonePhoenixWeb.Live.Authentication

  @doc "撤销刷新令牌并将 LiveView 返回登录状态。"
  def expire_authentication(socket, message) do
    Auth.logout(socket.assigns.refresh_token)
    Authentication.expire(socket, message)
  end
end
