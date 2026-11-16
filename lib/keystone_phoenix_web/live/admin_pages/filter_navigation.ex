defmodule KeystonePhoenixWeb.Live.AdminPages.FilterNavigation do
  @moduledoc "管理页面筛选条件的深链接参数转换。"

  import Phoenix.Component, only: [assign: 2]

  @doc "读取与 admin-web 相同的页面关键词参数。"
  def keyword(params, key), do: String.trim(params[key] || params["keyword"] || "")

  @doc "返回当前页面需要写入的筛选 assign。"
  def assigns("menus", params), do: [menu_filter: keyword(params, "menus_keyword")]

  def assigns("depts", params),
    do: [dept_filter: %{"keyword" => keyword(params, "departments_keyword"), "status" => "all"}]

  def assigns("login-logs", params),
    do: [login_log_filter: audit_filter(params, "login_logs", ["username", "status"])]

  def assigns("operation-logs", params),
    do: [
      operation_log_filter:
        audit_filter(params, "operations_audit", ["actor", "action", "resource"])
    ]

  def assigns(_panel, _params), do: []

  @doc "将审计日志 URL 中的页码恢复到 LiveView 分页状态。"
  def apply_page(socket, "login-logs", params),
    do: assign_page(socket, "login-logs", params["login_logs_page"])

  def apply_page(socket, "operation-logs", params),
    do: assign_page(socket, "operation-logs", params["operations_audit_page"])

  def apply_page(socket, _panel, _params), do: socket

  @doc "生成与 admin-web 页面命名空间一致的筛选深链接。"
  def path("menus", ""), do: "/menus"
  def path("depts", ""), do: "/departments"
  def path("menus", keyword), do: "/menus?menus_keyword=#{URI.encode(keyword)}"
  def path("depts", keyword), do: "/departments?departments_keyword=#{URI.encode(keyword)}"

  @doc "生成登录日志页面的筛选和分页深链接。"
  def path("login-logs", filter, page),
    do: audit_path("/audit/login", "login_logs", filter, ["username", "status"], page)

  def path("operation-logs", filter, page),
    do:
      audit_path(
        "/audit/operations",
        "operations_audit",
        filter,
        ["actor", "action", "resource"],
        page
      )

  defp audit_filter(params, namespace, fields) do
    Map.new(fields, fn field -> {field, keyword(params, "#{namespace}_#{field}")} end)
  end

  defp assign_page(socket, panel, value) do
    page = positive_page(value)
    page_nums = Map.put(socket.assigns.page_nums, panel, page)
    assign(socket, page_nums: page_nums)
  end

  defp positive_page(value) do
    case Integer.parse(to_string(value || "")) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp audit_path(path, namespace, filter, fields, page) do
    query =
      fields
      |> Enum.reduce(%{}, fn field, query ->
        value = String.trim(to_string(filter[field] || filter["#{field}"] || ""))
        if value == "", do: query, else: Map.put(query, "#{namespace}_#{field}", value)
      end)
      |> then(fn query ->
        if page > 1, do: Map.put(query, "#{namespace}_page", page), else: query
      end)

    case URI.encode_query(query) do
      "" -> path
      encoded -> "#{path}?#{encoded}"
    end
  end
end
