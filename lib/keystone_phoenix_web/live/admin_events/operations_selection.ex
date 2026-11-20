defmodule KeystonePhoenixWeb.Live.AdminEvents.OperationsSelection do
  @moduledoc "处理任务删除后的当前详情状态。"

  import Phoenix.Component, only: [assign: 2]

  # 删除当前查看的任务时，清除详情、日志和深链接；删除其他任务时保留当前详情。
  def clear_deleted_job_detail(socket, deleted_ids) do
    selected_job_id = socket.assigns[:selected_job_id]

    if selected_job_id &&
         Enum.any?(deleted_ids, &(to_string(&1) == to_string(selected_job_id))) do
      assign(socket,
        selected_job_id: nil,
        selected_job: nil,
        job_log_rows: [],
        job_log_total: 0,
        job_log_loaded_page: nil,
        job_log_feedback: nil,
        page_nums: Map.put(socket.assigns.page_nums, "job-logs", 1)
      )
    else
      socket
    end
  end
end
