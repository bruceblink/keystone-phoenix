defmodule KeystonePhoenix.Job.RunnerTest do
  use KeystonePhoenix.DataCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Job.{Lock, Runner, Scheduler, SysJob, SysJobLog}
  alias KeystonePhoenix.Repo

  setup do
    previous_interval = Application.get_env(:keystone_phoenix, :job_scheduler_interval_ms)
    Application.put_env(:keystone_phoenix, :job_scheduler_interval_ms, 250)

    on_exit(fn ->
      Application.put_env(:keystone_phoenix, :job_scheduler_interval_ms, previous_interval)
    end)

    :ok
  end

  test "manual execution is skipped while the real scheduler runs a non-concurrent job" do
    job = create_job(concurrent: 0, invoke_target: "demoJobTask.simulateLongRunningJob()")
    scheduler = start_supervised!(Scheduler)

    assert_eventually(fn -> running?(scheduler, job.job_id) and lock_held?(job.job_id) end)
    assert {:skipped, :already_running} = Runner.run(job, 2)

    assert_eventually(fn ->
      Enum.any?(logs(job.job_id), &(&1.trigger_type == 2 and &1.status == 2))
    end)

    assert :ok = Scheduler.cancel(job.job_id)

    assert_eventually(fn ->
      not running?(scheduler, job.job_id) and lock_available?(job.job_id)
    end)

    assert Enum.any?(logs(job.job_id), &(&1.trigger_type == 1 and &1.status == 2))
  end

  test "scheduler timeout kills the automatic runner and releases its concurrency lock" do
    previous_timeout = Application.get_env(:keystone_phoenix, :job_execution_timeout_ms)
    Application.put_env(:keystone_phoenix, :job_execution_timeout_ms, 100)

    on_exit(fn ->
      Application.put_env(:keystone_phoenix, :job_execution_timeout_ms, previous_timeout)
    end)

    job = create_job(concurrent: 0, invoke_target: "demoJobTask.simulateLongRunningJob()")
    scheduler = start_supervised!(Scheduler)

    assert_eventually(fn -> running?(scheduler, job.job_id) and lock_held?(job.job_id) end)

    assert {:ok, _job} =
             KeystonePhoenix.Job.update_job_status(job.job_id, 0,
               authorization: %{
                 principal: %{data_scope: "TENANT", permissions: ["job:update-status"]}
               }
             )

    assert_eventually(fn ->
      Enum.any?(logs(job.job_id), &(&1.trigger_type == 1 and &1.status == 0))
    end)

    assert lock_available?(job.job_id)
    refute running?(scheduler, job.job_id)
  end

  test "manual execution uses the task timeout and persists a timeout log" do
    previous_timeout = Application.get_env(:keystone_phoenix, :job_execution_timeout_ms)
    Application.put_env(:keystone_phoenix, :job_execution_timeout_ms, 100)

    on_exit(fn ->
      Application.put_env(:keystone_phoenix, :job_execution_timeout_ms, previous_timeout)
    end)

    job = create_job(concurrent: 0, invoke_target: "demoJobTask.simulateLongRunningJob()")

    assert {:error, :execution_timeout} =
             KeystonePhoenix.Job.run_job(job.job_id,
               authorization: %{principal: %{data_scope: "TENANT", permissions: ["job:run"]}}
             )

    assert Enum.any?(logs(job.job_id), &(&1.trigger_type == 2 and &1.status == 0))
    assert lock_available?(job.job_id)
  end

  test "manual execution returns a resource error when the task supervisor is full" do
    {:ok, supervisor} = Task.Supervisor.start_link(max_children: 1)
    first_task = Task.Supervisor.async_nolink(supervisor, fn -> Process.sleep(5_000) end)
    previous_supervisor = Application.get_env(:keystone_phoenix, :job_task_supervisor)
    Application.put_env(:keystone_phoenix, :job_task_supervisor, supervisor)

    on_exit(fn ->
      if Process.alive?(first_task.pid), do: Process.exit(first_task.pid, :kill)
      Process.exit(supervisor, :shutdown)

      if is_nil(previous_supervisor) do
        Application.delete_env(:keystone_phoenix, :job_task_supervisor)
      else
        Application.put_env(:keystone_phoenix, :job_task_supervisor, previous_supervisor)
      end
    end)

    job = create_job(concurrent: 1)

    assert {:error, :resource_exhausted} =
             KeystonePhoenix.Job.run_job(job.job_id,
               authorization: %{principal: %{data_scope: "TENANT", permissions: ["job:run"]}}
             )
  end

  test "a killed manual caller releases the job lock" do
    job = create_job(concurrent: 0, invoke_target: "demoJobTask.simulateLongRunningJob()")
    {pid, ref} = spawn_monitor(fn -> Runner.run(job, 2) end)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    assert_eventually(fn -> lock_held?(job.job_id) end, 25)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1_000

    assert lock_available?(job.job_id)
  end

  test "execution failure and log persistence failure both release the job lock" do
    invalid_target = create_job(concurrent: 0, invoke_target: "notAllowed.run()")
    assert {:error, :invoke_target_not_found} = Runner.run(invalid_target, 2)
    assert lock_available?(invalid_target.job_id)

    invalid_log = %{create_job(concurrent: 0) | job_name: String.duplicate("x", 65)}
    assert {:error, :log_persist_failed} = Runner.run(invalid_log, 2)
    assert lock_available?(invalid_log.job_id)
  end

  test "concurrent jobs keep the existing direct execution and manual log behavior" do
    job = create_job(concurrent: 1)

    {first, first_ref} = spawn_monitor(fn -> Runner.run(job, 2) end)
    {second, second_ref} = spawn_monitor(fn -> Runner.run(job, 2) end)

    assert_eventually(fn -> Process.alive?(first) and Process.alive?(second) end)
    refute lock_held?(job.job_id)

    assert_receive {:DOWN, ^first_ref, :process, ^first, :normal}, 4_000
    assert_receive {:DOWN, ^second_ref, :process, ^second, :normal}, 4_000
    assert Enum.count(logs(job.job_id), &(&1.trigger_type == 2 and &1.status == 1)) == 2
  end

  defp create_job(opts) do
    defaults = [
      job_name: "runner test",
      job_group: "test",
      invoke_target: "demoJobTask.printHeartbeat()",
      cron_expression: "* * * * * *",
      concurrent: 0,
      status: 1
    ]

    Repo.insert!(SysJob.changeset(%SysJob{}, Map.new(Keyword.merge(defaults, opts))))
  end

  defp logs(job_id) do
    Repo.all(
      from(log in SysJobLog,
        where: log.job_id == ^job_id,
        order_by: [asc: log.job_log_id]
      )
    )
  end

  defp running?(scheduler, job_id) do
    scheduler
    |> :sys.get_state()
    |> Map.fetch!(:running)
    |> Map.has_key?(job_id)
  end

  defp lock_held?(job_id), do: Lock.held?(job_id)
  defp lock_available?(job_id), do: not Lock.held?(job_id)

  defp assert_eventually(fun, attempts \\ 150)

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      if attempts == 0 do
        flunk("condition was not met before timeout")
      else
        Process.sleep(20)
        assert_eventually(fun, attempts - 1)
      end
    end
  end
end
