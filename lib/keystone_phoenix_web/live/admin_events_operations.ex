defmodule KeystonePhoenixWeb.Live.AdminEvents.Operations do
  @moduledoc "LiveView event handlers for the operations domain."

  import Phoenix.Component, only: [assign: 2]
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Monitor
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminPages.FilterNavigation
  alias KeystonePhoenixWeb.Live.AdminReadSupport, as: ReadSupport
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def handle_event("refresh-jobs", _params, socket) do
    if Support.panel_allowed?(socket, "jobs") do
      case ReadSupport.jobs_page(socket, job_page_params(socket, 1, current_job_filter(socket))) do
        {:ok, page} ->
          {:noreply,
           assign(socket,
             job_rows: page.rows,
             job_total: page.total,
             selected_job_ids: [],
             selected_job_id: nil,
             selected_job: nil,
             job_log_loaded_page: nil,
             page_nums: Map.put(socket.assigns.page_nums, "jobs", 1),
             job_form: Support.empty_job_form(),
             job_feedback: nil,
             active_modal: nil
           )
           |> push_jobs_path(nil)}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             job_feedback: Support.read_error_feedback(reason, "任务列表刷新失败，请重试")
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("filter-jobs", params, socket) do
    if Support.panel_allowed?(socket, "jobs") do
      filter = %{"keyword" => String.trim(to_string(params["jobKeyword"] || ""))}

      socket =
        assign(socket,
          job_filter: filter,
          selected_job_ids: [],
          selected_job_id: nil,
          selected_job: nil,
          job_log_loaded_page: nil
        )

      {:noreply, refresh_job_page(socket, 1)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset-job-filter", _params, socket) do
    handle_event("filter-jobs", %{"jobKeyword" => ""}, socket)
  end

  def handle_event("paginate-jobs", %{"page" => page}, socket),
    do: paginate_jobs(socket, page)

  def handle_event("paginate-job-logs", %{"page" => page}, socket),
    do: paginate_job_logs(socket, page)

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
      Enum.map(socket.assigns.job_rows, &to_string(&1["jobId"]))

    selected_ids = Map.get(socket.assigns, :selected_job_ids, [])

    selected_ids =
      if selected == "true",
        do: Enum.uniq(selected_ids ++ page_ids),
        else: selected_ids -- page_ids

    {:noreply, assign(socket, selected_job_ids: selected_ids)}
  end

  def handle_event("select-job", %{"job-id" => job_id}, socket),
    do:
      select_job(
        socket,
        job_id,
        true,
        if(job_id == socket.assigns.selected_job_id and is_nil(socket.assigns.selected_job),
          do: get_in(socket.assigns, [:page_nums, "job-logs"]) || 1,
          else: 1
        )
      )

  def handle_event("delete-jobs", %{"job-ids" => job_ids}, socket) do
    if Support.permission_socket?(socket, "job:delete") do
      ids = String.split(job_ids, ",", trim: true)

      case Job.delete_jobs(ids, authorization(socket, "job:delete")) do
        :ok ->
          {:noreply,
           assign(socket,
             selected_job_ids: [],
             selected_job: nil,
             job_log_loaded_page: nil,
             job_form: Support.empty_job_form(),
             active_modal: nil,
             job_feedback: "已删除 #{length(ids)} 个任务"
           )
           |> refresh_job_page(1)}

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
      case Job.get_job(job_id, Support.authorization_options(socket, "job:read")) do
        {:ok, job} ->
          {:noreply,
           assign(socket,
             job_form: Map.merge(Support.empty_job_form(), Job.job_to_map(job)),
             selected_job: Job.job_to_map(job),
             job_feedback: nil,
             active_modal: "job"
           )}

        {:error, reason} ->
          feedback =
            if reason in [:permission_denied, :data_scope_denied],
              do: Feedback.error(:resource_not_found, "找不到指定任务"),
              else: Support.read_error_feedback(reason, "找不到指定任务")

          {:noreply, assign(socket, job_feedback: feedback)}
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
             selected_job_ids: [],
             selected_job: nil,
             job_form: Support.empty_job_form(),
             active_modal: nil,
             job_feedback: if(job_id == "", do: "任务已创建", else: "任务已更新")
           )
           |> refresh_job_page(1)}

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
             selected_job_ids: [],
             selected_job: nil,
             job_form: Support.empty_job_form(),
             active_modal: nil,
             job_feedback: "任务已删除"
           )
           |> refresh_job_page(1)}

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
        {:ok, %{status: 0}} ->
          {:noreply,
           assign(
             socket,
             job_feedback: Feedback.error(:resource_conflict, "任务已暂停，无法手动执行")
           )}

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
               assign(
                 socket,
                 job_feedback: Feedback.error(:service_unavailable, "任务无法启动：#{inspect(reason)}")
               )}
          end

        {:error, :not_found} ->
          {:noreply, assign(socket, job_feedback: Feedback.error(:resource_not_found, "找不到指定任务"))}

        {:error, :data_scope_denied} ->
          {:noreply, assign(socket, job_feedback: Feedback.error(:resource_not_found, "找不到指定任务"))}

        {:error, :permission_denied} ->
          {:noreply, assign(socket, job_feedback: Feedback.error(:resource_not_found, "找不到指定任务"))}
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
          {:error, :invalid_id} -> Feedback.error(:validation_failed, "任务编号无效")
          :not_found -> Feedback.error(:resource_conflict, "没有正在运行的任务")
        end

      {:noreply, refresh_job_page(assign(socket, job_feedback: feedback), 1)}
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
          {:ok, _job} ->
            "任务状态已更新"

          {:error, reason} ->
            Feedback.error(
              Feedback.code(Feedback.from_reason(reason)),
              "任务状态更新失败：#{inspect(reason)}"
            )
        end

      {:noreply, refresh_job_page(assign(socket, job_feedback: feedback), 1)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-job-logs", _params, socket) do
    if Support.panel_allowed?(socket, "job-logs") and socket.assigns.selected_job_id do
      case ReadSupport.job_logs_page(
             socket,
             job_log_page_params(socket, socket.assigns.selected_job_id, 1)
           ) do
        {:ok, page} ->
          {:noreply,
           assign(socket,
             job_log_rows: page.rows,
             job_log_total: page.total,
             page_nums: Map.put(socket.assigns.page_nums, "job-logs", 1),
             job_log_loaded_page: 1,
             job_log_feedback: nil
           )
           |> push_jobs_path(socket.assigns.selected_job_id)}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             job_log_feedback:
               Support.read_error_feedback(
                 reason,
                 "任务日志刷新失败，当前仍显示上一次成功读取的数据。请重试。"
               )
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh-monitor", _params, socket) do
    if Support.monitor_access?(socket) do
      socket =
        assign(socket,
          page_nums: Map.put(socket.assigns.page_nums, "online-users", 1),
          monitor_loading: true,
          monitor_initial_error: nil
        )

      {:noreply, Support.assign_monitor(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("retry-monitor", %{"resource" => resource}, socket) do
    case resource do
      "server" -> {:noreply, Support.assign_monitor_resource(socket, :server)}
      "network" -> {:noreply, Support.assign_monitor_resource(socket, :network)}
      "cache" -> {:noreply, Support.assign_monitor_resource(socket, :cache)}
      "online_users" -> {:noreply, Support.assign_monitor_resource(socket, :online_users)}
      _other -> {:noreply, socket}
    end
  end

  def handle_event("retry-monitor", params, socket),
    do: handle_event("refresh-monitor", params, socket)

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
          :ok ->
            "在线会话已强制下线"

          {:error, :not_found} ->
            Feedback.error(:resource_not_found, "在线会话不存在或已经失效")

          {:error, :unavailable} ->
            Feedback.error(:service_unavailable, "会话服务暂不可用")
        end

      socket = assign(socket, page_nums: Map.put(socket.assigns.page_nums, "online-users", 1))
      {:noreply, Support.assign_monitor(socket, feedback)}
    else
      {:noreply, socket}
    end
  end

  def restore_selected_job_if_needed(socket, "jobs") do
    selected_job = socket.assigns[:selected_job]

    case socket.assigns[:selected_job_id] do
      job_id when is_binary(job_id) and job_id != "" ->
        log_page = get_in(socket.assigns, [:page_nums, "job-logs"]) || 1
        loaded_job_id = if is_map(selected_job), do: selected_job["jobId"], else: nil

        if is_nil(selected_job) or to_string(loaded_job_id || "") != job_id or
             socket.assigns[:job_log_loaded_page] != log_page do
          select_job(socket, job_id, false, log_page)
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def restore_selected_job_if_needed(socket, _panel), do: {:noreply, socket}

  defp select_job(socket, job_id, push?, requested_log_page) do
    if Support.panel_allowed?(socket, "jobs") do
      # 切换详情时先清除旧任务数据，读取失败也不能把旧任务显示成当前任务。
      socket =
        assign(socket,
          selected_job_id: job_id,
          selected_job: nil,
          job_log_rows: [],
          job_log_total: 0,
          job_log_loaded_page: nil,
          page_nums: Map.put(socket.assigns.page_nums, "job-logs", requested_log_page),
          job_log_feedback: nil
        )

      with {:ok, job} <- Job.get_job(job_id, Support.authorization_options(socket, "job:read")),
           {:ok, page, page_number} <-
             load_selected_job_log_page(socket, job_id, requested_log_page) do
        socket =
          assign(socket,
            selected_job_id: job_id,
            selected_job: Job.job_to_map(job),
            job_log_rows: page.rows,
            job_log_total: page.total,
            job_log_loaded_page: page_number,
            page_nums: Map.put(socket.assigns.page_nums, "job-logs", page_number),
            job_log_feedback: nil
          )

        socket =
          if push? or page_number != requested_log_page,
            do: push_jobs_path(socket, job_id),
            else: socket

        {:noreply, socket}
      else
        {:error, reason} ->
          socket =
            assign(socket,
              job_log_feedback: Support.read_error_feedback(reason, "无法读取所选任务或执行日志，请重试")
            )

          socket = if push?, do: push_jobs_path(socket, job_id), else: socket
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp load_selected_job_log_page(socket, job_id, requested_page) do
    with {:ok, requested_result} <-
           ReadSupport.job_logs_page(
             socket,
             job_log_page_params(socket, job_id, requested_page)
           ) do
      last_page =
        max(
          div(requested_result.total + job_log_page_size(socket) - 1, job_log_page_size(socket)),
          1
        )

      page = min(requested_page, last_page)

      if page == requested_page do
        {:ok, requested_result, page}
      else
        with {:ok, last_result} <-
               ReadSupport.job_logs_page(socket, job_log_page_params(socket, job_id, page)) do
          {:ok, last_result, page}
        end
      end
    end
  end

  defp job_log_page_size(socket),
    do: get_in(socket.assigns, [:page_sizes, "job-logs"]) || 50

  defp authorization(socket, permission) do
    principal =
      (socket.assigns[:current_user] || %{})
      |> Map.put(:permissions, List.wrap(socket.assigns[:permissions]))

    [authorization: %{principal: principal, permission: permission}]
  end

  defp current_job_filter(socket), do: Map.get(socket.assigns, :job_filter, %{"keyword" => ""})

  defp push_jobs_path(socket, selected_job_id) do
    Phoenix.LiveView.push_patch(socket,
      to:
        FilterNavigation.path(
          "jobs",
          current_job_filter(socket),
          get_in(socket.assigns, [:page_nums, "jobs"]) || 1,
          get_in(socket.assigns, [:page_nums, "job-logs"]) || 1,
          selected_job_id
        )
    )
  end

  defp job_page_params(socket, page, filter) do
    Map.merge(filter, %{
      "pageNum" => page,
      "pageSize" => get_in(socket.assigns, [:page_sizes, "jobs"]) || 20
    })
  end

  defp job_log_page_params(socket, job_id, page) do
    %{
      "jobId" => job_id,
      "pageNum" => page,
      "pageSize" => get_in(socket.assigns, [:page_sizes, "job-logs"]) || 50
    }
  end

  defp refresh_job_page(socket, page, clear_selection? \\ false) do
    case ReadSupport.jobs_page(socket, job_page_params(socket, page, current_job_filter(socket))) do
      {:ok, result} ->
        attrs = [
          job_rows: result.rows,
          job_total: result.total,
          page_nums: Map.put(socket.assigns.page_nums, "jobs", page)
        ]

        # 分页成功后清除上一页的批量选择，避免操作不可见任务。
        attrs = if clear_selection?, do: Keyword.put(attrs, :selected_job_ids, []), else: attrs

        assign(socket, attrs)
        |> push_jobs_path(socket.assigns[:selected_job_id])

      {:error, reason} ->
        assign(socket, job_feedback: Support.read_error_feedback(reason, "任务列表读取失败，请重试"))
    end
  end

  defp paginate_jobs(socket, page) do
    case Integer.parse(to_string(page)) do
      {page_number, ""} when page_number > 0 ->
        {:noreply, refresh_job_page(socket, page_number, true)}

      _ ->
        {:noreply, socket}
    end
  end

  defp paginate_job_logs(socket, page) do
    with {page_number, ""} when page_number > 0 <- Integer.parse(to_string(page)),
         job_id when is_binary(job_id) <- socket.assigns.selected_job_id,
         {:ok, result} <-
           ReadSupport.job_logs_page(socket, job_log_page_params(socket, job_id, page_number)) do
      {:noreply,
       assign(socket,
         job_log_rows: result.rows,
         job_log_total: result.total,
         job_log_loaded_page: page_number,
         page_nums: Map.put(socket.assigns.page_nums, "job-logs", page_number),
         job_log_feedback: nil
       )
       |> push_jobs_path(job_id)}
    else
      {:error, reason} ->
        {:noreply,
         assign(socket,
           job_log_feedback:
             Support.read_error_feedback(
               reason,
               "任务日志分页读取失败，当前仍显示上一次成功读取的数据。请重试。"
             )
         )}

      _ ->
        {:noreply, socket}
    end
  end
end
