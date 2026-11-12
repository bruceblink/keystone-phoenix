defmodule KeystonePhoenix.Job do
  @moduledoc "Query, command, and execution boundary for scheduled jobs."

  import Ecto.Query

  alias KeystonePhoenix.Audit
  alias KeystonePhoenix.Job.Authorization
  alias KeystonePhoenix.Job.{Invoke, Runner, SysJob, SysJobLog}
  alias KeystonePhoenix.Pagination
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Repo

  @job_attrs [
    {"jobName", :job_name},
    {"jobGroup", :job_group},
    {"invokeTarget", :invoke_target},
    {"jobParams", :job_params},
    {"cronExpression", :cron_expression},
    {"concurrent", :concurrent},
    {"status", :status},
    {"remark", :remark}
  ]

  @doc "Returns a paginated task list."
  def list_jobs(params \\ %{}) do
    query = from(job in SysJob, order_by: [desc: job.create_time, desc: job.job_id])
    query = filter_contains(query, :job_name, params["jobName"] || params[:job_name])
    query = filter_contains(query, :job_group, params["jobGroup"] || params[:job_group])
    query = filter_integer(query, :status, params["status"] || params[:status])
    paginate(query, params, :job_id, &job_to_map/1)
  end

  @doc "Returns one task definition."
  def get_job(id) do
    case Params.parse_positive_integer(id) do
      {:ok, id} ->
        case Repo.get(SysJob, id) do
          nil -> {:error, :not_found}
          job -> {:ok, job}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc "Creates and validates a task definition."
  def create_job(attrs, actor_or_options \\ nil)

  def create_job(attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Authorization.authorize(options, "system:job:add") do
      create_job(attrs, KeystonePhoenix.Authz.Command.actor_id(options))
    end
  end

  def create_job(attrs, actor_id) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with :ok <- Invoke.validate_target(attrs[:invoke_target], attrs[:job_params]),
         changeset = SysJob.changeset(%SysJob{}, attrs) |> Audit.put_actor(:creator_id, actor_id),
         true <- changeset.valid? do
      Repo.insert(changeset)
    else
      false -> {:error, SysJob.changeset(%SysJob{}, attrs)}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_job(_attrs, _actor_id), do: {:error, :invalid_params}

  @doc "Updates and validates a task definition."
  def update_job(id, attrs, actor_or_options \\ nil)

  def update_job(id, attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Authorization.authorize(options, "system:job:edit") do
      update_job(id, attrs, KeystonePhoenix.Authz.Command.actor_id(options))
    end
  end

  def update_job(id, attrs, actor_id) when is_map(attrs) do
    with {:ok, job} <- get_job(id),
         attrs <- normalize_attrs(attrs),
         :ok <- Invoke.validate_target(attrs[:invoke_target], attrs[:job_params]),
         changeset = SysJob.changeset(job, attrs) |> Audit.put_actor(:updater_id, actor_id),
         true <- changeset.valid? do
      Repo.update(changeset)
    else
      false ->
        case get_job(id) do
          {:ok, job} ->
            changeset = SysJob.changeset(job, normalize_attrs(attrs))
            {:error, Audit.put_actor(changeset, :updater_id, actor_id)}

          error ->
            error
        end

      {:error, reason} ->
        {:error, reason}

      error ->
        error
    end
  end

  def update_job(_id, _attrs, _actor_id), do: {:error, :invalid_params}

  @doc "Changes a task status and returns the updated definition."
  def update_job_status(id, status, options_or_actor \\ nil)

  def update_job_status(id, status, options) when is_list(options) do
    with :ok <- Authorization.authorize(options, "system:job:changeStatus") do
      update_job_status(id, status, KeystonePhoenix.Authz.Command.actor_id(options))
    end
  end

  def update_job_status(id, status, actor_id) do
    with {:ok, job} <- get_job(id),
         {:ok, status} <- positive_status(status) do
      job
      |> Ecto.Changeset.change(status: status)
      |> Audit.put_actor(:updater_id, actor_id)
      |> Repo.update()
    end
  end

  @doc "Deletes task definitions while preserving their execution logs."
  def delete_jobs(ids), do: delete_jobs(ids, nil)

  def delete_jobs(ids, options)

  def delete_jobs(ids, options) when is_list(options) do
    with :ok <- Authorization.authorize(options, "system:job:remove") do
      delete_jobs(ids)
    end
  end

  def delete_jobs(ids, _options) when is_list(ids) do
    ids = ids |> Enum.map(&parse_positive_integer/1) |> Enum.uniq()

    if ids == [] or Enum.any?(ids, &is_nil/1) do
      {:error, :invalid_ids}
    else
      {count, _} = Repo.delete_all(from(job in SysJob, where: job.job_id in ^ids))
      if count == length(ids), do: :ok, else: {:error, :not_found}
    end
  end

  def delete_jobs(_ids, _options), do: {:error, :invalid_ids}

  @doc "Runs a task immediately and persists a manual execution log."
  def run_job(id, options \\ nil)

  def run_job(id, options) when is_list(options) do
    with :ok <- Authorization.authorize(options, "system:job:run") do
      run_job(id)
    end
  end

  def run_job(id, _options) do
    with {:ok, job} <- get_job(id),
         :ok <- Invoke.validate_target(job.invoke_target, job.job_params) do
      run_manual_job(job)
    end
  end

  defp run_manual_job(job) do
    timeout_ms = Application.get_env(:keystone_phoenix, :job_execution_timeout_ms, 30_000)

    supervisor =
      Application.get_env(
        :keystone_phoenix,
        :job_task_supervisor,
        KeystonePhoenix.JobTaskSupervisor
      )

    try do
      task =
        Task.Supervisor.async_nolink(supervisor, fn ->
          Runner.run(job, 2)
        end)

      case Task.yield(task, timeout_ms) do
        {:ok, result} ->
          result

        {:exit, _reason} ->
          {:error, :execute_failed}

        nil ->
          case Task.shutdown(task, :brutal_kill) do
            {:ok, result} ->
              result

            {:exit, _reason} ->
              _ = Runner.record_timeout(job, timeout_ms, 2)
              {:error, :execution_timeout}

            nil ->
              _ = Runner.record_timeout(job, timeout_ms, 2)
              {:error, :execution_timeout}
          end
      end
    rescue
      RuntimeError -> {:error, :resource_exhausted}
    catch
      :exit, _reason -> {:error, :resource_exhausted}
    end
  end

  @doc "Cancels automatic runs currently executing for a task."
  def cancel_job(id, options \\ nil)

  def cancel_job(id, options) when is_list(options) do
    with :ok <- Authorization.authorize(options, "system:job:run") do
      cancel_job(id)
    end
  end

  def cancel_job(id, _options) do
    case parse_positive_integer(id) do
      nil ->
        {:error, :invalid_id}

      job_id ->
        if Process.whereis(KeystonePhoenix.Job.Scheduler) do
          KeystonePhoenix.Job.Scheduler.cancel(job_id)
        else
          :not_found
        end
    end
  end

  @doc "Returns available allow-listed invocation targets."
  def invoke_targets, do: Invoke.targets()

  @doc "Returns paginated execution logs."
  def list_job_logs(params \\ %{}) do
    query = from(log in SysJobLog, order_by: [desc: log.start_time, desc: log.job_log_id])

    query =
      query
      |> filter_integer(:job_id, params["jobId"] || params[:job_id])
      |> filter_contains(:job_name, params["jobName"] || params[:job_name])
      |> filter_contains(:job_group, params["jobGroup"] || params[:job_group])
      |> filter_contains(:invoke_target, params["invokeTarget"] || params[:invoke_target])
      |> filter_integer(:trigger_type, params["triggerType"] || params[:trigger_type])
      |> filter_integer(:status, params["status"] || params[:status])

    paginate(query, params, :job_log_id, &job_log_to_map/1)
  end

  def job_to_map(job) do
    %{
      "jobId" => job.job_id,
      "jobName" => job.job_name,
      "jobGroup" => job.job_group,
      "invokeTarget" => job.invoke_target,
      "jobParams" => job.job_params,
      "cronExpression" => job.cron_expression,
      "concurrent" => job.concurrent,
      "concurrentStr" => yes_or_no(job.concurrent),
      "status" => job.status,
      "statusStr" => job_status(job.status),
      "remark" => job.remark,
      "createTime" => format_datetime(job.create_time)
    }
  end

  def job_log_to_map(log) do
    %{
      "jobLogId" => log.job_log_id,
      "jobId" => log.job_id,
      "jobName" => log.job_name,
      "jobGroup" => log.job_group,
      "invokeTarget" => log.invoke_target,
      "jobParams" => log.job_params,
      "cronExpression" => log.cron_expression,
      "triggerType" => log.trigger_type,
      "triggerTypeStr" => trigger_type(log.trigger_type),
      "status" => log.status,
      "statusStr" => log_status(log.status),
      "jobMessage" => log.job_message,
      "exceptionInfo" => log.exception_info,
      "startTime" => format_datetime(log.start_time),
      "endTime" => format_datetime(log.end_time),
      "durationMs" => log.duration_ms,
      "createTime" => format_datetime(log.create_time)
    }
  end

  defp normalize_attrs(attrs) do
    Enum.reduce(@job_attrs, %{}, fn {json_key, atom_key}, normalized ->
      cond do
        Map.has_key?(attrs, json_key) -> Map.put(normalized, atom_key, Map.get(attrs, json_key))
        Map.has_key?(attrs, atom_key) -> Map.put(normalized, atom_key, Map.get(attrs, atom_key))
        true -> normalized
      end
    end)
  end

  defp positive_status(value) when value in [0, 1], do: {:ok, value}
  defp positive_status(value) when is_binary(value), do: parse_status(value)
  defp positive_status(_value), do: {:error, :invalid_status}

  defp parse_status(value) do
    case Integer.parse(value) do
      {status, ""} when status in [0, 1] -> {:ok, status}
      _ -> {:error, :invalid_status}
    end
  end

  defp paginate(query, params, count_field, mapper) do
    Pagination.page(query, params, count_field, mapper)
  end

  defp filter_contains(query, _field, value) when value in [nil, ""], do: query

  defp filter_contains(query, field, value) do
    pattern = "%" <> String.trim(to_string(value)) <> "%"
    where(query, [record], ilike(field(record, ^field), ^pattern))
  end

  defp filter_integer(query, _field, value) when value in [nil, ""], do: query

  defp filter_integer(query, field, value) do
    case Integer.parse(to_string(value)) do
      {number, ""} -> where(query, [record], field(record, ^field) == ^number)
      _ -> query
    end
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} when number > 0 -> number
      _ -> nil
    end
  end

  defp parse_positive_integer(_value), do: nil

  defp yes_or_no(1), do: "是"
  defp yes_or_no(_value), do: "否"

  defp job_status(1), do: "正常"
  defp job_status(_value), do: "暂停"

  defp trigger_type(1), do: "自动调度"
  defp trigger_type(2), do: "手动执行"
  defp trigger_type(_value), do: "未知"

  defp log_status(0), do: "失败"
  defp log_status(1), do: "成功"
  defp log_status(2), do: "跳过"
  defp log_status(_value), do: "未知"

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
