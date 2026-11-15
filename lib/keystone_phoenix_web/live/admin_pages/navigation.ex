defmodule KeystonePhoenixWeb.Live.AdminPages.Navigation do
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
  def normalize_panel(panel), do: panel
end
