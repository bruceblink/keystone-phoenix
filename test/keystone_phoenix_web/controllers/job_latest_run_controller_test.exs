defmodule KeystonePhoenixWeb.JobLatestRunControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Job.SysJob
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @moduletag :integration
  @password "Strong!123"

  test "manual HTTP execution returns its persisted latest result in list and detail" do
    user = create_user(["job:create", "job:read", "job:run"])
    {:ok, tokens} = Auth.login_plaintext(user.username, @password)
    job = create_job()

    initial = get(authorized(build_conn(), tokens.token), "/api/v1/jobs")
    assert %{"data" => initial_rows} = json_response(initial, 200)
    assert %{"lastStatus" => nil, "lastRunAt" => nil} = find_job(initial_rows, job.job_id)

    run_response =
      post(
        authorized(build_conn(), tokens.token),
        "/api/v1/jobs/#{job.job_id}/trigger",
        %{}
      )

    assert %{"data" => %{"triggered" => true}} = json_response(run_response, 200)

    list_response = get(authorized(build_conn(), tokens.token), "/api/v1/jobs")
    assert %{"data" => rows} = json_response(list_response, 200)
    assert %{"lastStatus" => "SUCCESS", "lastRunAt" => last_run_at} = find_job(rows, job.job_id)
    assert {:ok, %DateTime{time_zone: "Etc/UTC"}, _offset} = DateTime.from_iso8601(last_run_at)

    detail_response = get(authorized(build_conn(), tokens.token), "/api/v1/jobs/#{job.job_id}")

    assert %{
             "data" => %{
               "lastStatus" => "SUCCESS",
               "lastRunAt" => ^last_run_at
             }
           } = json_response(detail_response, 200)
  end

  defp create_user(permissions) do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: "任务最近状态测试",
        role_key: "job_latest_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: "ALL",
        status: 1
      })
      |> Repo.insert!()

    Enum.each(permissions, fn permission ->
      entry = Repo.get_by!(SysPermission, permission: permission)
      Repo.insert!(%SysRolePermission{role_id: role.role_id, permission_id: entry.permission_id})
    end)

    PolicyCache.invalidate()

    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role.role_id,
      username: "job_latest_#{System.unique_integer([:positive])}",
      password: @password,
      status: 1
    })
    |> Repo.insert!()
  end

  defp create_job do
    Repo.insert!(
      SysJob.changeset(%SysJob{}, %{
        job_code: "job-latest-#{System.unique_integer([:positive])}",
        job_name: "HTTP 最近运行状态",
        job_group: "integration",
        invoke_target: "demoJobTask.printHeartbeat()",
        cron_expression: "*/5 * * * * *",
        concurrent: 0,
        status: 1
      })
    )
  end

  defp find_job(rows, job_id),
    do: Enum.find(rows, &(&1["id"] == job_id))

  defp authorized(conn, token),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
end
