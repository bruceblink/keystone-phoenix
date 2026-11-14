defmodule KeystonePhoenixWeb.Plugs.RequireHttps do
  @moduledoc "在生产入口拒绝没有 HTTPS 证明的请求。"

  import Plug.Conn

  @doc "返回 Plug 初始化参数。"
  def init(opts), do: opts

  @doc "生产配置开启时要求原始请求或受信转发协议使用 HTTPS。"
  def call(conn, _opts) do
    if Application.get_env(:keystone_phoenix, :force_ssl_enabled, false) and not https?(conn) do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("x-frame-options", "DENY")
      |> send_resp(
        426,
        Jason.encode!(
          KeystonePhoenixWeb.ApiResponse.error(:authorization_unavailable, "HTTPS is required")
        )
      )
      |> halt()
    else
      conn
    end
  end

  defp https?(conn) do
    conn.scheme == :https or
      Enum.any?(get_req_header(conn, "x-forwarded-proto"), fn value ->
        case String.split(value, ",") do
          [first | _] -> String.trim(first) == "https"
          _ -> false
        end
      end)
  end
end
