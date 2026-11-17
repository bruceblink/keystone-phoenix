defmodule KeystonePhoenixWeb.HumanAdminDataScopeTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @tag :integration
  test "permission manager follows SELF scope for user reads and target details" do
    role = create_role(~w(permission:manage user:read), "SELF")
    actor = create_user(role, "actor")
    other = create_user(role, "other")

    {:ok, tokens} = Auth.login_plaintext(actor.username, "Strong!123")

    users_response = get_bearer(tokens.token, "/api/v1/users")
    users_data = json_response(users_response, 200)["data"]

    assert %{"total" => 1, "items" => [%{"id" => actor_id}]} = users_data
    assert actor_id == actor.user_id

    other_response = get_bearer(tokens.token, "/api/v1/users/#{other.user_id}")
    assert other_response.status == 403
    assert get_in(json_response(other_response, 403), ["error", "code"]) == "data_scope_denied"

    manager = %{permissions: ["permission:manage"]}
    assert Authz.role_metadata_allowed?(manager, %{"permissions" => ["user:read"]})
    assert Authz.menu_metadata_allowed?(manager, %{"permission" => "user:read"})
  end

  @tag :integration
  test "global resources require ALL while ALL scope remains available" do
    role = create_role(~w(config:read permission:manage user:read), "SELF")
    actor = create_user(role, "global_scope")

    {:ok, self_tokens} = Auth.login_plaintext(actor.username, "Strong!123")
    config_response = get_bearer(self_tokens.token, "/api/v1/configs")
    assert config_response.status == 403
    assert get_in(json_response(config_response, 403), ["error", "code"]) == "data_scope_denied"

    # ALL 范围仍允许访问全局配置资源。
    Repo.update!(Ecto.Changeset.change(role, data_scope: "ALL"))

    all_users = json_response(get_bearer(self_tokens.token, "/api/v1/users"), 200)["data"]
    all_user_ids = Enum.map(all_users["items"], & &1["id"])
    assert actor.user_id in all_user_ids
    assert json_response(get_bearer(self_tokens.token, "/api/v1/configs"), 200)["success"]
  end

  @tag :integration
  test "permission:manage does not replace the exact route permission" do
    role = create_role(["permission:manage"], "ALL")
    actor = create_user(role, "manage_only")
    {:ok, tokens} = Auth.login_plaintext(actor.username, "Strong!123")

    response = get_bearer(tokens.token, "/api/v1/users")
    assert response.status == 403
    assert get_in(json_response(response, 403), ["error", "code"]) == "permission_denied"
  end

  @tag :integration
  test "missing bulk user ids return validation error without bypassing permissions or scope" do
    role = create_role(["user:delete"], "SELF")
    actor = create_user(role, "bulk_actor")
    other = create_user(role, "bulk_other")
    {:ok, tokens} = Auth.login_plaintext(actor.username, "Strong!123")

    # 缺少规范 ids 时由控制器返回参数错误，旧查询字段不能替代规范参数。
    missing = delete_bearer(tokens.token, "/api/v1/users?user_ids=#{other.user_id}")
    assert get_in(json_response(missing, 422), ["error", "code"]) == "validation_failed"

    # 真实目标仍受 SELF 数据范围限制。
    denied = delete_bearer(tokens.token, "/api/v1/users?ids=#{other.user_id}")
    assert get_in(json_response(denied, 403), ["error", "code"]) == "data_scope_denied"

    no_delete_role = create_role(["user:read"], "ALL")
    no_delete = create_user(no_delete_role, "bulk_no_permission")
    {:ok, no_delete_tokens} = Auth.login_plaintext(no_delete.username, "Strong!123")
    forbidden = delete_bearer(no_delete_tokens.token, "/api/v1/users?user_ids=#{other.user_id}")
    assert get_in(json_response(forbidden, 403), ["error", "code"]) == "permission_denied"
  end

  defp create_role(permission_codes, data_scope) do
    role =
      %SysRole{}
      |> Ecto.Changeset.change(%{
        role_id: Identity.v7(),
        role_name: "人类管理员数据范围测试",
        role_key: "human_scope_#{System.unique_integer([:positive])}",
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

  # 创建一个只属于测试角色的有效人类账号。
  defp create_user(role, suffix) do
    %SysUser{}
    |> SysUser.create_changeset(%{
      user_id: Identity.v7(),
      role_id: role.role_id,
      username: "human_scope_#{suffix}_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end

  # 每个请求创建新的连接，模拟独立的 Bearer HTTP 请求。
  defp get_bearer(token, path) do
    build_conn()
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    |> get(path)
  end

  defp delete_bearer(token, path) do
    build_conn()
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    |> delete(path)
  end
end
