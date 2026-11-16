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

  def assigns("users", params),
    do: [
      user_query: keyword(params, "users_username"),
      user_display_name_query: keyword(params, "users_displayName")
    ]

  def assigns("jobs", params),
    do: [
      job_filter: %{"keyword" => keyword(params, "jobs_keyword")},
      selected_job_id: blank_to_nil(params["jobs_selectedJobId"])
    ]

  def assigns(_panel, _params), do: []

  @doc "将审计日志 URL 中的页码恢复到 LiveView 分页状态。"
  def apply_page(socket, "login-logs", params),
    do: assign_page(socket, "login-logs", params["login_logs_page"])

  def apply_page(socket, "operation-logs", params),
    do: assign_page(socket, "operation-logs", params["operations_audit_page"])

  def apply_page(socket, "users", params),
    do: assign_page(socket, "users", params["users_page"])

  def apply_page(socket, "jobs", params) do
    socket
    |> assign_page("jobs", params["jobs_jobPage"])
    |> assign_page("job-logs", params["jobs_logPage"])
  end

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

  def path("users", filter, page),
    do: query_path("/users", "users", filter, ["username", "displayName"], page)

  def path("jobs", filter, job_page, log_page, selected_job_id),
    do: jobs_path(filter, job_page, log_page, selected_job_id)

  defp audit_filter(params, namespace, fields) do
    Map.new(fields, fn field -> {field, keyword(params, "#{namespace}_#{field}")} end)
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

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

  defp query_path(path, namespace, filter, fields, page) do
    query =
      fields
      |> Enum.reduce(%{}, fn field, query ->
        value = String.trim(to_string(filter[field] || ""))
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

  defp jobs_path(filter, job_page, log_page, selected_job_id) do
    query =
      %{}
      |> put_query("jobs_keyword", filter["keyword"])
      |> put_page("jobs_jobPage", job_page)
      |> put_page("jobs_logPage", log_page)
      |> put_query("jobs_selectedJobId", selected_job_id)

    case URI.encode_query(query) do
      "" -> "/jobs"
      encoded -> "/jobs?" <> encoded
    end
  end

  defp put_query(query, _key, value) when value in [nil, ""], do: query
  defp put_query(query, key, value), do: Map.put(query, key, String.trim(to_string(value)))

  defp put_page(query, _key, page) when page in [nil, 1], do: query
  defp put_page(query, key, page), do: Map.put(query, key, page)
end
