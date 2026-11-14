defmodule KeystonePhoenix.JobLogUuidTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Job.{SysJob, SysJobLog}
  alias KeystonePhoenix.Log.{SysLoginInfo, SysOperationLog}
  alias KeystonePhoenix.Repo

  test "job and log changesets or write boundaries use UUIDv7 identifiers" do
    job =
      SysJob.changeset(%SysJob{}, %{
        job_name: "UUID 任务",
        job_group: "system",
        invoke_target: "demoJobTask.printHeartbeat()",
        cron_expression: "*/5 * * * * *",
        concurrent: 0,
        status: 1
      })

    job_log =
      SysJobLog.changeset(%SysJobLog{}, %{
        job_name: "UUID 任务",
        job_group: "system",
        invoke_target: "demoJobTask.printHeartbeat()",
        trigger_type: 1,
        status: 1,
        start_time: DateTime.utc_now()
      })

    assert Identity.canonical?(Ecto.Changeset.get_change(job, :job_id))
    assert Identity.canonical?(Ecto.Changeset.get_change(job_log, :job_log_id))
    assert Identity.canonical?(Identity.v7())
  end

  test "job and log identity columns use PostgreSQL UUID" do
    %{rows: rows} =
      Repo.query!("""
      SELECT table_name, column_name, data_type
      FROM information_schema.columns
      WHERE table_schema = current_schema()
        AND ((table_name = 'sys_job' AND column_name IN ('job_id', 'creator_id', 'created_by', 'updater_id'))
          OR (table_name = 'sys_job_log' AND column_name IN ('job_log_id', 'job_id'))
          OR (table_name = 'sys_login_info' AND column_name = 'info_id')
          OR (table_name = 'sys_operation_log' AND column_name IN ('operation_id', 'user_id', 'dept_id')))
      """)

    assert length(rows) == 10
    assert Enum.all?(rows, &(Enum.at(&1, 2) == "uuid"))
    assert %SysLoginInfo{}
    assert %SysOperationLog{}
  end

  test "job log migration is guarded for replay" do
    source =
      Path.expand(
        "../../priv/repo/migrations/20261114140000_rebuild_job_log_ids_as_uuid.exs",
        __DIR__
      )

    source = File.read!(source)
    assert source =~ "unless uuid_ready?()"

    assert source =~
             "DROP TABLE IF EXISTS sys_job_log, sys_job, sys_login_info, sys_operation_log CASCADE"
  end
end
