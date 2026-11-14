defmodule KeystonePhoenix.OwnerResourceScopeTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Notice
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  test "notice owner scope filters records and rolls back mixed deletes" do
    owner = create_owner()
    other = create_owner()
    owner_auth = authorization(owner.user_id, notice_permissions())
    other_auth = authorization(other.user_id, notice_permissions())

    {:ok, own_notice} = Notice.create_notice(notice_attrs("拥有者公告"), owner_auth)
    {:ok, other_notice} = Notice.create_notice(notice_attrs("其他公告"), other_auth)

    assert {:ok, page} = Notice.list_notices(%{}, owner_auth)
    assert Enum.any?(page.rows, &(&1["noticeId"] == own_notice.notice_id))
    refute Enum.any?(page.rows, &(&1["noticeId"] == other_notice.notice_id))
    assert {:error, :not_found} = Notice.get_notice(other_notice.notice_id, owner_auth)

    assert {:error, :not_found} =
             Notice.update_notice(other_notice.notice_id, %{"status" => 0}, owner_auth)

    assert {:error, :not_found} =
             Notice.delete_notices([own_notice.notice_id, other_notice.notice_id], owner_auth)

    assert {:ok, _} = Notice.get_notice(own_notice.notice_id, owner_auth)
    assert :ok = Notice.delete_notices([own_notice.notice_id], owner_auth)
    assert :ok = Notice.delete_notices([other_notice.notice_id], other_auth)
  end

  test "job owner scope filters execution queries and protects commands" do
    owner = create_owner()
    other = create_owner()
    owner_auth = authorization(owner.user_id, job_permissions())
    other_auth = authorization(other.user_id, job_permissions())

    {:ok, own_job} = Job.create_job(job_attrs("拥有者任务"), owner_auth)
    {:ok, other_job} = Job.create_job(job_attrs("其他任务"), other_auth)

    assert {:ok, page} = Job.list_jobs(%{}, owner_auth)
    assert Enum.any?(page.rows, &(&1["jobId"] == own_job.job_id))
    refute Enum.any?(page.rows, &(&1["jobId"] == other_job.job_id))
    assert {:error, :not_found} = Job.get_job(other_job.job_id, owner_auth)

    assert {:error, :not_found} =
             Job.update_job(other_job.job_id, %{"jobName" => "越界"}, owner_auth)

    assert {:error, :not_found} = Job.run_job(other_job.job_id, owner_auth)
    assert :not_found = Job.cancel_job(other_job.job_id, owner_auth)
    assert {:error, :invalid_id} = Job.cancel_job("bad-id", owner_auth)
    assert {:ok, logs} = Job.list_job_logs(%{"jobId" => other_job.job_id}, owner_auth)
    assert logs.total == 0
    assert {:error, :not_found} = Job.delete_jobs([own_job.job_id, other_job.job_id], owner_auth)
    assert {:ok, _} = Job.get_job(own_job.job_id, owner_auth)
    assert :ok = Job.delete_jobs([own_job.job_id], owner_auth)
    assert :ok = Job.delete_jobs([other_job.job_id], other_auth)
  end

  test "owner resource commands require an explicit principal" do
    id = Identity.v7()
    assert {:error, :authorization_required} = Notice.list_notices(%{}, [])
    assert {:error, :authorization_required} = Job.list_jobs(%{}, [])
    assert {:error, :authorization_required} = Notice.get_notice(id, [])
    assert {:error, :authorization_required} = Job.get_job(id, [])
  end

  defp notice_attrs(title) do
    %{
      "noticeTitle" => title,
      "noticeType" => 1,
      "noticeContent" => "owner scope test",
      "status" => 1
    }
  end

  defp job_attrs(name) do
    %{
      "jobName" => name,
      "jobGroup" => "owner-scope",
      "invokeTarget" => "demoJobTask.printHeartbeat()",
      "cronExpression" => "*/5 * * * * *",
      "concurrent" => 0,
      "status" => 0
    }
  end

  defp authorization(user_id, permissions),
    do: [
      authorization: %{
        principal: %{user_id: user_id, data_scope: "OWNER", permissions: permissions}
      }
    ]

  defp create_owner do
    %SysUser{user_id: Identity.v7()}
    |> SysUser.create_changeset(%{
      username: "owner_scope_#{System.unique_integer([:positive])}",
      password: "Strong!123"
    })
    |> Repo.insert!()
  end

  defp notice_permissions, do: ["notice:read", "notice:create", "notice:update", "notice:delete"]

  defp job_permissions,
    do: ["job:read", "job:create", "job:update", "job:update-status", "job:run", "job:delete"]
end
