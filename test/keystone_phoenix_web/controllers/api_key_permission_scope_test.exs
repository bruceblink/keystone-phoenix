defmodule KeystonePhoenixWeb.ApiKeyPermissionScopeTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Authz.Principal
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Permission
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}

  test "API Key permission:manage does not replace the owner's data scope", %{conn: conn} do
    role = create_role(~w(api-key:create config:read permission:manage user:read), "SELF")
    actor = create_user(role, "scope_actor")
    other = create_user(role, "scope_other")

    assert {:ok, users_key} =
             ApiKey.issue(actor.user_id, "users scope", ["user:read", "permission:manage"])

    users_response =
      conn
      |> api_key(users_key.api_key)
      |> get("/api/v1/users")
      |> json_response(200)

    assert users_response["data"]["total"] == 1
    assert [%{"id" => actor_id}] = users_response["data"]["items"]
    assert actor_id == actor.user_id

    detail_response =
      build_conn()
      |> api_key(users_key.api_key)
      |> get("/api/v1/users/#{other.user_id}")

    assert detail_response.status == 403
    assert get_in(json_response(detail_response, 403), ["error", "code"]) == "data_scope_denied"

    assert {:ok, configs_key} =
             ApiKey.issue(actor.user_id, "config scope", ["config:read", "permission:manage"])

    config_response =
      build_conn()
      |> api_key(configs_key.api_key)
      |> get("/api/v1/configs")

    assert config_response.status == 403
    assert get_in(json_response(config_response, 403), ["error", "code"]) == "data_scope_denied"

    assert {:ok, manage_only_key} =
             ApiKey.issue(actor.user_id, "manage only", ["permission:manage"])

    permission_response =
      build_conn()
      |> api_key(manage_only_key.api_key)
      |> get("/api/v1/users")

    assert permission_response.status == 403

    assert get_in(json_response(permission_response, 403), ["error", "code"]) ==
             "permission_denied"

    {:ok, human_tokens} = Auth.login_plaintext(actor.username, "Strong!123")

    human_users_response =
      build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{human_tokens.token}")
      |> get("/api/v1/users")
      |> json_response(200)

    human_user_ids = Enum.map(human_users_response["data"]["items"], & &1["id"])
    # permission:manage 只管理权限元数据；SELF 角色仍只能查看本人数据。
    assert human_users_response["data"]["total"] == 1
    assert human_user_ids == [actor.user_id]
    refute other.user_id in human_user_ids

    human_config_response =
      build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{human_tokens.token}")
      |> get("/api/v1/configs")

    assert human_config_response.status == 403

    assert get_in(json_response(human_config_response, 403), ["error", "code"]) ==
             "data_scope_denied"

    # API Key 按所属角色的新范围恢复访问，不会因凭据类型被一律拒绝。
    Repo.update!(Ecto.Changeset.change(role, data_scope: "ALL"))

    global_users_response =
      build_conn()
      |> api_key(users_key.api_key)
      |> get("/api/v1/users")
      |> json_response(200)

    assert global_users_response["data"]["total"] >= 2
    global_user_ids = Enum.map(global_users_response["data"]["items"], & &1["id"])
    assert actor.user_id in global_user_ids
    assert other.user_id in global_user_ids

    global_config_response =
      build_conn()
      |> api_key(configs_key.api_key)
      |> get("/api/v1/configs")

    assert global_config_response.status == 200
  end

  test "permission:manage stays an administrator capability for human principals" do
    human = %{credential_type: "PASSWORD", permissions: ["permission:manage"]}
    api_key = %{credential_type: "API_KEY", permissions: ["permission:manage"]}

    assert Principal.admin?(human)
    assert Permission.admin?(human)
    assert Authz.admin?(human)
    assert Authz.menu_metadata_allowed?(human, %{"permission" => "user:read"})
    assert Authz.role_metadata_allowed?(human, %{"permissions" => ["user:read"]})

    refute Principal.admin?(api_key)
    refute Permission.admin?(api_key)
    refute Authz.admin?(api_key)
    refute Authz.menu_metadata_allowed?(api_key, %{"permission" => "user:read"})
    refute Authz.role_metadata_allowed?(api_key, %{"permissions" => ["user:read"]})
  end

  defp create_role(permission_codes, data_scope) do
    role =
      %SysRole{}
      |> Ecto.Changeset.change(%{
        role_id: Identity.v7(),
        role_name: "API Key 范围测试",
        role_key: "api_key_scope_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: data_scope,
        status: 1,
        deleted: false
      })
      |> Repo.insert!()

    Enum.each(permission_codes, fn permission ->
      entry = Repo.get_by!(SysPermission, permission: permission)
      Repo.insert!(%SysRolePermission{role_id: role.role_id, permission_id: entry.permission_id})
    end)

    role
  end

  # API Key 从所属账号读取当前角色权限和数据范围。
  defp create_user(role, suffix) do
    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role.role_id,
      username: "api_key_scope_#{suffix}_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end

  defp api_key(conn, value),
    do: Plug.Conn.put_req_header(conn, "authorization", "ApiKey #{value}")
end
