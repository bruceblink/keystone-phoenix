defmodule KeystonePhoenixWeb.LogController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate when action in [:create_operation_log]
  plug KeystonePhoenixWeb.Plugs.Authenticate, admin: true
      when action in [:login_logs, :operation_logs, :delete_login_logs, :delete_operation_logs]

  alias KeystonePhoenix.Log
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns login audit records."
  def login_logs(conn, params) do
    json(conn, ApiResponse.ok(Log.list_login_logs(params)))
  end

  @doc "Soft deletes login audit records."
  def delete_login_logs(conn, %{"ids" => ids}) do
    case Log.delete_login_logs(String.split(ids, ",")) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def delete_login_logs(conn, _params), do: render_error(conn, :invalid_ids)

  @doc "Returns operation audit records."
  def operation_logs(conn, params) do
    json(conn, ApiResponse.ok(Log.list_operation_logs(params)))
  end

  @doc "Creates an operation audit record for the authenticated user."
  def create_operation_log(conn, params) do
    case Log.create_operation_log(params, conn.assigns.current_user, conn.request_path, conn.method) do
      {:ok, _log} -> json(conn, ApiResponse.ok())
      {:error, :invalid_log} -> render_error(conn, :invalid_log)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Soft deletes operation audit records."
  def delete_operation_logs(conn, %{"operationIds" => ids}) do
    case Log.delete_operation_logs(String.split(ids, ",")) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def delete_operation_logs(conn, _params), do: render_error(conn, :invalid_ids)

  defp render_error(conn, :invalid_ids) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10001, "日志编号无效"))
  end

  defp render_error(conn, :not_found) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(10002, "找不到请求的日志"))
  end

  defp render_error(conn, :invalid_log) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10003, "日志参数无效"))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(99999, "参数校验失败", errors))
  end
end
