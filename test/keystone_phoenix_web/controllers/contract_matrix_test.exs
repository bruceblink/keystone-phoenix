defmodule KeystonePhoenixWeb.ContractMatrixTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Job.{Lock, SysJob}
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @tag :integration
  test "health endpoint exposes liveness", %{conn: conn} do
    assert %{"success" => true, "data" => "is alive"} =
             conn |> get("/api/v1/health") |> json_response(200)
  end

  @tag :integration
  test "protected controller endpoints reject missing bearer tokens", %{} do
    for {method, path} <- [
          {:post, "/api/v1/file/upload"},
          {:get, "/api/v1/file/download?fileName=missing.txt"},
          {:get, "/api/v1/monitor/cacheInfo"},
          {:get, "/api/v1/monitor/serverInfo"},
          {:get, "/api/v1/configs/1"},
          {:get, "/api/v1/jobs/1"},
          {:get, "/api/v1/login-logs"}
        ] do
      response =
        case method do
          :get -> get(build_conn(), path)
          :post -> post(build_conn(), path, %{})
        end

      assert response.status == 401, "expected #{path} to require authentication"
      assert get_in(json_response(response, 401), ["error", "code"]) == "session_revoked"
    end
  end

  @tag :integration
  test "LiveView authentication path is available while old HTTP paths stay removed", %{} do
    assert html_response(get(build_conn(), "/login"), 200) =~ "login-form"
    assert get(build_conn(), "/system/users").status == 404
    assert get(build_conn(), "/health").status == 404

    assert delete(build_conn(), "/api/v1/login-logs?ids=00000000-0000-0000-0000-000000000000").status ==
             404

    assert delete(build_conn(), "/api/v1/operation-logs?ids=00000000-0000-0000-0000-000000000000").status ==
             404
  end

  @tag :integration
  test "authenticated controller paths return stable invalid and missing resource errors", %{} do
    user = insert_admin()
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    authorized = fn -> put_req_header(build_conn(), "authorization", "Bearer #{tokens.token}") end

    assert get_in(json_response(get(authorized.(), "/api/v1/configs/abc"), 404), [
             "error",
             "code"
           ]) ==
             "resource_not_found"

    assert get_in(json_response(get(authorized.(), "/api/v1/jobs/abc"), 404), [
             "error",
             "code"
           ]) ==
             "resource_not_found"

    assert get_in(json_response(post(authorized.(), "/api/v1/file/upload", %{}), 422), [
             "error",
             "code"
           ]) ==
             "validation_failed"

    assert %{"success" => true} =
             json_response(get(authorized.(), "/api/v1/monitor/serverInfo"), 200)
  end

  @tag :integration
  test "deprecated batch deletion query aliases are rejected", %{} do
    user = insert_admin()
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    authorized = fn -> put_req_header(build_conn(), "authorization", "Bearer #{tokens.token}") end
    id = Identity.v7()

    for path <- [
          "/api/v1/users?user_ids=#{id}",
          "/api/v1/roles?role_ids=#{id}",
          "/api/v1/notices?ids=#{id}",
          "/api/v1/jobs?ids=#{id}"
        ] do
      response = delete(authorized.(), path)
      assert response.status == 422, "expected #{path} to reject its deprecated alias"
      assert get_in(json_response(response, 422), ["error", "code"]) == "validation_failed"
    end
  end

  @tag :integration
  test "a skipped concurrent trigger keeps the accepted-result contract", %{conn: conn} do
    user = insert_admin()
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

    job =
      %SysJob{}
      |> SysJob.changeset(%{
        job_code: "contract-trigger-#{System.unique_integer([:positive])}",
        job_name: "并发触发契约任务",
        job_group: "契约测试",
        invoke_target: "demoJobTask.printHeartbeat()",
        cron_expression: "0/30 * * * * ?",
        concurrent: 0,
        status: 1
      })
      |> Repo.insert!()

    assert :ok = Lock.acquire(job.job_id)

    try do
      response =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.token}")
        |> post("/api/v1/jobs/#{job.job_id}/trigger", %{})

      assert response.status == 200
      assert get_in(json_response(response, 200), ["data", "triggered"]) == true
    after
      assert :ok = Lock.release(job.job_id)
    end
  end

  defp insert_admin do
    admin_role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    %SysUser{}
    |> SysUser.create_changeset(%{
      username: "contract_admin_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      role_id: admin_role.role_id,
      status: 1
    })
    |> Repo.insert!()
  end
end
