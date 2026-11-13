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
  alias KeystonePhoenix.Params

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
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    termination = task_termination(state, ref, pid)

    if reason not in [:normal, :noproc] and not expected_kill?(termination, reason) do
      Logger.warning("scheduled job task #{inspect(pid)} stopped: #{inspect(reason)}")
    end

    {:noreply, remove_running_ref(state, ref, pid)}
  end

  # 仅忽略调度器主动取消或超时后预期出现的 :killed 退出。
  def expected_kill?(termination, reason) do
    reason == :killed and
      (termination == :cancelled or match?({:timeout, _timeout_ms}, termination))
  end

  @impl true
  def handle_call({:cancel, job_id}, _from, state) do
    case Map.get(state.running, parse_job_id(job_id)) do
      nil ->
        {:reply, :not_found, state}

      running ->
        state =
          Enum.reduce(running, state, fn {pid, _entry}, state ->
            Process.exit(pid, :kill)
            mark_termination(state, parse_job_id(job_id), pid, :cancelled)
          end)

        {:reply, :ok, state}
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

        entry = %{
          ref: ref,
          job: job,
          started_at: System.monotonic_time(:millisecond),
          termination: nil
        }

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
      Enum.reduce(running, state, fn {pid, entry}, state ->
        if is_nil(entry.termination) and now - entry.started_at >= timeout_ms do
          Process.exit(pid, :kill)
          mark_termination(state, job_id, pid, {:timeout, timeout_ms})
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

  defp mark_termination(state, job_id, pid, termination) do
    case Map.get(state.running, job_id) do
      %{^pid => %{termination: nil} = entry} = running ->
        %{
          state
          | running:
              Map.put(
                state.running,
                job_id,
                Map.put(running, pid, %{entry | termination: termination})
              )
        }

      _ ->
        state
    end
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

  defp parse_job_id(value) do
    case Params.parse_uuid(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp remove_running_ref(state, ref, pid) do
    Enum.reduce(state.running, state, fn {job_id, running}, state ->
      case Map.get(running, pid) do
        %{ref: ^ref, termination: :cancelled} ->
          log_result(Runner.record_cancel(running[pid].job), "cancelled", job_id)
          remove_running(state, job_id, pid)

        %{ref: ^ref, termination: {:timeout, timeout_ms}} ->
          log_result(Runner.record_timeout(running[pid].job, timeout_ms), "timed out", job_id)
          remove_running(state, job_id, pid)

        %{ref: ^ref} ->
          remove_running(state, job_id, pid)

        _ ->
          state
      end
    end)
  end

  defp task_termination(state, ref, pid) do
    Enum.find_value(state.running, fn {_job_id, running} ->
      case Map.get(running, pid) do
        %{ref: ^ref, termination: termination} -> termination
        _ -> nil
      end
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
