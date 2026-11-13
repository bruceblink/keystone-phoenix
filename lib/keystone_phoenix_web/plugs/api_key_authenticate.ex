defmodule KeystonePhoenixWeb.Plugs.ApiKeyAuthenticate do
  @moduledoc "使用 ApiKey Authorization 头建立服务主体 Principal。"

  import Plug.Conn

  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenixWeb.ApiResponse

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["ApiKey " <> value] <- get_req_header(conn, "authorization"),
         {:ok, principal} <- ApiKey.authenticate(value, conn.remote_ip) do
      assign(conn, :api_key_principal, principal)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(ApiResponse.error(:invalid_credential, "API Key 无效或已过期"))
        |> halt()
    end
  end
end
