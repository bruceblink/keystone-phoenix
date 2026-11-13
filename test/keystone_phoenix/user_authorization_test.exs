defmodule KeystonePhoenix.UserAuthorizationTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Department.SysDept

  alias KeystonePhoenix.Authz.{
    PermissionCatalog,
    SysMenuPermission,
    SysPermission,
    SysRolePermission
  }

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.SysUser

  test "principal-aware user writes deny an out-of-scope target before updating" do
    {actor, target} = users_fixture()

    principal = %{
      user_id: actor.user_id,
      role_id: actor.role_id,
      dept_id: actor.dept_id,
      permissions: ["user:update"]
    }

    assert {:error, :data_scope_denied} =
             User.update_user(
               target.user_id,
               %{"nickname" => "不应保存"},
               authorization: %{principal: principal, permission: "user:update"}
             )

    assert Repo.get!(SysUser, target.user_id).nickname == "范围外用户"
  end

  test "principal-aware user writes deny a missing permission" do
    {actor, target} = users_fixture()

    principal = %{
      user_id: actor.user_id,
      role_id: actor.role_id,
      dept_id: actor.dept_id,
      permissions: []
    }

    assert {:error, :permission_denied} =
             User.update_user(
               target.user_id,
               %{"nickname" => "不应保存"},
               authorization: %{principal: principal, permission: "user:update"}
             )
  end

  test "principal-aware profile writes are limited to the authenticated subject" do
    {actor, target} = users_fixture()

    assert {:error, :data_scope_denied} =
             User.update_profile(target.user_id, %{"nickname" => "不应保存"},
               authorization: %{principal: %{user_id: actor.user_id}}
             )

    assert Repo.get!(SysUser, target.user_id).nickname == "范围外用户"
  end

  defp users_fixture do
    actor_dept = insert_dept("actor")
    target_dept = insert_dept("target")

    role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: unique("scope_role"),
        role_key: unique("scope_role"),
        role_sort: 1,
        data_scope: "DEPARTMENT",
        status: 1
      })
      |> Repo.insert!()

    menu =
      %SysMenu{menu_id: Identity.v7()}
      |> SysMenu.changeset(%{
        menu_name: "用户编辑",
        menu_type: 0,
        parent_id: nil,
        status: 1
      })
      |> Repo.insert!()

    permission_entry =
      Repo.get_by(SysPermission, permission: "user:update") ||
        Repo.insert!(%SysPermission{
          permission_id: Identity.permission_id("user:update"),
          permission: "user:update",
          resource: "user",
          domain: "default",
          action: "update",
          status: 1,
          deprecated: false
        })

    assert PermissionCatalog.registered?(permission_entry.permission)

    Repo.insert!(%SysMenuPermission{
      menu_id: menu.menu_id,
      permission_id: permission_entry.permission_id
    })

    Repo.insert!(%SysRolePermission{
      role_id: role.role_id,
      permission_id: permission_entry.permission_id
    })

    Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: menu.menu_id})

    actor =
      Repo.insert!(%SysUser{
        user_id: Identity.v7(),
        username: unique("scope_actor"),
        password: "password-hash",
        role_id: role.role_id,
        dept_id: actor_dept.dept_id,
        status: 1
      })

    target =
      Repo.insert!(%SysUser{
        user_id: Identity.v7(),
        username: unique("scope_target"),
        password: "password-hash",
        dept_id: target_dept.dept_id,
        status: 1,
        nickname: "范围外用户"
      })

    {actor, target}
  end

  defp insert_dept(label) do
    %SysDept{dept_id: Identity.v7()}
    |> SysDept.changeset(%{
      dept_name: "#{label}-#{unique("department")}",
      parent_id: nil,
      ancestors: "",
      status: 1
    })
    |> Repo.insert!()
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
