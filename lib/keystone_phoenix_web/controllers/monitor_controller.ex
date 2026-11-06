defmodule KeystonePhoenixWeb.MonitorController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      cache_info: "monitor:cache:list",
      server_info: "monitor:server:list",
      online_users: "monitor:online:list",
      logout_online_user: "monitor:online:forceLogout"
    }

  alias KeystonePhoenix.Monitor
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns ETS cache statistics."
  def cache_info(conn, _params) do
    case Monitor.cache_info() do
      {:ok, info} -> json(conn, ApiResponse.ok(info))
      {:error, :unavailable} -> render_error(conn, :unavailable)
    end
  end

  @doc "Returns host and BEAM runtime information."
  def server_info(conn, _params) do
    case Monitor.server_info() do
      {:ok, info} -> json(conn, ApiResponse.ok(info))
      {:error, :unavailable} -> render_error(conn, :unavailable)
    end
  end

  @doc "Returns authenticated online refresh sessions."
  def online_users(conn, params) do
    case Monitor.online_users(params) do
      {:ok, users} -> json(conn, ApiResponse.ok(users))
      {:error, :unavailable} -> render_error(conn, :unavailable)
    end
  end

  @doc "Revokes an online refresh session."
  def logout_online_user(conn, %{"token_id" => token_id}) do
    case Monitor.logout_online_user(token_id) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, :unavailable} -> render_error(conn, :unavailable)
    end
  end

  @doc "Streams one network status snapshot; the frontend reconnects for updates."
  def network_status_stream(conn, _params) do
    payload =
      "event: network-status\ndata: " <>
        Jason.encode!(Monitor.network_status()) <>
        "\n\n"

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)

    case chunk(conn, payload) do
      {:ok, conn} -> conn
      {:error, _reason} -> conn
    end
  end

  defp render_error(conn, :not_found) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(10001, "找不到在线会话"))
  end

  defp render_error(conn, :unavailable) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(50301, "监控服务暂不可用"))
  end
end
