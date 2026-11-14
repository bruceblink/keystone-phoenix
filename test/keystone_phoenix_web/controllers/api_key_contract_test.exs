defmodule KeystonePhoenixWeb.ApiKeyContractTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
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
          get(conn, "/api/v1/auth/oidc/authorize"),
          post(conn, "/api/v1/auth/login", %{}),
          post(conn, "/api/v1/api-keys", %{}),
          put(conn, "/api/v1/system/user/profile/password", %{})
        ] do
      assert response.status == 403
      assert get_in(json_response(response, 403), ["error", "code"]) == "permission_denied"
    end
  end

  @tag :integration
  test "human session completes API Key create, list, rotate and revoke lifecycle", %{conn: conn} do
    # 使用真实 HTTP 管理入口验证凭据明文只在签发和轮换响应中返回。
    user = create_user(["api-key:create", "api-key:read", "api-key:rotate", "api-key:revoke"])
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    authorized_conn = put_req_header(conn, "authorization", "Bearer #{tokens.token}")

    create_response =
      post(authorized_conn, "/api/v1/api-keys", %{
        "name" => "http worker",
        "scopes" => ["api-key:read"]
      })

    assert %{"success" => true, "data" => %{"id" => key_id, "apiKey" => api_key}} =
             json_response(create_response, 201)

    assert String.starts_with?(api_key, "ks_live_")

    list_response = get(authorized_conn, "/api/v1/api-keys")

    assert %{"success" => true, "data" => [%{"id" => ^key_id} = metadata]} =
             json_response(list_response, 200)

    refute Map.has_key?(metadata, "apiKey")

    rotate_response = post(authorized_conn, "/api/v1/api-keys/#{key_id}/rotate", %{})

    assert %{"success" => true, "data" => %{"id" => replacement_id, "apiKey" => replacement_key}} =
             json_response(rotate_response, 200)

    assert replacement_id != key_id
    assert String.starts_with?(replacement_key, "ks_live_")

    assert %{"success" => true, "data" => %{"revoked" => true}} =
             json_response(delete(authorized_conn, "/api/v1/api-keys/#{replacement_id}"), 200)

    final_metadata =
      authorized_conn
      |> get("/api/v1/api-keys")
      |> json_response(200)
      |> get_in(["data"])

    assert Enum.any?(final_metadata, &(&1["id"] == replacement_id and is_binary(&1["revokedAt"])))
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
