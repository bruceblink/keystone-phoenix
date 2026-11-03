defmodule KeystonePhoenix.Job.Invoke do
  @moduledoc "Allow-listed job targets compatible with Keystone's invokeTarget contract."

  import Ecto.Query
  require Logger

  alias KeystonePhoenix.Job.SysJobLog
  alias KeystonePhoenix.Repo

  @target_pattern ~r/^([A-Za-z][A-Za-z0-9_]*)\.([A-Za-z][A-Za-z0-9_]*)\(\)$/

  @targets [
    %{
      "invokeTarget" => "demoJobTask.printHeartbeat()",
      "beanName" => "demoJobTask",
      "methodName" => "printHeartbeat",
      "name" => "打印心跳日志",
      "group" => "示例任务",
      "description" => "用于验证定时任务是否能按计划触发"
    },
    %{
      "invokeTarget" => "demoJobTask.refreshDemoCache()",
      "beanName" => "demoJobTask",
      "methodName" => "refreshDemoCache",
      "name" => "模拟缓存刷新",
      "group" => "示例任务",
      "description" => "用于验证业务型无参任务调用"
    },
    %{
      "invokeTarget" => "demoJobTask.simulateLongRunningJob()",
      "beanName" => "demoJobTask",
      "methodName" => "simulateLongRunningJob",
      "name" => "模拟耗时任务",
      "group" => "示例任务",
      "description" => "用于验证禁止并发执行配置"
    },
    %{
      "invokeTarget" => "sysJobLogCleanupTask.cleanExpiredJobLogs()",
      "beanName" => "sysJobLogCleanupTask",
      "methodName" => "cleanExpiredJobLogs",
      "name" => "清理定时任务运行日志",
      "group" => "系统维护",
      "description" => "清理 sys_job_log 表中 30 天之前的历史数据"
    }
  ]

  @doc "Returns targets that can be selected by the management frontend."
  def targets, do: @targets

  @doc "Validates target syntax, allow-list membership, and JSON parameters."
  def validate_target(target, params \\ nil) do
    with {:ok, _target} <- find_target(target),
         :ok <- validate_params(params) do
      :ok
    end
  end

  @doc "Invokes one allow-listed target synchronously."
  def run(target, params \\ nil) do
    with {:ok, target_spec} <- find_target(target),
         :ok <- validate_params(params) do
      run_target(target_spec["invokeTarget"], params)
    end
  end

  defp find_target(target) when is_binary(target) do
    target = String.trim(target)

    case Regex.match?(@target_pattern, target) do
      false ->
        {:error, :invoke_target_invalid}

      true ->
        case Enum.find(@targets, &(&1["invokeTarget"] == target)) do
          nil -> {:error, :invoke_target_not_found}
          target_spec -> {:ok, target_spec}
        end
    end
  end

  defp find_target(_target), do: {:error, :invoke_target_invalid}

  defp validate_params(params) when params in [nil, ""], do: :ok

  defp validate_params(params) when is_binary(params) do
    case Jason.decode(params) do
      {:ok, decoded} when is_map(decoded) -> :ok
      {:ok, _decoded} -> {:error, :params_invalid}
      {:error, _reason} -> {:error, :params_invalid}
    end
  end

  defp validate_params(_params), do: {:error, :params_invalid}

  defp run_target("demoJobTask.printHeartbeat()", _params) do
    Logger.info("demo scheduled job heartbeat")
    :ok
  end

  defp run_target("demoJobTask.refreshDemoCache()", _params) do
    Logger.info("demo scheduled job refreshed cache placeholder")
    :ok
  end

  defp run_target("demoJobTask.simulateLongRunningJob()", _params) do
    Logger.info("demo long running scheduled job started")
    Process.sleep(3_000)
    Logger.info("demo long running scheduled job finished")
    :ok
  end

  defp run_target("sysJobLogCleanupTask.cleanExpiredJobLogs()", params) do
    retention_days = retention_days(params)
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 86_400, :second)

    {count, _} = Repo.delete_all(from(log in SysJobLog, where: log.create_time < ^cutoff))

    Logger.info(
      "cleaned expired scheduled job logs, retention_days=#{retention_days}, count=#{count}"
    )

    :ok
  end

  defp retention_days(nil), do: 30

  defp retention_days(params) when is_binary(params) do
    case Jason.decode(params) do
      {:ok, decoded} -> retention_days(decoded)
      _ -> 30
    end
  end

  defp retention_days(%{"retentionDays" => value}), do: positive_retention(value)
  defp retention_days(%{"retention_days" => value}), do: positive_retention(value)
  defp retention_days(_params), do: 30

  defp positive_retention(value) when is_integer(value) and value > 0, do: value

  defp positive_retention(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> 30
    end
  end

  defp positive_retention(_value), do: 30
end
