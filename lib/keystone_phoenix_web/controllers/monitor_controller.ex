defmodule KeystonePhoenixWeb.MonitorController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      cache_info: "cache:refresh",
      server_info: "server:read",
      online_users: "online-session:read",
      logout_online_user: "online-session:revoke",
      network_status_stream: "server:read",
      security_metrics: "audit:read",
      security_report: "audit:read"
    }

  plug KeystonePhoenixWeb.Plugs.RequireResourceScope, resource: :session

  alias KeystonePhoenix.Monitor
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns ETS cache statistics."
  def cache_info(conn, _params) do
    case Monitor.cache_info(authorization: %{principal: conn.assigns.current_user}) do
      {:ok, info} -> json(conn, ApiResponse.ok(info))
      {:error, :unavailable} -> render_error(conn, :unavailable)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Returns host and BEAM runtime information."
  def server_info(conn, _params) do
    case Monitor.server_info(authorization: %{principal: conn.assigns.current_user}) do
      {:ok, info} -> json(conn, ApiResponse.ok(info))
      {:error, :unavailable} -> render_error(conn, :unavailable)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Returns authenticated online refresh sessions."
  def online_users(conn, params) do
    case Monitor.online_users(params, authorization: %{principal: conn.assigns.current_user}) do
      {:ok, users} -> json(conn, ApiResponse.ok(users))
      {:error, :unavailable} -> render_error(conn, :unavailable)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Revokes an online refresh session."
  def logout_online_user(conn, %{"token_id" => token_id}) do
    case Monitor.logout_online_user(token_id,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, :unavailable} -> render_error(conn, :unavailable)
    end
  end

  @doc "Streams one network status snapshot; the frontend reconnects for updates."
  def network_status_stream(conn, _params) do
    case Monitor.network_status(authorization: %{principal: conn.assigns.current_user}) do
      {:error, reason} ->
        render_error(conn, reason)

      network_status ->
        payload =
          "event: network-status\ndata: " <> Jason.encode!(network_status) <> "\n\n"

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
  end

  @doc "Returns security operation metrics and a redacted audit report."
  def security_metrics(conn, _params) do
    case KeystonePhoenix.Security.metrics(authorization: %{principal: conn.assigns.current_user}) do
      {:ok, metrics} -> json(conn, ApiResponse.ok(metrics))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def security_report(conn, params) do
    case KeystonePhoenix.Security.report(
           params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, report} ->
        json(conn, ApiResponse.ok(report))

      {:error, :invalid_horizon} ->
        render_error(conn, :validation_failed, "horizonDays 无效")

      {:error, :invalid_window} ->
        render_error(conn, :validation_failed, "时间范围无效")

      {:error, :invalid_time} ->
        render_error(conn, :validation_failed, "时间格式无效")

      {:error, :unsupported_credential_filter} ->
        render_error(conn, :validation_failed, "当前报告不支持凭据筛选")

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  defp render_error(conn, :not_found) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(:validation_failed, "找不到在线会话"))
  end

  defp render_error(conn, :unavailable) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(:authorization_unavailable, "监控服务暂不可用"))
  end

  defp render_error(conn, :permission_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:permission_denied, "没有操作权限"))
  end

  defp render_error(conn, :data_scope_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:data_scope_denied, "没有数据权限"))
  end

  defp render_error(conn, :validation_failed, message) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, message))
  end
end
