defmodule KeystonePhoenix.PermissionTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Permission
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}

  test "checks exact role menu permissions and admin bypass" do
    role = insert_role(%{role_key: unique("permission_role")})

    menu =
      %SysMenu{}
      |> SysMenu.changeset(%{
        menu_name: "用户列表",
        menu_type: 0,
        parent_id: 0,
        permission: "system:user:list",
        status: 1
      })
      |> Repo.insert!()

    Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: menu.menu_id})
    user = %{user_id: 10, role_id: role.role_id, is_admin: false}

    assert Permission.allowed?(user, "system:user:list")
    refute Permission.allowed?(user, "system:user:remove")
    assert Permission.allowed?(%{is_admin: true}, "anything")
  end

  test "enforces custom and department-tree data scopes" do
    parent = insert_dept(100, 0, "0")
    child = insert_dept(101, parent.dept_id, "0,100")
    other = insert_dept(102, 0, "0")
    role = insert_role(%{data_scope: 4, role_key: unique("tree_role")})
    user = %{user_id: 20, role_id: role.role_id, dept_id: parent.dept_id, is_admin: false}

    assert Permission.data_scope_allowed?(user, :dept, child.dept_id)
    refute Permission.data_scope_allowed?(user, :dept, other.dept_id)

    {:ok, custom_role} =
      role
      |> SysRole.changeset(%{data_scope: 2, dept_id_set: Integer.to_string(other.dept_id)})
      |> Repo.update()

    custom_user = %{user | role_id: custom_role.role_id}
    assert Permission.data_scope_allowed?(custom_user, :dept, other.dept_id)
    refute Permission.data_scope_allowed?(custom_user, :dept, child.dept_id)
    refute Permission.data_scope_allowed?(custom_user, :dept, nil)
  end

  test "accepts comma separated menu IDs from LiveView forms" do
    role = insert_role(%{role_key: unique("form_role")})

    menu =
      %SysMenu{}
      |> SysMenu.changeset(%{
        menu_name: "角色菜单",
        menu_type: 0,
        parent_id: 0,
        permission: "system:role:list",
        status: 1
      })
      |> Repo.insert!()

    assert {:ok, _updated} =
             KeystonePhoenix.Role.update_role(role.role_id, %{
               "roleName" => role.role_name,
               "roleKey" => role.role_key,
               "roleSort" => role.role_sort,
               "dataScope" => role.data_scope,
               "status" => role.status,
               "menuIds" => Integer.to_string(menu.menu_id)
             })

    assert Role.menu_ids_for_role(role.role_id) == [menu.menu_id]
  end

  defp insert_role(attrs) do
    attrs =
      Map.merge(
        %{
          role_name: "权限角色",
          role_key: unique("role"),
          role_sort: 1,
          data_scope: 1,
          dept_id_set: "",
          status: 1
        },
        attrs
      )

    %SysRole{}
    |> SysRole.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_dept(id, parent_id, ancestors) do
    %SysDept{dept_id: id}
    |> SysDept.changeset(%{
      parent_id: parent_id,
      ancestors: ancestors,
      dept_name: "部门 #{id}",
      status: 1
    })
    |> Repo.insert!()
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
