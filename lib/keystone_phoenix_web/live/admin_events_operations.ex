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
         page_nums: Map.put(socket.assigns.page_nums, "jobs", 1),
         job_form: Support.empty_job_form(),
         job_feedback: nil,
         active_modal: nil
       )}
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
end
