defmodule KeystonePhoenixWeb.AuthCapabilitiesController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.RejectApiKey
  plug KeystonePhoenixWeb.Plugs.Authenticate

  alias KeystonePhoenix.Authz.Capabilities
  alias KeystonePhoenixWeb.ApiResponse

  @doc "返回当前人类会话的有效权限和资源列表范围。"
  def show(conn, _params) do
    case Capabilities.for_user(conn.assigns.current_user) do
      {:ok, capabilities} ->
        json(conn, ApiResponse.ok(capabilities))

      {:error, :authorization_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(ApiResponse.error(:authorization_unavailable, "授权信息暂不可用"))
    end
  end
end
