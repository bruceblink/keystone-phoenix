defmodule KeystonePhoenixWeb.UserDepartmentUpdateContractTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @password "Strong!123"

  @tag :integration
  test "department updates follow Native clearDept precedence", %{conn: conn} do
    dept = insert_department()
    role = insert_role_with_user_permissions()
    user = insert_user(role.role_id, dept.dept_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, @password)
    path = "/api/v1/users/#{user.user_id}"

    # 缺失 deptId 或显式 null 只有在 clearDept=true 时才会清除部门。
    for body <- [
          %{"displayName" => "部门保留"},
          %{"displayName" => "部门保留", "deptId" => nil},
          %{"displayName" => "部门保留", "deptId" => nil, "clearDept" => false}
        ] do
      response = put(authorized(conn, tokens.token), path, body)
      assert json_response(response, 200)["data"]["deptId"] == dept.dept_id
      assert Repo.get!(SysUser, user.user_id).dept_id == dept.dept_id
    end

    # Native 兼容规则中，具体部门编号优先于 clearDept=true。
    response =
      put(
        authorized(conn, tokens.token),
        path,
        %{"displayName" => "部门赋值优先", "deptId" => dept.dept_id, "clearDept" => true}
      )

    assert json_response(response, 200)["data"]["deptId"] == dept.dept_id

    for body <- [
          %{"displayName" => "标记清除", "clearDept" => true},
          %{"displayName" => "空值清除", "deptId" => nil, "clearDept" => true}
        ] do
      response = put(authorized(conn, tokens.token), path, body)
      assert json_response(response, 200)["data"]["deptId"] == nil
      assert Repo.get!(SysUser, user.user_id).dept_id == nil

      reset = put(authorized(conn, tokens.token), path, %{"deptId" => dept.dept_id})
      assert json_response(reset, 200)["data"]["deptId"] == dept.dept_id
    end

    # 空字符串和无效 UUID 不得意外清空部门；API 返回参数错误并保留数据。
    for invalid_id <- ["", "not-a-uuid"] do
      response =
        put(authorized(conn, tokens.token), path, %{
          "displayName" => "拒绝无效部门",
          "deptId" => invalid_id,
          "clearDept" => true
        })

      assert get_in(json_response(response, 422), ["error", "code"]) == "validation_failed"
      assert Repo.get!(SysUser, user.user_id).dept_id == dept.dept_id
    end
  end

  defp authorized(conn, token),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")

  defp insert_department do
    %SysDept{dept_id: Identity.v7()}
    |> SysDept.changeset(%{
      dept_code: "dept_#{System.unique_integer([:positive])}",
      dept_name: "部门更新测试",
      ancestors: "",
      status: 1
    })
    |> Repo.insert!()
  end

  defp insert_role_with_user_permissions do
    role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: "部门更新测试角色",
        role_key: "dept_update_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: "ALL",
        status: 1
      })
      |> Repo.insert!()

    for permission <- ["user:read", "user:update"] do
      entry =
        Repo.get_by(SysPermission, permission: permission) ||
          Repo.insert!(%SysPermission{
            permission_id: Identity.permission_id(permission),
            permission: permission,
            resource: "user",
            domain: "default",
            action: List.last(String.split(permission, ":")),
            status: 1,
            deprecated: false
          })

      Repo.insert!(%SysRolePermission{role_id: role.role_id, permission_id: entry.permission_id})
    end

    PolicyCache.invalidate()
    role
  end

  defp insert_user(role_id, dept_id) do
    %SysUser{user_id: Identity.v7()}
    |> SysUser.create_changeset(%{
      username: "dept_update_#{System.unique_integer([:positive])}",
      password: @password,
      nickname: "部门更新用户",
      role_id: role_id,
      dept_id: dept_id,
      status: 1
    })
    |> Repo.insert!()
  end
end
