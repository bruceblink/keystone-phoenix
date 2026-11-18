defmodule KeystonePhoenixWeb.AuthCapabilitiesControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.{PermissionVersion, Permissions}
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.{RoleMembership, SysUser}

  @resource_names ~w(
    user department role post menu config dictionary notice job audit session api-key profile
  )

  @tag :integration
  # 多角色能力取启用角色权限并集，禁用角色不得增加权限或数据范围。
  test "returns the active multi-role permission union and resource scopes" do
    self_role = create_role("SELF", ["user:read", "notice:read"])
    owner_role = create_role("OWNER", ["api-key:read", "job:read"])
    disabled_role = create_role("ALL", ["role:read"], 0)
    user = create_user([self_role.role_id, owner_role.role_id, disabled_role.role_id])
    response = capabilities(login(user))

    assert %{
             "success" => true,
             "data" => %{
               "permissions" => permissions,
               "resources" => resources
             }
           } = json_response(response, 200)

    assert permissions == ["api-key:read", "job:read", "notice:read", "user:read"]
    assert MapSet.new(Map.keys(resources)) == MapSet.new(@resource_names)
    assert resources["user"]
    assert resources["department"]
    assert resources["profile"]
    assert resources["api-key"]
    assert resources["notice"]
    assert resources["job"]

    for resource <- ~w(role post menu config dictionary audit session) do
      refute resources[resource]
    end

    assert_no_store(response)
  end

  @tag :integration
  # 数据范围布尔值与各列表入口一致；查询过滤型列表即使没有角色也可返回空结果。
  test "reports SELF, OWNER, ALL, TENANT and empty role scopes" do
    for {scope, self, owner, global} <- [
          {"SELF", true, false, false},
          {"OWNER", false, true, false},
          {"ALL", true, true, true},
          {"TENANT", true, true, true}
        ] do
      role = create_role(scope, [])
      user = create_user([role.role_id])
      response = capabilities(login(user))
      resources = json_response(response, 200)["data"]["resources"]

      assert resources["user"]
      assert resources["department"]
      assert resources["profile"] == self
      assert resources["api-key"] == self
      assert resources["notice"] == owner
      assert resources["job"] == owner

      for resource <- ~w(role post menu config dictionary audit session) do
        assert resources[resource] == global
      end
    end

    user = create_user([])
    response = capabilities(login(user))
    data = json_response(response, 200)["data"]

    assert data["permissions"] == []
    assert data["resources"]["user"]
    assert data["resources"]["department"]

    for resource <- Enum.reject(@resource_names, &(&1 in ["user", "department"])) do
      refute data["resources"][resource]
    end
  end

  @tag :integration
  # 角色权限变化会撤销旧会话；新会话必须读取刚保存的权限集合。
  test "recomputes permission data after an authorization change" do
    role = create_role("SELF", ["user:read"])
    user = create_user([role.role_id])
    old_token = login(user)

    assert json_response(capabilities(old_token), 200)["data"]["permissions"] == ["user:read"]

    assert :ok = Permissions.replace(role.role_id, ["user:read", "api-key:read"])
    assert :ok = PermissionVersion.bump_for_role(role.role_id)

    revoked = capabilities(old_token)
    assert revoked.status == 401
    assert get_in(json_response(revoked, 401), ["error", "code"]) == "session_revoked"
    assert_no_store(revoked)

    fresh = capabilities(login(user))
    assert json_response(fresh, 200)["data"]["permissions"] == ["api-key:read", "user:read"]
  end

  @tag :integration
  # 能力仅用于人类会话；匿名和有效 API Key 请求保留原有错误状态。
  test "rejects anonymous and API Key requests without caching" do
    anonymous = get(build_conn(), "/api/v1/auth/me/capabilities")
    assert anonymous.status == 401
    assert get_in(json_response(anonymous, 401), ["error", "code"]) == "session_revoked"
    assert_no_store(anonymous)

    role = create_role("ALL", ["api-key:read"])
    user = create_user([role.role_id])
    assert {:ok, issued} = ApiKey.issue(user.user_id, "capabilities test", ["api-key:read"])

    api_key =
      build_conn()
      |> Plug.Conn.put_req_header("authorization", "ApiKey #{issued.api_key}")
      |> get("/api/v1/auth/me/capabilities")

    assert api_key.status == 403
    assert get_in(json_response(api_key, 403), ["error", "code"]) == "permission_denied"
    assert_no_store(api_key)
  end

  @tag :integration
  # 授权表不可读时必须返回 503，不能把故障伪装成无权限的成功响应。
  test "returns unavailable when authorization storage cannot be read" do
    role = create_role("ALL", ["user:read"])
    user = create_user([role.role_id])
    token = login(user)

    Repo.query!("ALTER TABLE sys_role RENAME TO sys_role_caps_unavailable")

    response =
      try do
        capabilities(token)
      after
        Repo.query!("ALTER TABLE sys_role_caps_unavailable RENAME TO sys_role")
      end

    assert response.status == 503
    assert get_in(json_response(response, 503), ["error", "code"]) == "authorization_unavailable"
    assert_no_store(response)
  end

  defp create_role(scope, permission_names, status \\ 1) do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: "能力验收 #{scope}",
        role_key: "capabilities_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: scope,
        status: status
      })
      |> Repo.insert!()

    Enum.each(permission_names, fn permission ->
      entry = Repo.get_by!(SysPermission, permission: permission)

      Repo.insert!(%SysRolePermission{
        role_id: role.role_id,
        permission_id: entry.permission_id
      })
    end)

    role
  end

  defp create_user(role_ids) do
    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        role_id: List.first(role_ids),
        username: "capabilities_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        status: 1
      })
      |> Repo.insert!()

    RoleMembership.replace_user_roles([user.user_id], role_ids)
    user
  end

  defp login(user) do
    assert {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123", true)
    tokens.token
  end

  defp capabilities(token) do
    build_conn()
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    |> get("/api/v1/auth/me/capabilities")
  end

  defp assert_no_store(conn),
    do: assert(Plug.Conn.get_resp_header(conn, "cache-control") == ["no-store"])
end
