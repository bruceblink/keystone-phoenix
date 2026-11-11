defmodule KeystonePhoenixWeb.Live.AdminPages.Navigation do
  @moduledoc """
  管理后台导航的页面标题映射。

  页面标识由 LiveView 路由使用，标题由本模块统一维护。
  """

  # 将内部面板标识转换为面向管理员的正式页面标题。
  def panel_title("overview"), do: "平台概览"
  def panel_title("depts"), do: "部门管理"
  def panel_title("posts"), do: "岗位管理"
  def panel_title("roles"), do: "角色管理"
  def panel_title("menus"), do: "菜单管理"
  def panel_title("users"), do: "用户管理"
  def panel_title("configs"), do: "配置管理"
  def panel_title("dicts"), do: "字典管理"
  def panel_title("notices"), do: "公告管理"
  def panel_title("logs"), do: "日志审计"
  def panel_title("jobs"), do: "定时任务"
  def panel_title("job-logs"), do: "任务日志"
  def panel_title("monitor"), do: "运行监控"
  def panel_title("profile"), do: "个人资料"
  def panel_title(_panel), do: "管理模块"
end
