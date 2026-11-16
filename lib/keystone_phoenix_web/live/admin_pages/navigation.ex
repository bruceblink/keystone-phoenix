defmodule KeystonePhoenixWeb.Live.AdminPages.Navigation do
  use Phoenix.Component

  @moduledoc """
  管理后台导航的页面标题映射。

  页面标识由 LiveView 路由使用，标题由本模块统一维护。
  """

  # 将内部面板标识转换为面向管理员的正式页面标题。
  def panel_title("overview"), do: "运行监控"
  def panel_title("dashboard"), do: "运行监控"
  def panel_title("depts"), do: "组织结构"
  def panel_title("posts"), do: "岗位管理"
  def panel_title("roles"), do: "角色管理"
  def panel_title("menus"), do: "菜单与权限"
  def panel_title("users"), do: "用户管理"
  def panel_title("api-keys"), do: "API Key 管理"
  def panel_title("configs"), do: "配置管理"
  def panel_title("dicts"), do: "字典管理"
  def panel_title("notices"), do: "公告管理"
  def panel_title("logs"), do: "日志审计"
  def panel_title("login-logs"), do: "登录日志"
  def panel_title("operation-logs"), do: "操作审计"
  def panel_title("jobs"), do: "定时任务"
  def panel_title("job-logs"), do: "任务日志"
  def panel_title("monitor"), do: "运行监控"
  def panel_title("profile"), do: "个人资料"
  def panel_title(_panel), do: "管理模块"

  # admin-web 的路由名称映射到 LiveView 内部面板，dashboard 与 monitor 共用同一页面。
  def panel_for_path(uri) do
    case URI.parse(uri).path do
      "/departments" -> "depts"
      "/dictionaries" -> "dicts"
      "/audit/login" -> "login-logs"
      "/audit/operations" -> "operation-logs"
      "/dashboard" -> "monitor"
      "/monitor" -> "monitor"
      "/users" -> "users"
      "/roles" -> "roles"
      "/posts" -> "posts"
      "/menus" -> "menus"
      "/api-keys" -> "api-keys"
      "/jobs" -> "jobs"
      "/configs" -> "configs"
      "/notices" -> "notices"
      "/profile" -> "profile"
      _ -> "monitor"
    end
  end

  def normalize_panel("dashboard"), do: "monitor"
  def normalize_panel("overview"), do: "monitor"
  def normalize_panel("logs"), do: "operation-logs"
  def normalize_panel("job-logs"), do: "jobs"
  def normalize_panel(panel), do: panel

  @doc "渲染与 admin-web 对齐的 Lucide 风格侧栏图标。"
  attr :name, :string, required: true

  def nav_icon(assigns) do
    ~H"""
    <svg class="nav-icon-svg" xmlns="http://www.w3.org/2000/svg" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d={icon_path(@name)} />
    </svg>
    """
  end

  defp icon_path("activity"), do: "M3 12h4l3-9 4 18 3-9h4"

  defp icon_path("users"),
    do:
      "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"

  defp icon_path("user-cog"),
    do:
      "M15 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M8 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8M19 16l1.2.7-.2 1.4-1.4.2-.7 1.2-1.2-.7-1.2.7-.7-1.2-1.4-.2-.2-1.4 1.2-.7-.1-1.4 1.3-.5.9-1.1 1.3.5z"

  defp icon_path("building"),
    do: "M3 21h18M6 21V5l6-3 6 3v16M9 9h1M14 9h1M9 13h1M14 13h1M9 17h1M14 17h1"

  defp icon_path("briefcase"), do: "M3 7h18v13H3zM8 7V4h8v3M3 12h18M10 12v2h4v-2"
  defp icon_path("hard-drive"), do: "M3 6h18v12H3zM7 10h.01M11 10h.01M15 10h2M7 14h10"
  defp icon_path("list-tree"), do: "M4 6h4M4 12h4M4 18h4M12 6h8M12 12h8M12 18h8M8 6v12"
  defp icon_path("key"), do: "M21 2l-2 2m-2-2 2 2-5.5 5.5a5 5 0 1 1-3-3zM7 17h.01M10 14h.01"

  defp icon_path("file-text"),
    do: "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zM14 2v6h6M8 13h8M8 17h6"

  defp icon_path("shield"), do: "M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10M9 12l2 2 4-4"

  defp icon_path("file-clock"),
    do:
      "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zM14 2v6h6M12 18a3 3 0 1 0 0-6 3 3 0 0 0 0 6M12 14v2l1 1"

  defp icon_path("list-checks"),
    do: "M9 6h12M9 12h12M9 18h12M3 6l1 1 2-2M3 12l1 1 2-2M3 18l1 1 2-2"

  defp icon_path("clipboard-list"),
    do:
      "M8 4H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2h-2M8 3h8v4H8zM9 12h.01M12 12h4M9 16h.01M12 16h4"

  defp icon_path("settings"),
    do:
      "M12 15.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-1.8 1.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6v.2h-2.5V20a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1-1.8-1.8.1-.1A1.7 1.7 0 0 0 8 15a1.7 1.7 0 0 0-1.6-1H6v-2.5h.2a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9l-.1-.1 1.8-1.8.1.1a1.7 1.7 0 0 0 1.9.3 1.7 1.7 0 0 0 1-1.6v-.2h2.5v.2a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1 1.8 1.8-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1h.2V14h-.2a1.7 1.7 0 0 0-1.6 1z"

  defp icon_path("book-open"),
    do: "M2 3h6a4 4 0 0 1 4 4v14a4 4 0 0 0-4-4H2zM22 3h-6a4 4 0 0 0-4 4v14a4 4 0 0 1 4-4h6z"

  defp icon_path("megaphone"),
    do: "M3 11v2a2 2 0 0 0 2 2h1l2 5h2l-1.5-5H12l8 4V5l-8 4H5a2 2 0 0 0-2 2z"

  defp icon_path(_name), do: icon_path("activity")
end
