defmodule KeystonePhoenix.Job.AuditTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  test "job definition writes store creator and updater IDs" do
    actor =
      %SysUser{user_id: 1101}
      |> SysUser.create_changeset(%{username: unique("job_actor"), password: "Strong!123"})
      |> Repo.insert!()

    assert {:ok, job} =
             Job.create_job(
               %{
                 "jobName" => "审计任务",
                 "jobGroup" => "测试",
                 "invokeTarget" => "demoJobTask.printHeartbeat()",
                 "cronExpression" => "*/5 * * * * *",
                 "concurrent" => 0,
                 "status" => 0
               },
               actor.user_id
             )

    assert job.creator_id == actor.user_id

    assert {:ok, job} =
             Job.update_job(
               job.job_id,
               %{
                 "jobName" => "更新任务",
                 "invokeTarget" => "demoJobTask.printHeartbeat()",
                 "jobParams" => "",
                 "cronExpression" => "*/5 * * * * *"
               },
               actor.user_id
             )

    assert job.updater_id == actor.user_id
    assert {:ok, job} = Job.update_job_status(job.job_id, 1, actor.user_id)
    assert job.updater_id == actor.user_id
  end

  test "principal-aware job writes reject missing permissions" do
    assert {:error, :permission_denied} =
             Job.create_job(
               %{
                 "jobName" => "受保护任务",
                 "jobGroup" => "测试",
                 "invokeTarget" => "demoJobTask.printHeartbeat()"
               },
               authorization: %{principal: %{user_id: 1102, permissions: []}}
             )
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
