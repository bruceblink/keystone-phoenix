defmodule KeystonePhoenixWeb.Plugs.RejectApiKey do
  @moduledoc "拒绝 API Key 进入仅允许人类会话的认证、密码和密钥管理入口。"

  import Plug.Conn

  alias KeystonePhoenixWeb.ApiResponse

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{api_key_principal: _principal}} = conn, _opts) do
    conn
    |> put_status(:forbidden)
    |> Phoenix.Controller.json(ApiResponse.error(:permission_denied, "该接口不支持 API Key"))
    |> halt()
  end

  def call(conn, _opts), do: conn
end
