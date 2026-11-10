defmodule KeystonePhoenixWeb.Plugs.RateLimit do
  @moduledoc "Applies a per-node ETS request rate limit."

  import Plug.Conn

  alias KeystonePhoenix.RateLimiter
  alias KeystonePhoenixWeb.ApiResponse

  def init(opts), do: opts

  def call(conn, opts) do
    key = key(conn, opts)
    limit = Keyword.fetch!(opts, :limit)
    window = Keyword.fetch!(opts, :window)

    case RateLimiter.check(key, limit, window) do
      :allow -> conn
      {:deny, retry_after} -> reject(conn, retry_after)
      {:error, reason} when reason in [:capacity, :unavailable] -> unavailable(conn)
    end
  end

  defp key(conn, opts) do
    scope = Keyword.get(opts, :scope, :global)
    prefix = Keyword.get(opts, :key, conn.request_path)
    identity = if scope == :ip, do: remote_ip(conn), else: "global"
    "rate:#{prefix}:#{identity}"
  end

  defp reject(conn, retry_after) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(retry_after))
    |> put_status(:too_many_requests)
    |> Phoenix.Controller.json(ApiResponse.error(42901, "请求过于频繁，请稍后再试"))
    |> halt()
  end

  defp unavailable(conn) do
    conn
    |> put_status(:service_unavailable)
    |> Phoenix.Controller.json(ApiResponse.error(50302, "限流服务暂不可用，请稍后重试"))
    |> halt()
  end

  defp remote_ip(%Plug.Conn{remote_ip: {a, b, c, d}}), do: "#{a}.#{b}.#{c}.#{d}"
  defp remote_ip(%Plug.Conn{remote_ip: ip}), do: inspect(ip)
end
