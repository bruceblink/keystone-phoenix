defmodule KeystonePhoenixWeb.ContractMatrixTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @tag :integration
  test "health endpoints expose liveness and dependency readiness", %{conn: conn} do
    assert %{"success" => true, "data" => "is alive"} =
             conn |> get("/health") |> json_response(200)

    assert %{
             "success" => true,
             "data" => %{
               "status" => "READY",
               "database" => "UP",
               "cache" => "UP",
               "storage" => "UP"
             }
           } = conn |> get("/health/ready") |> json_response(200)
  end

  @tag :integration
  test "protected controller endpoints reject missing bearer tokens", %{} do
    for {method, path} <- [
          {:post, "/file/upload"},
          {:get, "/file/download?fileName=missing.txt"},
          {:get, "/monitor/cacheInfo"},
          {:get, "/monitor/serverInfo"},
          {:get, "/system/config/1"},
          {:get, "/system/jobs/1"},
          {:get, "/logs/loginLogs"}
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
  test "authenticated controller paths return stable invalid and missing resource errors", %{} do
    user = insert_admin()
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    authorized = fn -> put_req_header(build_conn(), "authorization", "Bearer #{tokens.token}") end

    assert get_in(json_response(get(authorized.(), "/system/config/abc"), 404), ["error", "code"]) ==
             "validation_failed"

    assert get_in(json_response(get(authorized.(), "/system/jobs/abc"), 404), ["error", "code"]) ==
             "validation_failed"

    assert get_in(json_response(post(authorized.(), "/file/upload", %{}), 422), ["error", "code"]) ==
             "validation_failed"

    assert %{"success" => true} = json_response(get(authorized.(), "/monitor/serverInfo"), 200)
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
