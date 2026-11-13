defmodule KeystonePhoenixWeb.ApiKeyContractTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  test "API Key management uses the versioned resource path", %{conn: conn} do
    response = post(conn, "/api/v1/api-keys", %{"name" => "worker", "scopes" => ["api-key:read"]})

    assert response.status == 401
    assert get_in(json_response(response, 401), ["error", "code"]) == "session_revoked"
  end

  test "unversioned API Key paths are unavailable" do
    assert post(build_conn(), "/api-keys", %{}).status == 404
    assert get(build_conn(), "/api/v1/api-keys").status == 401
  end

  test "API Key authenticates an allowed business resource", %{conn: conn} do
    user = create_user(["api-key:create", "user:read"])
    assert {:ok, issued} = ApiKey.issue(user.user_id, "worker", ["user:read"])

    response =
      conn
      |> Plug.Conn.put_req_header("authorization", "ApiKey #{issued.api_key}")
      |> get("/api/v1/system/users")

    assert response.status == 200
    assert json_response(response, 200)["success"] == true
  end

  test "API Key cannot enter human authentication or API Key management paths", %{conn: conn} do
    user = create_user(["api-key:create", "user:read"])
    assert {:ok, issued} = ApiKey.issue(user.user_id, "worker", ["user:read"])
    conn = Plug.Conn.put_req_header(conn, "authorization", "ApiKey #{issued.api_key}")

    for response <- [
          get(conn, "/api/v1/auth/me"),
          post(conn, "/api/v1/auth/login", %{}),
          post(conn, "/api/v1/api-keys", %{}),
          put(conn, "/api/v1/system/user/profile/password", %{})
        ] do
      assert response.status == 403
      assert get_in(json_response(response, 403), ["error", "code"]) == "permission_denied"
    end
  end

  defp create_user(permissions) do
    role_id = Identity.v7()

    %SysRole{}
    |> Ecto.Changeset.change(%{
      role_id: role_id,
      role_name: "API Key HTTP role",
      role_key: "api_key_http_#{System.unique_integer([:positive])}",
      role_sort: 1,
      data_scope: "ALL",
      status: 1,
      deleted: false
    })
    |> Repo.insert!()

    Enum.each(permissions, fn permission ->
      entry = Repo.get_by!(SysPermission, permission: permission)
      Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: entry.permission_id})
    end)

    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role_id,
      username: "api_key_http_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end
end
