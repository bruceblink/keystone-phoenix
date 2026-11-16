defmodule KeystonePhoenixWeb.Live.AdminEvents.Audit do
  @moduledoc "LiveView event handlers for audit filters and Excel exports."

  import Phoenix.LiveView, only: [push_event: 3]
  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Log
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  @login_headers ["ID", "用户名", "IP 地址", "登录地点", "操作系统", "浏览器", "状态", "说明", "登录时间"]
  @operation_headers [
    "ID",
    "业务类型",
    "请求方法",
    "请求模块",
    "请求地址",
    "调用方法",
    "操作人类型",
    "用户 ID",
    "用户名",
    "IP 地址",
    "IP 地点",
    "部门 ID",
    "部门",
    "操作参数",
    "操作结果",
    "状态",
    "错误堆栈",
    "操作时间"
  ]

  def handle_event("filter-login-logs", params, socket) do
    if Support.panel_allowed?(socket, "login-logs") do
      filter = %{
        "username" => String.trim(to_string(params["loginUsername"] || "")),
        "status" => String.trim(to_string(params["loginStatus"] || ""))
      }

      case Support.load_logs_for_socket_result(socket, %{
             "login" => Map.put(login_query(filter), "pageNum", 1)
           }) do
        {:ok, logs} ->
          {:noreply,
           assign(socket,
             login_log_filter: filter,
             login_log_rows: logs.login_log_rows,
             login_log_total: logs.login_log_total,
             page_nums: Map.put(socket.assigns.page_nums, "login-logs", 1),
             log_feedback: nil
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             login_log_filter: filter,
             log_feedback: Support.read_error_feedback(reason, "登录日志查询失败，请重试")
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset-login-log-filter", _params, socket),
    do: handle_event("filter-login-logs", %{}, socket)

  def handle_event("paginate-login-logs", %{"page" => page}, socket),
    do: paginate_logs(socket, "login", page)

  def handle_event("filter-operation-logs", params, socket) do
    if Support.panel_allowed?(socket, "operation-logs") do
      filter = %{
        "actor" => String.trim(to_string(params["operationActor"] || "")),
        "action" => String.trim(to_string(params["operationAction"] || "")),
        "resource" => String.trim(to_string(params["operationResource"] || ""))
      }

      case Support.load_logs_for_socket_result(socket, %{
             "operation" => Map.put(operation_query(filter), "pageNum", 1)
           }) do
        {:ok, logs} ->
          {:noreply,
           assign(socket,
             operation_log_filter: filter,
             operation_log_rows: logs.operation_log_rows,
             operation_log_total: logs.operation_log_total,
             page_nums: Map.put(socket.assigns.page_nums, "operation-logs", 1),
             log_feedback: nil
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             operation_log_filter: filter,
             log_feedback: Support.read_error_feedback(reason, "操作审计查询失败，请重试")
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset-operation-log-filter", _params, socket),
    do: handle_event("filter-operation-logs", %{}, socket)

  def handle_event("paginate-operation-logs", %{"page" => page}, socket),
    do: paginate_logs(socket, "operation", page)

  def handle_event("filter-dict-types", params, socket) do
    if Support.panel_allowed?(socket, "dicts") do
      keyword = String.trim(to_string(params["dictTypeKeyword"] || ""))
      dictionary = Support.load_dictionary_for_socket(socket, "", %{})
      filtered_types = filter_dict_types(dictionary.types, keyword)

      selected_type =
        if Enum.any?(filtered_types, &(&1["dictType"] == socket.assigns.selected_dict_type)) do
          socket.assigns.selected_dict_type
        else
          List.first(filtered_types, %{})["dictType"] || ""
        end

      dict_data_rows =
        if selected_type == "",
          do: [],
          else: Support.load_dict_data_for_socket(socket, selected_type)

      {:noreply,
       assign(socket,
         dict_type_filter: %{"keyword" => keyword},
         dict_type_rows: filtered_types,
         dict_data_rows: dict_data_rows,
         selected_dict_type: selected_type,
         page_nums: Map.put(socket.assigns.page_nums, "dict-data", 1),
         dict_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset-dict-type-filter", _params, socket),
    do: handle_event("filter-dict-types", %{}, socket)

  def handle_event("export-login-logs", _params, socket), do: export_logs(socket, :login)
  def handle_event("export-operation-logs", _params, socket), do: export_logs(socket, :operation)

  # 过滤字典类型时同时匹配名称和编码，并在无匹配结果时清空当前条目选择。
  defp filter_dict_types(rows, keyword) do
    normalized = String.downcase(keyword)

    Enum.filter(rows, fn row ->
      normalized == "" or
        String.contains?(
          String.downcase("#{row["dictName"] || ""} #{row["dictType"] || ""}"),
          normalized
        )
    end)
  end

  defp export_logs(socket, kind) do
    # 导出依赖失败时保留原文，并标记为可重试的服务错误。
    permission = if kind == :login, do: "login-log:export", else: "operation-log:export"

    if Support.permission_socket?(socket, permission) do
      filters =
        if kind == :login,
          do: login_query(socket.assigns.login_log_filter),
          else: operation_query(socket.assigns.operation_log_filter)

      authorization = Support.authorization_options(socket)

      fetcher =
        if kind == :login,
          do: &Log.list_login_logs_for_export/2,
          else: &Log.list_operation_logs_for_export/2

      case Excel.all_rows_result(fn page -> fetcher.(page, authorization) end, filters) do
        {:ok, rows} ->
          {filename, headers, export_rows} = export_payload(kind, rows)

          case Excel.export(headers, export_rows, filename) do
            {:ok, binary} ->
              {:noreply,
               push_event(socket, "download-xlsx", %{
                 filename: filename,
                 content: Base.encode64(binary),
                 content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
               })}

            {:error, reason} ->
              {:noreply,
               assign(
                 socket,
                 log_feedback:
                   Feedback.error(:service_unavailable, "Excel 导出失败：#{inspect(reason)}")
               )}
          end

        {:error, reason} ->
          {:noreply,
           assign(
             socket,
             log_feedback: Feedback.error(:service_unavailable, "Excel 导出失败：#{inspect(reason)}")
           )}
      end
    else
      {:noreply, socket}
    end
  end

  defp export_payload(:login, rows),
    do: {"login-logs.xlsx", @login_headers, Enum.map(rows, &login_row/1)}

  defp export_payload(:operation, rows),
    do: {"operation-logs.xlsx", @operation_headers, Enum.map(rows, &operation_row/1)}

  defp login_row(row),
    do: [
      row["infoId"],
      row["username"],
      row["ipAddress"],
      row["loginLocation"],
      row["operationSystem"],
      row["browser"],
      row["statusStr"],
      row["msg"],
      row["loginTime"]
    ]

  defp operation_row(row),
    do: [
      row["operationId"],
      row["businessTypeStr"],
      row["requestMethod"],
      row["requestModule"],
      row["requestUrl"],
      row["calledMethod"],
      row["operatorTypeStr"],
      row["userId"],
      row["username"],
      row["operatorIp"],
      row["operatorLocation"],
      row["deptId"],
      row["deptName"],
      row["operationParam"],
      row["operationResult"],
      row["statusStr"],
      row["errorStack"],
      row["operationTime"]
    ]

  defp login_query(%{"username" => username, "status" => status}) do
    %{"username" => username, "status" => normalize_login_status(status)}
  end

  defp operation_query(%{"actor" => actor, "action" => action, "resource" => resource}),
    do: %{"username" => actor, "action" => action, "requestModule" => resource}

  defp paginate_logs(socket, kind, page) do
    panel = if kind == "login", do: "login-logs", else: "operation-logs"

    case Integer.parse(to_string(page)) do
      {page_number, ""} when page_number > 0 ->
        query =
          if kind == "login",
            do: login_query(socket.assigns.login_log_filter),
            else: operation_query(socket.assigns.operation_log_filter)

        filters = %{kind => Map.put(query, "pageNum", page_number)}

        case Support.load_logs_for_socket_result(socket, filters) do
          {:ok, logs} ->
            rows = if kind == "login", do: logs.login_log_rows, else: logs.operation_log_rows
            total = if kind == "login", do: logs.login_log_total, else: logs.operation_log_total
            row_key = if kind == "login", do: :login_log_rows, else: :operation_log_rows
            total_key = if kind == "login", do: :login_log_total, else: :operation_log_total

            {:noreply,
             assign(
               socket,
               [
                 {row_key, rows},
                 {total_key, total},
                 page_nums: Map.put(socket.assigns.page_nums, panel, page_number),
                 log_feedback: nil
               ]
             )}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               log_feedback: Support.read_error_feedback(reason, "日志分页读取失败，请重试")
             )}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp normalize_login_status("SUCCESS"), do: 1
  defp normalize_login_status("FAILURE"), do: 0
  defp normalize_login_status("LOGOUT"), do: 2
  defp normalize_login_status("REGISTER"), do: 3
  defp normalize_login_status(value), do: value
end
