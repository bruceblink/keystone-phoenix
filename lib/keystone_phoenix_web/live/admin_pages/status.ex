defmodule KeystonePhoenixWeb.Live.AdminPages.Status do
  @moduledoc """
  统一管理后台状态徽标的视觉映射。

  状态文字仍由各页面数据提供，本模块只负责将稳定的状态值映射为 CSS 类。
  """

  # 普通管理记录使用正常和停用两种视觉状态。
  def normal_paused(1), do: "status-badge--normal"
  def normal_paused(_status), do: "status-badge--paused"

  # 登录和操作日志使用成功和失败两种视觉状态。
  def success_failure(1), do: "status-badge--success"
  def success_failure(_status), do: "status-badge--failure"

  # 定时任务日志保留跳过和未知状态的独立语义。
  def job_log(0), do: "status-badge--failure"
  def job_log(1), do: "status-badge--success"
  def job_log(2), do: "status-badge--skipped"
  def job_log(_status), do: "status-badge--unknown"

  # 网络状态只允许在线、离线和未知三种视觉语义。
  def network("ONLINE"), do: "status-badge--success"
  def network("OFFLINE"), do: "status-badge--failure"
  def network(_status), do: "status-badge--unknown"
end
