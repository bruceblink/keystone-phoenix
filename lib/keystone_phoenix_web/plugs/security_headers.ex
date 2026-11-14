defmodule KeystonePhoenixWeb.Plugs.SecurityHeaders do
  @moduledoc """
  为所有响应添加安全响应头，并按配置处理跨域预检请求。

  CORS 只允许运行时配置中的完整来源地址。没有匹配来源时不返回跨域响应头，
  这样浏览器会阻止跨域读取，同时不改变同源请求的业务状态码。
  """

  import Plug.Conn

  @security_headers [
    {"x-content-type-options", "nosniff"},
    {"x-frame-options", "DENY"},
    {"referrer-policy", "strict-origin-when-cross-origin"},
    {"permissions-policy", "camera=(), geolocation=(), microphone=()"},
    {"cross-origin-opener-policy", "same-origin"},
    {"content-security-policy",
     "default-src 'self'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; " <>
       "img-src 'self' data:; connect-src 'self' ws: wss:; " <>
       "style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'"}
  ]

  @cors_methods "GET,POST,PUT,PATCH,DELETE,OPTIONS"
  @cors_headers "authorization,content-type,x-request-id"

  @doc "返回 Plug 初始化参数。"
  def init(opts), do: opts

  @doc "添加安全响应头；允许来源的 OPTIONS 请求直接返回 204。"
  def call(conn, _opts) do
    conn = add_security_headers(conn)
    allowed_origins = allowed_origins()

    case request_origin(conn) do
      origin when is_binary(origin) ->
        if origin in allowed_origins do
          conn = add_cors_headers(conn, origin)

          if conn.method == "OPTIONS" do
            conn |> send_resp(204, "") |> halt()
          else
            conn
          end
        else
          conn
        end

      _ ->
        conn
    end
  end

  defp add_security_headers(conn) do
    headers =
      if Application.get_env(:keystone_phoenix, :force_ssl_enabled, false) do
        [{"strict-transport-security", "max-age=31536000; includeSubDomains"} | @security_headers]
      else
        @security_headers
      end

    Enum.reduce(headers, conn, fn {name, value}, acc -> put_resp_header(acc, name, value) end)
  end

  defp add_cors_headers(conn, origin) do
    conn
    |> put_resp_header("access-control-allow-origin", origin)
    |> put_resp_header("access-control-allow-methods", @cors_methods)
    |> put_resp_header("access-control-allow-headers", @cors_headers)
    |> put_resp_header("access-control-max-age", "600")
    |> put_resp_header("vary", "origin")
  end

  defp request_origin(conn) do
    case get_req_header(conn, "origin") do
      [origin | _] when origin != "" -> origin
      _ -> nil
    end
  end

  defp allowed_origins do
    case Application.get_env(:keystone_phoenix, :cors_allowed_origins, []) do
      origins when is_list(origins) -> origins
      _ -> []
    end
  end
end
