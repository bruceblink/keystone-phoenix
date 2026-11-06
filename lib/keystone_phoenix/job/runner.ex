defmodule KeystonePhoenix.Job.Runner do
  @moduledoc "Executes a job target and persists one run log."

  alias KeystonePhoenix.Job.{Invoke, SysJob, SysJobLog}
  alias KeystonePhoenix.Repo

  @max_message_length 500
  @max_exception_length 2000

  @doc "Runs a job once and records a manual or automatic execution log."
  def run(%SysJob{} = job, trigger_type) when trigger_type in [1, 2] do
    start_time = DateTime.utc_now()
    started_at = System.monotonic_time(:millisecond)

    result =
      try do
        Invoke.run(job.invoke_target, job.job_params)
      rescue
        error -> {:error, {:exception, error, __STACKTRACE__}}
      catch
        kind, reason -> {:error, {kind, reason, []}}
      end

    {status, message, exception_info, return} = result_fields(result)
    end_time = DateTime.utc_now()
    duration_ms = System.monotonic_time(:millisecond) - started_at

    :telemetry.execute(
      [:keystone_phoenix, :job, :run],
      %{duration_ms: duration_ms},
      %{job_id: job.job_id, trigger_type: trigger_type, status: status}
    )

    attrs = %{
      job_id: job.job_id,
      job_name: job.job_name,
      job_group: job.job_group,
      invoke_target: job.invoke_target,
      job_params: job.job_params,
      cron_expression: job.cron_expression,
      trigger_type: trigger_type,
      status: status,
      job_message: message,
      exception_info: exception_info,
      start_time: start_time,
      end_time: end_time,
      duration_ms: duration_ms,
      create_time: start_time
    }

    persist_log(attrs, return)
  end

  @doc "Records a skipped automatic run when a non-concurrent job is still running."
  def record_skip(%SysJob{} = job, message) do
    now = DateTime.utc_now()

    attrs = %{
      job_id: job.job_id,
      job_name: job.job_name,
      job_group: job.job_group,
      invoke_target: job.invoke_target,
      job_params: job.job_params,
      cron_expression: job.cron_expression,
      trigger_type: 1,
      status: 2,
      job_message: message,
      exception_info: "",
      start_time: now,
      end_time: now,
      duration_ms: 0,
      create_time: now
    }

    persist_log(attrs, :ok)
  end

  @doc "Records an automatic run that was terminated after exceeding the timeout."
  def record_timeout(%SysJob{} = job, timeout_ms) do
    now = DateTime.utc_now()

    attrs = %{
      job_id: job.job_id,
      job_name: job.job_name,
      job_group: job.job_group,
      invoke_target: job.invoke_target,
      job_params: job.job_params,
      cron_expression: job.cron_expression,
      trigger_type: 1,
      status: 0,
      job_message: "任务执行超时（超过#{timeout_ms}毫秒）",
      exception_info: "任务进程已被调度器终止",
      start_time: now,
      end_time: now,
      duration_ms: timeout_ms,
      create_time: now
    }

    persist_log(attrs, :ok)
  end

  @doc "Records an automatic run cancelled by an administrator."
  def record_cancel(%SysJob{} = job) do
    now = DateTime.utc_now()

    attrs = %{
      job_id: job.job_id,
      job_name: job.job_name,
      job_group: job.job_group,
      invoke_target: job.invoke_target,
      job_params: job.job_params,
      cron_expression: job.cron_expression,
      trigger_type: 1,
      status: 2,
      job_message: "任务已取消",
      exception_info: "",
      start_time: now,
      end_time: now,
      duration_ms: 0,
      create_time: now
    }

    persist_log(attrs, :ok)
  end

  defp persist_log(attrs, return) do
    case Repo.insert(SysJobLog.changeset(%SysJobLog{}, attrs)) do
      {:ok, _log} -> return
      {:error, _changeset} -> {:error, :log_persist_failed}
    end
  end

  defp result_fields(:ok), do: {1, "任务执行成功", "", :ok}

  defp result_fields({:error, {kind, reason, stacktrace}}) do
    detail = Exception.message(reason)
    message = truncate("任务执行失败：#{detail}")
    exception = truncate_exception(kind, reason, stacktrace)
    {0, message, exception, {:error, :execute_failed}}
  end

  defp result_fields({:error, reason}) do
    message = truncate("任务执行失败：#{format_reason(reason)}")
    {0, message, "", {:error, reason}}
  end

  defp truncate(value), do: String.slice(to_string(value), 0, @max_message_length)

  defp truncate_exception(kind, reason, stacktrace) do
    stack = Exception.format(kind, reason, stacktrace)
    String.slice(stack, 0, @max_exception_length)
  end

  defp format_reason(:invoke_target_invalid), do: "调用目标无效"
  defp format_reason(:invoke_target_not_found), do: "调用目标不存在"
  defp format_reason(:params_invalid), do: "任务参数无效"
  defp format_reason(reason), do: inspect(reason)
end
