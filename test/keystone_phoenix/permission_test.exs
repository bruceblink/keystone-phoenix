defmodule KeystonePhoenix.PermissionTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Permission
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}

  test "checks exact role menu permissions without an admin bypass" do
    role = insert_role(%{role_key: unique("permission_role")})

    menu =
      %SysMenu{}
      |> SysMenu.changeset(%{
        menu_name: "用户列表",
        menu_type: 0,
        parent_id: nil,
        permission: "user:read",
        status: 1
      })
      |> Repo.insert!()

    Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: menu.menu_id})
    insert_permission(role.role_id, "user:read")
    user = %{user_id: Identity.v7(), role_id: role.role_id}

    assert Permission.allowed?(user, "user:read")
    refute Permission.allowed?(user, "user:delete")
    refute Permission.allowed?(%{}, "user:update")
  end

  test "enforces custom and department-tree data scopes" do
    parent = insert_dept(100, nil, "")
    child = insert_dept(101, parent.dept_id, to_string(parent.dept_id))
    other = insert_dept(102, nil, "")
    role = insert_role(%{data_scope: 4, role_key: unique("tree_role")})
    user = %{user_id: Identity.v7(), role_id: role.role_id, dept_id: parent.dept_id}

    assert Permission.data_scope_allowed?(user, :dept, child.dept_id)
    refute Permission.data_scope_allowed?(user, :dept, other.dept_id)

    {:ok, custom_role} =
      role
      |> SysRole.changeset(%{data_scope: 2, dept_id_set: other.dept_id})
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
        parent_id: nil,
        permission: "role:read",
        status: 1
      })
      |> Repo.insert!()

    assert {:ok, _updated} =
             KeystonePhoenix.Role.update_role(
               role.role_id,
               %{
                 "roleName" => role.role_name,
                 "roleKey" => role.role_key,
                 "roleSort" => role.role_sort,
                 "dataScope" => role.data_scope,
                 "status" => role.status,
                 "menuIds" => menu.menu_id
               },
               authorization: %{
                 principal: %{permissions: ["role:update", "permission:manage"]},
                 permission: "role:update"
               }
             )

    assert Role.menu_ids_for_role(role.role_id) == [menu.menu_id]
  end

  test "protects role permission metadata behind an explicit permission" do
    role = insert_role(%{role_key: unique("metadata_role")})
    user = %{user_id: Identity.v7(), role_id: role.role_id}

    refute Permission.role_metadata_allowed?(user, %{"menuIds" => "1"})
    refute Permission.role_metadata_allowed?(user, %{"dataScope" => 1})
    assert Permission.role_metadata_allowed?(user, %{"roleName" => "普通编辑"})

    permission_menu =
      %SysMenu{}
      |> SysMenu.changeset(%{
        menu_name: "角色权限配置",
        menu_type: 0,
        parent_id: nil,
        permission: "role:manage",
        status: 1
      })
      |> Repo.insert!()

    Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: permission_menu.menu_id})
    insert_permission(role.role_id, "role:manage")
    assert Permission.role_metadata_allowed?(user, %{"menuIds" => "1"})
  end

  test "protects menu permission metadata behind an explicit permission" do
    role = insert_role(%{role_key: unique("menu_metadata_role")})
    user = %{user_id: Identity.v7(), role_id: role.role_id}

    refute Permission.menu_metadata_allowed?(user, %{"permission" => "user:read"})
    assert Permission.menu_metadata_allowed?(user, %{"menuName" => "普通菜单"})
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

  defp insert_dept(legacy_id, parent_id, ancestors) do
    parent_id = if parent_id in [0, "0"], do: nil, else: parent_id
    ancestors = if parent_id, do: to_string(parent_id), else: ancestors

    %SysDept{}
    |> SysDept.changeset(%{
      parent_id: parent_id,
      ancestors: ancestors,
      dept_name: "部门 #{legacy_id}",
      status: 1
    })
    |> Repo.insert!()
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"

  defp insert_permission(role_id, permission) do
    entry =
      Repo.get_by(SysPermission, permission: permission) ||
        Repo.insert!(%SysPermission{
          permission_id: Identity.permission_id(permission),
          permission: permission,
          resource: permission |> String.split(":") |> Enum.at(0),
          domain: "default",
          action: permission |> String.split(":") |> List.last(),
          status: 1,
          deprecated: false
        })

    Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: entry.permission_id})
  end
end
