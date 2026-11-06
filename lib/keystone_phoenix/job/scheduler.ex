defmodule KeystonePhoenix.Job.Scheduler do
  @moduledoc """
  Runs enabled database jobs against their six-field Cron expressions.

  The scheduler polls definitions frequently enough to catch a matching
  second, while the execution log remains the source of truth for each run.
  """

  use GenServer

  import Ecto.Query
  require Logger

  alias KeystonePhoenix.Job.{Cron, Runner, SysJob}
  alias KeystonePhoenix.Repo

  @default_tick_interval_ms 1_000

  @doc "Starts the singleton scheduled-job poller."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Cancels automatic runs currently executing for a job."
  def cancel(job_id), do: GenServer.call(__MODULE__, {:cancel, job_id})

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{last_trigger: %{}, running: %{}}}
  end

  @impl true
  def handle_info(:tick, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    state = expire_running_jobs(state)

    state =
      case Repo.all(from job in SysJob, where: job.status == 1) do
        jobs when is_list(jobs) ->
          state
          |> prune_last_triggers(jobs)
          |> trigger_due_jobs(jobs, now)

        _ ->
          state
      end

    schedule_tick()
    {:noreply, state}
  rescue
    error ->
      Logger.warning("scheduled job poll failed: #{Exception.message(error)}")
      schedule_tick()
      {:noreply, state}
  end

  @impl true
  def handle_info({:job_finished, job_id, pid, result}, state) do
    if result != :ok do
      Logger.warning("scheduled job #{job_id} finished with #{inspect(result)}")
    end

    {:noreply, remove_running(state, job_id, pid)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    if reason not in [:normal, :noproc] do
      Logger.warning("scheduled job task #{inspect(pid)} stopped: #{inspect(reason)}")
    end

    {:noreply, remove_running_pid(state, pid)}
  end

  @impl true
  def handle_call({:cancel, job_id}, _from, state) do
    case Map.get(state.running, parse_job_id(job_id)) do
      nil ->
        {:reply, :not_found, state}

      running ->
        Enum.each(running, fn {pid, %{job: job}} ->
          Process.exit(pid, :kill)
          log_result(Runner.record_cancel(job), "cancelled", job.job_id)
        end)

        {:reply, :ok, remove_running_job(state, parse_job_id(job_id))}
    end
  end

  @doc "Drops trigger timestamps for jobs that are no longer enabled."
  def prune_last_triggers(state, jobs) when is_map(state) and is_list(jobs) do
    active_job_ids = Enum.map(jobs, & &1.job_id)
    %{state | last_trigger: Map.take(state.last_trigger, active_job_ids)}
  end

  defp trigger_due_jobs(state, jobs, now) do
    Enum.reduce(jobs, state, fn job, state ->
      trigger_job(job, now, state)
    end)
  end

  defp trigger_job(job, now, state) do
    trigger_key = DateTime.to_unix(now)

    if Cron.matches?(job.cron_expression, now) and
         Map.get(state.last_trigger, job.job_id) != trigger_key do
      state = put_in(state.last_trigger[job.job_id], trigger_key)

      if job.concurrent == 0 and running_count(state, job.job_id) > 0 do
        case Runner.record_skip(job, "任务仍在执行，跳过本次调度") do
          :ok ->
            state

          {:error, reason} ->
            Logger.warning("could not persist skipped job #{job.job_id}: #{inspect(reason)}")
            state
        end
      else
        start_job(job, state)
      end
    else
      state
    end
  end

  defp start_job(job, state) do
    scheduler = self()

    case Task.Supervisor.start_child(KeystonePhoenix.JobTaskSupervisor, fn ->
           result = Runner.run(job, 1)
           send(scheduler, {:job_finished, job.job_id, self(), result})
           result
         end) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        entry = %{ref: ref, job: job, started_at: System.monotonic_time(:millisecond)}
        running = Map.update(state.running, job.job_id, %{pid => entry}, &Map.put(&1, pid, entry))
        %{state | running: running}

      {:error, reason} ->
        Logger.warning("could not start scheduled job #{job.job_id}: #{inspect(reason)}")
        log_result(Runner.record_skip(job, "任务执行资源达到上限，跳过本次调度"), "skipped", job.job_id)
        state
    end
  end

  defp running_count(state, job_id), do: state.running |> Map.get(job_id, %{}) |> map_size()

  defp expire_running_jobs(state) do
    timeout_ms = Application.get_env(:keystone_phoenix, :job_execution_timeout_ms, 30_000)
    now = System.monotonic_time(:millisecond)

    Enum.reduce(state.running, state, fn {job_id, running}, state ->
      Enum.reduce(running, state, fn {pid, %{job: job, started_at: started_at}}, state ->
        if now - started_at >= timeout_ms do
          Process.exit(pid, :kill)
          log_result(Runner.record_timeout(job, timeout_ms), "timed out", job_id)
          remove_running(state, job_id, pid)
        else
          state
        end
      end)
    end)
  end

  defp log_result(:ok, _event, _job_id), do: :ok

  defp log_result({:error, reason}, event, job_id) do
    Logger.warning("could not persist #{event} log for job #{job_id}: #{inspect(reason)}")
  end

  defp remove_running(state, job_id, pid) do
    case Map.get(state.running, job_id) do
      nil ->
        state

      running ->
        running = Map.delete(running, pid)

        running =
          if map_size(running) == 0,
            do: Map.delete(state.running, job_id),
            else: Map.put(state.running, job_id, running)

        %{state | running: running}
    end
  end

  defp remove_running_job(state, job_id),
    do: %{state | running: Map.delete(state.running, job_id)}

  defp parse_job_id(value) when is_integer(value) and value > 0, do: value

  defp parse_job_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp parse_job_id(_value), do: nil

  defp remove_running_pid(state, pid) do
    Enum.reduce(state.running, state, fn {job_id, running}, state ->
      if Map.has_key?(running, pid), do: remove_running(state, job_id, pid), else: state
    end)
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, tick_interval_ms())

  defp tick_interval_ms do
    Application.get_env(
      :keystone_phoenix,
      :job_scheduler_interval_ms,
      @default_tick_interval_ms
    )
    |> max(250)
  end
end
