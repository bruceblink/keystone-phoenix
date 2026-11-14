defmodule KeystonePhoenixWeb.LogController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
       [
         permissions: %{
           login_logs: "login-log:read",
           export_login_logs: "login-log:export",
           delete_login_logs: "login-log:delete",
           operation_logs: "operation-log:read",
           export_operation_logs: "operation-log:export",
           delete_operation_logs: "operation-log:delete"
         }
       ]
       when action in [
              :login_logs,
              :operation_logs,
              :delete_login_logs,
              :delete_operation_logs,
              :export_login_logs,
              :export_operation_logs
            ]

  plug KeystonePhoenixWeb.Plugs.RequireResourceScope,
       [resource: :audit]
       when action in [
              :login_logs,
              :operation_logs,
              :delete_login_logs,
              :delete_operation_logs,
              :export_login_logs,
              :export_operation_logs
            ]

  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Log
  alias KeystonePhoenixWeb.ApiResponse
  alias KeystonePhoenixWeb.ExcelResponse

  @login_export_headers ["ID", "用户名", "ip地址", "登录地点", "操作系统", "浏览器", "状态", "描述", "登录时间"]
  @operation_export_headers [
    "ID",
    "业务类型",
    "请求方法",
    "请求模块",
    "请求地址",
    "调用方法",
    "操作人类型",
    "用户ID",
    "用户名",
    "ip地址",
    "ip地点",
    "部门ID",
    "部门",
    "操作参数",
    "操作结果",
    "状态",
    "错误堆栈",
    "操作时间"
  ]

  @doc "Returns login audit records."
  def login_logs(conn, params) do
    case Log.list_login_logs(params, authorization: %{principal: conn.assigns.current_user}) do
      {:ok, rows} -> json(conn, ApiResponse.ok(rows))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Soft deletes login audit records."
  def delete_login_logs(conn, %{"ids" => ids}) do
    case Log.delete_login_logs(String.split(ids, ","),
           authorization: %{principal: conn.assigns.current_user}
         ) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def delete_login_logs(conn, _params), do: render_error(conn, :invalid_ids)

  @doc "Returns operation audit records."
  def operation_logs(conn, params) do
    case Log.list_operation_logs(params, authorization: %{principal: conn.assigns.current_user}) do
      {:ok, rows} -> json(conn, ApiResponse.ok(rows))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Exports all login audit records matching the current filters."
  def export_login_logs(conn, params) do
    authorization = [authorization: %{principal: conn.assigns.current_user}]

    case Log.authorize_read(authorization, "login-log:export") do
      :ok ->
        rows = Excel.all_rows(&Log.list_login_logs/1, params)

        ExcelResponse.send_xlsx(
          conn,
          "login-logs.xlsx",
          @login_export_headers,
          Enum.map(rows, &login_export_row/1)
        )

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @doc "Exports all operation audit records matching the current filters."
  def export_operation_logs(conn, params) do
    authorization = [authorization: %{principal: conn.assigns.current_user}]

    case Log.authorize_read(authorization, "operation-log:export") do
      :ok ->
        rows = Excel.all_rows(&Log.list_operation_logs/1, params)

        ExcelResponse.send_xlsx(
          conn,
          "operation-logs.xlsx",
          @operation_export_headers,
          Enum.map(rows, &operation_export_row/1)
        )

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @doc "Soft deletes operation audit records."
  def delete_operation_logs(conn, %{"operationIds" => ids}) do
    case Log.delete_operation_logs(String.split(ids, ","),
           authorization: %{principal: conn.assigns.current_user}
         ) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def delete_operation_logs(conn, _params), do: render_error(conn, :invalid_ids)

  defp login_export_row(row) do
    [
      row["infoId"],
      row["username"],
      row["ipAddress"],
      row["loginLocation"],
      row["operationSystem"],
      row["browser"],
      login_status_label(row["status"]),
      row["msg"],
      row["loginTime"]
    ]
  end

  defp operation_export_row(row) do
    [
      row["operationId"],
      business_type_label(row["businessType"]),
      row["requestMethodStr"] || request_method_label(row["requestMethod"]),
      row["requestModule"],
      row["requestUrl"],
      row["calledMethod"],
      operator_type_label(row["operatorType"]),
      row["userId"],
      row["username"],
      row["operatorIp"],
      row["operatorLocation"],
      row["deptId"],
      row["deptName"],
      row["operationParam"],
      row["operationResult"],
      operation_status_label(row["status"]),
      row["errorStack"],
      row["operationTime"]
    ]
  end

  defp login_status_label(1), do: "登录成功"
  defp login_status_label(2), do: "退出成功"
  defp login_status_label(3), do: "注册"
  defp login_status_label(0), do: "登录失败"
  defp login_status_label(status), do: to_string(status || "")

  defp operation_status_label(1), do: "成功"
  defp operation_status_label(0), do: "失败"
  defp operation_status_label(status), do: to_string(status || "")

  defp request_method_label(1), do: "GET"
  defp request_method_label(2), do: "POST"
  defp request_method_label(3), do: "PUT"
  defp request_method_label(4), do: "DELETE"
  defp request_method_label(_status), do: "UNKNOWN"

  defp business_type_label(0), do: "其他操作"
  defp business_type_label(1), do: "添加"
  defp business_type_label(2), do: "修改"
  defp business_type_label(3), do: "删除"
  defp business_type_label(4), do: "授权"
  defp business_type_label(5), do: "导出"
  defp business_type_label(6), do: "导入"
  defp business_type_label(7), do: "强退"
  defp business_type_label(8), do: "清空"
  defp business_type_label(type), do: to_string(type || "")

  defp operator_type_label(1), do: "其他"
  defp operator_type_label(2), do: "Web用户"
  defp operator_type_label(3), do: "手机端用户"
  defp operator_type_label(type), do: to_string(type || "")

  defp render_error(conn, :invalid_ids) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "日志编号无效"))
  end

  defp render_error(conn, :not_found) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(:validation_failed, "找不到请求的日志"))
  end

  defp render_error(conn, :invalid_log) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "日志参数无效"))
  end

  defp render_error(conn, :permission_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:permission_denied, "没有操作权限"))
  end

  defp render_error(conn, :data_scope_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:data_scope_denied, "没有数据权限"))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "参数校验失败", errors))
  end
end
