defmodule KeystonePhoenixWeb.Live.AdminEvents.AsyncJobs do
  @moduledoc "处理管理页面异步任务完成后的 LiveView 更新。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminSupport

  # 完成消息刷新当前主体可见的任务和日志，并保留成功或失败结果。
  def handle_info(_job_id, result, socket) do
    feedback =
      case result do
        :ok ->
          "任务已执行并写入运行日志"

        {:skipped, :already_running} ->
          "任务正在执行，本次触发已跳过"

        {:error, :not_found} ->
          Feedback.error(:resource_not_found, "找不到指定任务")

        {:error, reason} ->
          Feedback.error(
            Feedback.code(Feedback.from_reason(reason)),
            "任务执行失败：#{inspect(reason)}"
          )

        _ ->
          Feedback.error(:internal_error, "任务状态未知，请检查运行日志")
      end

    reload =
      if AdminSupport.admin_socket?(socket) do
        [job_rows: AdminSupport.load_jobs(), job_log_rows: AdminSupport.load_job_logs()]
      else
        [
          job_rows: AdminSupport.load_jobs_for_socket(socket),
          job_log_rows: AdminSupport.load_job_logs_for_socket(socket)
        ]
      end

    {:noreply, assign(socket, Keyword.put(reload, :job_feedback, feedback))}
  end
end
