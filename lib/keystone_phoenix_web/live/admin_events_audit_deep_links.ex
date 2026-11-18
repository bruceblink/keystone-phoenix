defmodule KeystonePhoenixWeb.Live.AdminEvents.AuditDeepLinks do
  @moduledoc "登录后恢复审计列表的筛选、服务端页码和失败反馈。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminEvents.Audit, as: AuditEvents
  alias KeystonePhoenixWeb.Live.AdminPages.FilterNavigation
  alias KeystonePhoenixWeb.Live.AdminPages.Pagination
  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  @doc "按 URL 筛选和页码读取登录日志。"
  def restore_login_logs_from_deep_link(socket) do
    filter = socket.assigns.login_log_filter
    restore_page(socket, "login-logs", filter, &AuditEvents.login_query/1)
  end

  @doc "按 URL 筛选和页码读取操作审计。"
  def restore_operation_logs_from_deep_link(socket) do
    filter = socket.assigns.operation_log_filter
    restore_page(socket, "operation-logs", filter, &operation_query/1)
  end

  defp restore_page(socket, panel, filter, query_builder) do
    page = get_in(socket.assigns, [:page_nums, panel]) || 1
    size = get_in(socket.assigns, [:page_sizes, panel]) || 20

    case load_page(socket, panel, query_builder.(filter), page, size) do
      {:ok, result} ->
        valid_page = min(page, Pagination.page_count(result.total, size))

        if valid_page == page do
          save_page(socket, panel, filter, page, result, false)
        else
          case load_page(socket, panel, query_builder.(filter), valid_page, size) do
            {:ok, page_result} -> save_page(socket, panel, filter, valid_page, page_result, true)
            {:error, reason} -> failed_page(socket, panel, reason)
          end
        end

      {:error, reason} ->
        failed_page(socket, panel, reason)
    end
  end

  defp load_page(socket, "login-logs", filter, page, size) do
    params = Map.merge(filter, %{"pageNum" => page, "pageSize" => size})
    AdminReadSupport.login_logs_page(socket, params)
  end

  defp load_page(socket, "operation-logs", filter, page, size) do
    params = Map.merge(filter, %{"pageNum" => page, "pageSize" => size})
    AdminReadSupport.operation_logs_page(socket, params)
  end

  defp save_page(socket, panel, filter, page, result, page_corrected?) do
    {rows_key, total_key} = audit_keys(panel)

    socket =
      assign(socket, [
        {rows_key, result.rows},
        {total_key, result.total},
        page_nums: Map.put(socket.assigns.page_nums, panel, page),
        log_feedback: nil
      ])

    if page_corrected? do
      {:noreply,
       Phoenix.LiveView.push_patch(socket, to: FilterNavigation.path(panel, filter, page))}
    else
      {:noreply, socket}
    end
  end

  defp failed_page(socket, panel, reason) do
    {rows_key, total_key} = audit_keys(panel)
    message = if panel == "login-logs", do: "登录日志读取失败，请重试", else: "操作审计读取失败，请重试"

    {:noreply,
     assign(
       socket,
       [
         {rows_key, []},
         {total_key, 0},
         log_feedback: Support.read_error_feedback(reason, message)
       ]
     )}
  end

  defp operation_query(%{"actor" => actor, "action" => action, "resource" => resource}) do
    %{"actor" => actor, "action" => action, "resource" => resource}
  end

  defp audit_keys("login-logs"), do: {:login_log_rows, :login_log_total}
  defp audit_keys("operation-logs"), do: {:operation_log_rows, :operation_log_total}
end
