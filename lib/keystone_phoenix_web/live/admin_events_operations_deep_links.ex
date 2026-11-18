defmodule KeystonePhoenixWeb.Live.AdminEvents.OperationsDeepLinks do
  @moduledoc "恢复定时任务页面 URL 中的筛选、分页和选中任务。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminEvents.Operations, as: OperationsEvents
  alias KeystonePhoenixWeb.Live.AdminReadSupport, as: ReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  @doc "登录后按 URL 条件读取任务列表，再恢复所选任务日志。"
  def restore_jobs_from_deep_link(socket) do
    page = get_in(socket.assigns, [:page_nums, "jobs"]) || 1
    filter = Map.get(socket.assigns, :job_filter, %{"keyword" => ""})

    params =
      Map.merge(filter, %{
        "pageNum" => page,
        "pageSize" => get_in(socket.assigns, [:page_sizes, "jobs"]) || 20
      })

    if Support.panel_allowed?(socket, "jobs") do
      case ReadSupport.jobs_page(socket, params) do
        {:ok, result} ->
          socket =
            assign(socket,
              job_rows: result.rows,
              job_total: result.total,
              selected_job_ids: [],
              job_feedback: nil
            )

          OperationsEvents.restore_selected_job_if_needed(socket, "jobs")

        {:error, reason} ->
          {:noreply,
           assign(socket,
             job_rows: [],
             job_total: 0,
             selected_job_ids: [],
             job_feedback: Support.read_error_feedback(reason, "任务列表读取失败，请重试")
           )}
      end
    else
      {:noreply, socket}
    end
  end
end
