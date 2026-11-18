defmodule KeystonePhoenixWeb.SelfResourceScopeHttpTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @permissions ["user:read", "api-key:read"]

  @tag :integration
  # 通过真实 HTTP 和 PostgreSQL 检查本人资料与 API Key 的有效数据范围。
  test "self resources accept SELF, ALL and TENANT scopes" do
    for scope <- ["SELF", "ALL", "TENANT"] do
      user = create_user(scope)
      {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123", true)

      profile = get(authorized(build_conn(), tokens.token), "/api/v1/profile")
      assert profile.status == 200, "profile rejected #{scope}"
      assert json_response(profile, 200)["success"]

      api_keys = get(authorized(build_conn(), tokens.token), "/api/v1/api-keys")
      assert api_keys.status == 200, "API Key list rejected #{scope}"
      assert json_response(api_keys, 200)["data"] == []
    end
  end

  @tag :integration
  # 只有 OWNER 或空范围时，入口保持 403，不改变已有 HTTP 错误状态。
  test "self resources reject OWNER-only and users without an assigned role" do
    owner = create_user("OWNER")
    {:ok, owner_tokens} = Auth.login_plaintext(owner.username, "Strong!123", true)

    for path <- ["/api/v1/profile", "/api/v1/api-keys"] do
      response = get(authorized(build_conn(), owner_tokens.token), path)
      assert response.status == 403, "#{path} accepted OWNER-only scope"
      assert get_in(json_response(response, 403), ["error", "code"]) == "data_scope_denied"
    end

    empty_scope = create_unassigned_user()
    {:ok, empty_tokens} = Auth.login_plaintext(empty_scope.username, "Strong!123", true)
    refute Authz.resource_scope_allowed?(empty_scope, :profile)
    refute Authz.resource_scope_allowed?(empty_scope, :api_key)

    for {path, expected_code} <- [
          {"/api/v1/profile", "permission_denied"},
          {"/api/v1/api-keys", "data_scope_denied"}
        ] do
      response = get(authorized(build_conn(), empty_tokens.token), path)
      assert response.status == 403, "#{path} accepted an empty role scope"
      assert get_in(json_response(response, 403), ["error", "code"]) == expected_code
    end
  end

  defp create_user(scope) do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: "本人资源范围 #{scope}",
        role_key: "self_scope_#{String.downcase(scope)}_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: scope,
        status: 1
      })
      |> Repo.insert!()

    Enum.each(@permissions, fn permission ->
      entry = Repo.get_by!(SysPermission, permission: permission)

      Repo.insert!(%SysRolePermission{
        role_id: role.role_id,
        permission_id: entry.permission_id
      })
    end)

    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        role_id: role.role_id,
        username: "self_scope_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        status: 1
      })
      |> Repo.insert!()

    user
  end

  defp create_unassigned_user do
    %SysUser{}
    |> SysUser.create_changeset(%{
      username: "self_scope_empty_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end

  defp authorized(conn, token),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
end
