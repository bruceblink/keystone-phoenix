defmodule KeystonePhoenixWeb.ContractMatrixTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @tag :integration
  test "health endpoints expose liveness and dependency readiness", %{conn: conn} do
    assert %{"success" => true, "data" => "is alive"} =
             conn |> get("/api/v1/health") |> json_response(200)

    assert %{
             "success" => true,
             "data" => %{
               "status" => "READY",
               "database" => "UP",
               "cache" => "UP",
               "storage" => "UP"
             }
           } = conn |> get("/api/v1/health/ready") |> json_response(200)
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
  test "clean break removes previous root authentication and health paths", %{} do
    assert get(build_conn(), "/login").status == 404
    assert get(build_conn(), "/system/users").status == 404
    assert get(build_conn(), "/health").status == 404
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
             "validation_failed"

    assert get_in(json_response(get(authorized.(), "/api/v1/jobs/abc"), 404), [
             "error",
             "code"
           ]) ==
             "validation_failed"

    assert get_in(json_response(post(authorized.(), "/api/v1/file/upload", %{}), 422), [
             "error",
             "code"
           ]) ==
             "validation_failed"

    assert %{"success" => true} =
             json_response(get(authorized.(), "/api/v1/monitor/serverInfo"), 200)
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
