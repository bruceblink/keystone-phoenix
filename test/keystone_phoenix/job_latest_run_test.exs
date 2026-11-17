defmodule KeystonePhoenix.JobLatestRunTest do
  use KeystonePhoenix.DataCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Job.{Lock, Runner, SysJob, SysJobLog}
  alias KeystonePhoenix.Repo

  @moduletag :integration

  test "成功、失败、跳过和超时都更新任务的最近运行结果" do
    job = create_job()

    assert :ok = Runner.run(job, 2)
    assert_run_state(job.job_id, "SUCCESS")

    failed_job = %{job | invoke_target: "missingJob.run()"}
    assert {:error, :invoke_target_not_found} = Runner.run(failed_job, 2)
    assert_run_state(job.job_id, "FAILED")

    assert :ok = Lock.acquire(job.job_id)

    try do
      assert {:skipped, :already_running} = Runner.run(job, 2)
    after
      Lock.release(job.job_id)
    end

    assert_run_state(job.job_id, "SKIPPED")

    assert :ok = Runner.record_timeout(job, 100, 2)
    assert_run_state(job.job_id, "FAILED")
  end

  test "日志校验失败时不把未记录的成功更新为最近运行结果" do
    job = create_job()
    previous_run_at = DateTime.add(DateTime.utc_now(), -60, :second)

    Repo.update!(Ecto.Changeset.change(job, last_status: "FAILED", last_run_at: previous_run_at))

    invalid_log_job = %{job | job_name: String.duplicate("x", 65)}
    assert {:error, :log_persist_failed} = Runner.run(invalid_log_job, 2)

    persisted = Repo.get!(SysJob, job.job_id)
    assert persisted.last_status == "FAILED"
    assert persisted.last_run_at == previous_run_at

    assert Repo.aggregate(
             from(log in SysJobLog, where: log.job_id == ^job.job_id),
             :count,
             :job_log_id
           ) == 0
  end

  defp create_job do
    Repo.insert!(
      SysJob.changeset(%SysJob{}, %{
        job_code: "latest-run-#{System.unique_integer([:positive])}",
        job_name: "最近运行状态测试",
        job_group: "integration",
        invoke_target: "demoJobTask.printHeartbeat()",
        cron_expression: "*/5 * * * * *",
        concurrent: 0,
        status: 0
      })
    )
  end

  defp assert_run_state(job_id, expected_status) do
    job = Repo.get!(SysJob, job_id)
    dto = KeystonePhoenix.Job.job_to_map(job)

    assert job.last_status == expected_status
    assert %DateTime{} = job.last_run_at
    assert dto["lastStatus"] == expected_status

    assert {:ok, %DateTime{time_zone: "Etc/UTC"}, _offset} =
             DateTime.from_iso8601(dto["lastRunAt"])
  end
end
