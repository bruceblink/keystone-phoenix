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

  @tick_interval_ms 250

  @doc "Starts the singleton scheduled-job poller."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{last_trigger: %{}, running: %{}}}
  end

  @impl true
  def handle_info(:tick, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    state =
      case Repo.all(from job in SysJob, where: job.status == 1) do
        jobs when is_list(jobs) -> trigger_due_jobs(jobs, now, state)
        _ -> state
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

  defp trigger_due_jobs(jobs, now, state) do
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
        running = Map.update(state.running, job.job_id, %{pid => ref}, &Map.put(&1, pid, ref))
        %{state | running: running}

      {:error, reason} ->
        Logger.warning("could not start scheduled job #{job.job_id}: #{inspect(reason)}")
        state
    end
  end

  defp running_count(state, job_id), do: state.running |> Map.get(job_id, %{}) |> map_size()

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

  defp remove_running_pid(state, pid) do
    Enum.reduce(state.running, state, fn {job_id, running}, state ->
      if Map.has_key?(running, pid), do: remove_running(state, job_id, pid), else: state
    end)
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_interval_ms)
end
