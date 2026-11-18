defmodule KeystonePhoenixWeb.ApiKeyContractTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Auth.ApiKey.Key
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.User.SysUserRole

  test "API Key management uses the versioned resource path", %{conn: conn} do
    response = post(conn, "/api/v1/api-keys", %{"name" => "worker", "scopes" => ["api-key:read"]})

    assert response.status == 401
    assert get_in(json_response(response, 401), ["error", "code"]) == "session_revoked"
  end

  test "unversioned API Key paths are unavailable" do
    assert post(build_conn(), "/api-keys", %{}).status == 404
    assert get(build_conn(), "/api/v1/api-keys").status == 401
  end

  @tag :integration
  test "API Key name limit follows database Unicode code points" do
    # 表情占一个码点，组合字符由两个码点组成；分别验证数据库边界和错误码。
    user = create_user(["api-key:create"])
    token = step_up_token(user)

    for name <- [String.duplicate("😀", 128), String.duplicate("e\u0301", 64)] do
      response =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/api-keys", %{"name" => name, "scopes" => ["api-key:create"]})

      assert get_in(json_response(response, 201), ["data", "name"]) == name
    end

    for name <- [String.duplicate("😀", 129), String.duplicate("e\u0301", 64) <> "e"] do
      response =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/api-keys", %{"name" => name, "scopes" => ["api-key:create"]})

      assert get_in(json_response(response, 422), ["error", "code"]) == "api_key_name_invalid"
    end
  end

  @tag :integration
  test "API Key issue validation returns distinct business codes and keeps HTTP 422" do
    user = create_user(["api-key:create"])
    token = step_up_token(user)
    expiry = DateTime.add(DateTime.utc_now(), 91 * 24 * 60 * 60, :second)

    invalid_requests = [
      {%{"scopes" => ["api-key:create"]}, "api_key_name_invalid", "API Key 名称必须为 1 到 128 个字符。"},
      {%{"name" => String.duplicate("a", 129), "scopes" => ["api-key:create"]},
       "api_key_name_invalid", "API Key 名称必须为 1 到 128 个字符。"},
      {%{"name" => "worker", "scopes" => ["api-key:create"], "expiresAt" => "invalid"},
       "api_key_expiry_invalid", "API Key 到期时间格式无效，请重新选择时间。"},
      {%{
         "name" => "long-lived worker",
         "scopes" => ["api-key:create"],
         "expiresAt" => DateTime.to_iso8601(expiry)
       }, "api_key_expiry_out_of_range", "API Key 到期时间必须晚于当前时间且不超过 90 天。"}
    ]

    for {params, expected_code, expected_message} <- invalid_requests do
      response =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/api-keys", params)

      body = json_response(response, 422)
      assert response.status == 422
      assert get_in(body, ["error", "code"]) == expected_code
      assert body["message"] == expected_message
    end
  end

  test "API Key authenticates an allowed business resource", %{conn: conn} do
    user = create_user(["api-key:create", "user:read"])
    assert {:ok, issued} = ApiKey.issue(user.user_id, "worker", ["user:read"])

    response =
      conn
      |> Plug.Conn.put_req_header("authorization", "ApiKey #{issued.api_key}")
      |> get("/api/v1/users")

    assert response.status == 200
    assert json_response(response, 200)["success"] == true
  end

  @tag :integration
  test "API Key HTTP permissions shrink when a role membership is removed", %{conn: conn} do
    primary = create_role(["api-key:create", "api-key:read"])
    secondary = create_role(["user:read"])
    user = create_multi_role_user(primary, secondary)

    assert {:ok, issued} =
             ApiKey.issue(user.user_id, "http multi-role worker", ["api-key:read", "user:read"])

    authorized = fn ->
      Plug.Conn.put_req_header(conn, "authorization", "ApiKey #{issued.api_key}")
    end

    assert get(authorized.(), "/api/v1/users").status == 200

    Repo.delete_all(
      from membership in SysUserRole,
        where: membership.user_id == ^user.user_id and membership.role_id == ^secondary.role_id
    )

    denied = get(authorized.(), "/api/v1/users")
    assert denied.status == 403
    assert get_in(json_response(denied, 403), ["error", "code"]) == "permission_denied"

    Repo.delete_all(from membership in SysUserRole, where: membership.user_id == ^user.user_id)
    Repo.update!(Ecto.Changeset.change(user, role_id: nil))

    invalid = get(authorized.(), "/api/v1/users")
    assert invalid.status == 401
    assert get_in(json_response(invalid, 401), ["error", "code"]) == "invalid_credential"
  end

  test "API Key cannot enter human authentication or API Key management paths", %{conn: conn} do
    user = create_user(["api-key:create", "user:read"])
    assert {:ok, issued} = ApiKey.issue(user.user_id, "worker", ["user:read"])
    conn = Plug.Conn.put_req_header(conn, "authorization", "ApiKey #{issued.api_key}")

    for response <- [
          get(conn, "/api/v1/profile"),
          get(conn, "/api/v1/auth/oidc/authorize"),
          post(conn, "/api/v1/auth/login", %{}),
          post(conn, "/api/v1/api-keys", %{}),
          put(conn, "/api/v1/profile/password", %{})
        ] do
      assert response.status == 403
      assert get_in(json_response(response, 403), ["error", "code"]) == "permission_denied"
    end
  end

  @tag :integration
  test "human session completes API Key create, list, rotate and revoke lifecycle", %{conn: conn} do
    # 使用真实 HTTP 管理入口验证凭据明文只在签发和轮换响应中返回。
    user = create_user(["api-key:create", "api-key:read", "api-key:rotate", "api-key:revoke"])
    token = step_up_token(user)
    authorized_conn = put_req_header(conn, "authorization", "Bearer #{token}")

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

    assert %{
             "success" => true,
             "data" => %{
               "items" => [%{"id" => ^key_id}],
               "page" => 1,
               "size" => 1,
               "total" => 1
             }
           } =
             authorized_conn
             |> get("/api/v1/api-keys?page=1&size=1&keyword=http%20worker&status=active")
             |> json_response(200)

    rotate_response = post(authorized_conn, "/api/v1/api-keys/#{key_id}/rotate", %{})

    assert %{"success" => true, "data" => %{"id" => replacement_id, "apiKey" => replacement_key}} =
             json_response(rotate_response, 200)

    assert replacement_id != key_id
    assert String.starts_with?(replacement_key, "ks_live_")

    assert %{"success" => true, "data" => %{"revoked" => true}} =
             json_response(delete(authorized_conn, "/api/v1/api-keys/#{replacement_id}"), 200)

    missing_id = Identity.v7()

    missing_rotate = post(authorized_conn, "/api/v1/api-keys/#{missing_id}/rotate", %{})
    assert missing_rotate.status == 404
    assert get_in(json_response(missing_rotate, 404), ["error", "code"]) == "resource_not_found"

    missing_revoke = delete(authorized_conn, "/api/v1/api-keys/#{missing_id}")
    assert missing_revoke.status == 404
    assert get_in(json_response(missing_revoke, 404), ["error", "code"]) == "resource_not_found"

    revoked_rotate = post(authorized_conn, "/api/v1/api-keys/#{replacement_id}/rotate", %{})
    assert revoked_rotate.status == 409
    assert get_in(json_response(revoked_rotate, 409), ["error", "code"]) == "resource_conflict"

    final_metadata =
      authorized_conn
      |> get("/api/v1/api-keys")
      |> json_response(200)
      |> get_in(["data"])

    assert Enum.any?(final_metadata, &(&1["id"] == replacement_id and is_binary(&1["revokedAt"])))
  end

  @tag :integration
  test "expired API Key is excluded from active results and cannot be rotated", %{conn: conn} do
    # 先通过接口签发，再将本条记录设为过期，验证筛选及拒绝轮换后的持久状态。
    user = create_user(["api-key:create", "api-key:read", "api-key:rotate"])
    token = step_up_token(user)
    authorized_conn = put_req_header(conn, "authorization", "Bearer #{token}")
    assert {:ok, issued} = ApiKey.issue(user.user_id, "expired worker", ["api-key:read"])

    Repo.update_all(from(key in Key, where: key.id == ^issued.id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -60, :second)]
    )

    active =
      authorized_conn
      |> get("/api/v1/api-keys?page=1&size=20&status=active")
      |> json_response(200)

    assert active["data"]["total"] == 0

    all = authorized_conn |> get("/api/v1/api-keys?page=1&size=20") |> json_response(200)
    assert Enum.any?(all["data"]["items"], &(&1["id"] == issued.id))

    response = post(authorized_conn, "/api/v1/api-keys/#{issued.id}/rotate", %{})
    assert get_in(json_response(response, 409), ["error", "code"]) == "api_key_expired"
    assert Repo.get!(Key, issued.id).revoked_at == nil
    assert Repo.aggregate(from(key in Key, where: key.user_id == ^user.user_id), :count, :id) == 1
  end

  defp create_user(permissions) do
    role = create_role(permissions)
    create_user_for_role(role)
  end

  defp create_role(permissions) do
    role_id = Identity.v7()

    role =
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

    role
  end

  defp create_multi_role_user(primary, secondary) do
    user = create_user_for_role(primary)
    Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: primary.role_id})
    Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: secondary.role_id})
    user
  end

  defp create_user_for_role(role) do
    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role.role_id,
      username: "api_key_http_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end
end
