defmodule KeystonePhoenix.JobAuditScopeTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Log
  alias KeystonePhoenix.Log.{SysLoginInfo, SysOperationLog}
  alias KeystonePhoenix.Repo

  test "job service commands reject a department-scoped principal" do
    permissions = [
      "job:read",
      "job:create",
      "job:update",
      "job:update-status",
      "job:run",
      "job:delete"
    ]

    authorization = [authorization: %{principal: principal("DEPARTMENT", permissions)}]
    id = Identity.v7()

    assert {:error, :data_scope_denied} = Job.list_jobs(%{}, authorization)
    assert {:error, :data_scope_denied} = Job.get_job(id, authorization)
    assert {:error, :data_scope_denied} = Job.invoke_targets(authorization)
    assert {:error, :data_scope_denied} = Job.list_job_logs(%{}, authorization)
    assert {:error, :data_scope_denied} = Job.create_job(%{"jobName" => "越界任务"}, authorization)
    assert {:error, :data_scope_denied} = Job.update_job(id, %{}, authorization)
    assert {:error, :data_scope_denied} = Job.update_job_status(id, 1, authorization)
    assert {:error, :data_scope_denied} = Job.run_job(id, authorization)
    assert {:error, :data_scope_denied} = Job.cancel_job(id, authorization)
    assert {:error, :data_scope_denied} = Job.delete_jobs([id], authorization)
  end

  test "job service commands use tenant scope for the lifecycle" do
    permissions = [
      "job:read",
      "job:create",
      "job:update",
      "job:update-status",
      "job:run",
      "job:delete"
    ]

    authorization = [authorization: %{principal: principal("TENANT", permissions)}]

    assert {:ok, job} =
             Job.create_job(
               %{
                 "jobName" => "范围任务",
                 "jobGroup" => "测试",
                 "invokeTarget" => "demoJobTask.printHeartbeat()",
                 "cronExpression" => "*/5 * * * * *",
                 "concurrent" => 0,
                 "status" => 0
               },
               authorization
             )

    assert {:ok, page} = Job.list_jobs(%{"jobName" => "范围任务"}, authorization)
    assert Enum.any?(page.rows, &(&1["jobId"] == job.job_id))
    assert {:ok, loaded} = Job.get_job(job.job_id, authorization)
    assert loaded.job_id == job.job_id
    assert {:ok, _targets} = Job.invoke_targets(authorization)
    assert {:ok, _logs} = Job.list_job_logs(%{"jobId" => job.job_id}, authorization)

    assert {:ok, updated} =
             Job.update_job(
               job.job_id,
               %{
                 "jobName" => "范围任务已更新",
                 "invokeTarget" => "demoJobTask.printHeartbeat()",
                 "cronExpression" => "*/5 * * * * *"
               },
               authorization
             )

    assert updated.job_name == "范围任务已更新"
    assert {:ok, status_job} = Job.update_job_status(job.job_id, 1, authorization)
    assert status_job.status == 1
    assert {:error, :not_found} = Job.run_job(Identity.v7(), authorization)
    assert :not_found = Job.cancel_job(Identity.v7(), authorization)
    assert :ok = Job.delete_jobs([job.job_id], authorization)
  end

  test "audit service queries and deletes enforce the audit resource scope" do
    permissions = [
      "login-log:read",
      "login-log:delete",
      "operation-log:read",
      "operation-log:delete"
    ]

    blocked = [authorization: %{principal: principal("DEPARTMENT", permissions)}]

    assert {:error, :data_scope_denied} = Log.list_login_logs(%{}, blocked)
    assert {:error, :data_scope_denied} = Log.list_operation_logs(%{}, blocked)
    assert {:error, :data_scope_denied} = Log.delete_login_logs([Identity.v7()], blocked)
    assert {:error, :data_scope_denied} = Log.delete_operation_logs([Identity.v7()], blocked)

    allowed = [authorization: %{principal: principal("TENANT", permissions)}]
    assert {:ok, _login_logs} = Log.list_login_logs(%{}, allowed)
    assert {:ok, _operation_logs} = Log.list_operation_logs(%{}, allowed)
    assert {:error, :invalid_ids} = Log.delete_login_logs([], allowed)
    assert {:error, :invalid_ids} = Log.delete_operation_logs([], allowed)
  end

  test "mixed audit deletion rolls back every record when one ID is missing" do
    login_id = Identity.v7()
    operation_id = Identity.v7()
    missing_id = Identity.v7()
    now = DateTime.utc_now()

    Repo.insert!(%SysLoginInfo{info_id: login_id, username: "mixed-delete", login_time: now})

    Repo.insert!(%SysOperationLog{
      operation_id: operation_id,
      operation_time: now
    })

    authorization =
      [
        authorization: %{
          principal: principal("TENANT", ["login-log:delete", "operation-log:delete"])
        }
      ]

    assert {:error, :not_found} = Log.delete_login_logs([login_id, missing_id], authorization)
    assert Repo.get!(SysLoginInfo, login_id).deleted == false

    assert {:error, :not_found} =
             Log.delete_operation_logs([operation_id, missing_id], authorization)

    assert Repo.get!(SysOperationLog, operation_id).deleted == false
  end

  test "job and audit service reads require explicit authorization contexts" do
    assert {:error, :authorization_required} = Job.list_jobs(%{}, [])
    assert {:error, :authorization_required} = Log.list_login_logs(%{}, [])
  end

  defp principal(data_scope, permissions), do: %{data_scope: data_scope, permissions: permissions}
end
