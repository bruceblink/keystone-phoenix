defmodule KeystonePhoenixWeb.Live.AdminEvents.Operations do
  @moduledoc "LiveView event handlers for the operations domain."

  import Phoenix.Component, only: [assign: 2]
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Monitor
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event("refresh-jobs", _params, socket) do
    if Support.panel_allowed?(socket, "jobs") do
      {:noreply,
       assign(socket,
         job_rows: Support.load_jobs_for_socket(socket),
         selected_job_ids: [],
         page_nums: Map.put(socket.assigns.page_nums, "jobs", 1),
         job_form: Support.empty_job_form(),
         job_feedback: nil,
         active_modal: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("filter-jobs", params, socket) do
    if Support.panel_allowed?(socket, "jobs") do
      {:noreply,
       assign(socket,
         job_filter: %{"keyword" => String.trim(to_string(params["jobKeyword"] || ""))},
         selected_job_ids: [],
         page_nums: Map.put(socket.assigns.page_nums, "jobs", 1)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset-job-filter", _params, socket) do
    if Support.panel_allowed?(socket, "jobs") do
      {:noreply,
       assign(socket,
         job_filter: %{"keyword" => ""},
         selected_job_ids: [],
         page_nums: Map.put(socket.assigns.page_nums, "jobs", 1)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-job-selection", %{"job-id" => job_id, "selected" => selected}, socket) do
    selected_ids = Map.get(socket.assigns, :selected_job_ids, [])

    selected_ids =
      if selected == "true",
        do: Enum.uniq([job_id | selected_ids]),
        else: List.delete(selected_ids, job_id)

    {:noreply, assign(socket, selected_job_ids: selected_ids)}
  end

  def handle_event("toggle-all-job-selection", %{"selected" => selected}, socket) do
    page_ids =
      socket.assigns.job_rows
      |> filtered_job_rows(socket.assigns[:job_filter] || %{})
      |> page_rows(socket.assigns.page_nums["jobs"], socket.assigns.page_sizes["jobs"])
      |> Enum.map(&to_string(&1["jobId"]))

    selected_ids = Map.get(socket.assigns, :selected_job_ids, [])

    selected_ids =
      if selected == "true",
        do: Enum.uniq(selected_ids ++ page_ids),
        else: selected_ids -- page_ids

    {:noreply, assign(socket, selected_job_ids: selected_ids)}
  end

  def handle_event("select-job", %{"job-id" => job_id}, socket) do
    if Support.panel_allowed?(socket, "jobs") do
      {:noreply,
       assign(socket,
         selected_job_id: job_id,
         job_log_rows: Support.load_job_logs_for_socket(socket),
         page_nums: Map.put(socket.assigns.page_nums, "job-logs", 1),
         job_log_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-jobs", %{"job-ids" => job_ids}, socket) do
    if Support.permission_socket?(socket, "job:delete") do
      ids = String.split(job_ids, ",", trim: true)

      case Job.delete_jobs(ids, authorization(socket, "job:delete")) do
        :ok ->
          {:noreply,
           assign(socket,
             job_rows: Support.load_jobs_for_socket(socket),
             selected_job_ids: [],
             job_form: Support.empty_job_form(),
             active_modal: nil,
             job_feedback: "已删除 #{length(ids)} 个任务"
           )}

        error ->
          {:noreply, assign(socket, job_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-job", _params, socket) do
    if Support.permission_socket?(socket, "job:create") do
      {:noreply,
       assign(socket, job_form: Support.empty_job_form(), job_feedback: nil, active_modal: "job")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit-job", %{"job-id" => job_id}, socket) do
    if Support.permission_socket?(socket, "job:update") do
      case Enum.find(socket.assigns.job_rows, &(to_string(&1["jobId"]) == job_id)) do
        nil ->
          {:noreply, assign(socket, job_feedback: Feedback.error("找不到指定任务"))}

        job ->
          {:noreply,
           assign(socket,
             job_form: Map.merge(Support.empty_job_form(), job),
             job_feedback: nil,
             active_modal: "job"
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-job", params, socket) do
    if Support.permission_socket?(socket, "job:create") or
         Support.permission_socket?(socket, "job:update") do
      job_id = String.trim(params["jobId"] || "")

      result =
        if job_id == "",
          do: Job.create_job(params, authorization(socket, "job:create")),
          else: Job.update_job(job_id, params, authorization(socket, "job:update"))

      case result do
        {:ok, _job} ->
          {:noreply,
           assign(socket,
             job_rows: Support.load_jobs_for_socket(socket),
             selected_job_ids: [],
             job_form: Support.empty_job_form(),
             active_modal: nil,
             job_feedback: if(job_id == "", do: "任务已创建", else: "任务已更新")
           )}

        error ->
          {:noreply, assign(socket, job_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-job", %{"job-id" => job_id}, socket) do
    if Support.permission_socket?(socket, "job:delete") do
      case Job.delete_jobs([job_id], authorization(socket, "job:delete")) do
        :ok ->
          {:noreply,
           assign(socket,
             job_rows: Support.load_jobs_for_socket(socket),
             selected_job_ids: [],
             job_form: Support.empty_job_form(),
             active_modal: nil,
             job_feedback: "任务已删除"
           )}

        error ->
          {:noreply, assign(socket, job_feedback: Support.form_error(error))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("run-job", %{"job-id" => job_id}, socket) do
    if Support.permission_socket?(socket, "job:run") do
      case Job.get_job(job_id, Support.authorization_options(socket, "job:read")) do
        {:ok, _job} ->
          live_view = self()

          case Task.Supervisor.start_child(KeystonePhoenix.JobTaskSupervisor, fn ->
                 result = Job.run_job(job_id, authorization(socket, "job:run"))
                 send(live_view, {:admin_job_finished, job_id, result})
               end) do
            {:ok, _pid} ->
              {:noreply, assign(socket, job_feedback: "任务已提交，执行结果将自动刷新")}

            {:error, reason} ->
              {:noreply,
               assign(socket, job_feedback: Feedback.error("任务无法启动：#{inspect(reason)}"))}
          end

        {:error, :not_found} ->
          {:noreply, assign(socket, job_feedback: Feedback.error("找不到指定任务"))}

        {:error, :data_scope_denied} ->
          {:noreply, assign(socket, job_feedback: Feedback.error("找不到指定任务"))}

        {:error, :permission_denied} ->
          {:noreply, assign(socket, job_feedback: Feedback.error("找不到指定任务"))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel-job", %{"job-id" => job_id}, socket) do
    if Support.permission_socket?(socket, "job:run") do
      feedback =
        case Job.cancel_job(job_id, authorization(socket, "job:run")) do
          :ok -> "任务已取消"
          {:error, :invalid_id} -> Feedback.error("任务编号无效")
          :not_found -> Feedback.error("没有正在运行的任务")
        end

      {:noreply,
       assign(socket, job_rows: Support.load_jobs_for_socket(socket), job_feedback: feedback)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-job-status", %{"job-id" => job_id, "status" => status}, socket) do
    if Support.permission_socket?(socket, "job:update-status") do
      feedback =
        case Job.update_job_status(
               job_id,
               status,
               authorization(socket, "job:update-status")
             ) do
          {:ok, _job} -> "任务状态已更新"
          {:error, reason} -> Feedback.error("任务状态更新失败：#{inspect(reason)}")
        end

      {:noreply,
       assign(socket, job_rows: Support.load_jobs_for_socket(socket), job_feedback: feedback)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-job-logs", _params, socket) do
    if Support.panel_allowed?(socket, "job-logs") do
      {:noreply,
       assign(socket,
         job_log_rows: Support.load_job_logs_for_socket(socket),
         page_nums: Map.put(socket.assigns.page_nums, "job-logs", 1),
         job_log_feedback: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-monitor", _params, socket) do
    if Support.monitor_access?(socket) do
      socket = assign(socket, page_nums: Map.put(socket.assigns.page_nums, "online-users", 1))
      {:noreply, Support.assign_monitor(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-monitor-help", _params, socket) do
    {:noreply,
     assign(socket, monitor_help_open: !Map.get(socket.assigns, :monitor_help_open, false))}
  end

  def handle_event("logout-online-user", %{"token-id" => token_id}, socket) do
    if Support.permission_socket?(socket, "online-session:revoke") do
      feedback =
        case Monitor.logout_online_user(
               token_id,
               authorization(socket, "online-session:revoke")
             ) do
          :ok -> "在线会话已强制下线"
          {:error, :not_found} -> Feedback.error("在线会话不存在或已经失效")
          {:error, :unavailable} -> Feedback.error("会话服务暂不可用")
        end

      socket = assign(socket, page_nums: Map.put(socket.assigns.page_nums, "online-users", 1))
      {:noreply, Support.assign_monitor(socket, feedback)}
    else
      {:noreply, socket}
    end
  end

  defp authorization(socket, permission) do
    principal =
      (socket.assigns[:current_user] || %{})
      |> Map.put(:permissions, List.wrap(socket.assigns[:permissions]))

    [authorization: %{principal: principal, permission: permission}]
  end

  defp filtered_job_rows(rows, filter) do
    keyword = String.trim(to_string(filter["keyword"] || "")) |> String.downcase()

    Enum.filter(rows, fn job ->
      keyword == "" or
        String.contains?(
          String.downcase(
            "#{job["jobName"] || ""} #{job["jobGroup"] || ""} #{job["invokeTarget"] || ""}" <>
              " #{job["jobCode"] || ""}"
          ),
          keyword
        )
    end)
  end

  defp page_rows(rows, page_num, page_size) do
    rows
    |> Enum.drop(max(page_num - 1, 0) * page_size)
    |> Enum.take(page_size)
  end
end
