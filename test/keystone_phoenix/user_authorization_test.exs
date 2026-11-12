defmodule KeystonePhoenix.UserAuthorizationTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Department.SysDept
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
      is_admin: false
    }

    assert {:error, :data_scope_denied} =
             User.update_user(
               target.user_id,
               %{"nickname" => "不应保存"},
               authorization: %{principal: principal, permission: "system:user:edit"}
             )

    assert Repo.get!(SysUser, target.user_id).nickname == "范围外用户"
  end

  test "principal-aware user writes deny a missing permission" do
    {actor, target} = users_fixture()

    principal = %{
      user_id: actor.user_id,
      role_id: actor.role_id,
      dept_id: actor.dept_id,
      is_admin: false,
      permissions: []
    }

    assert {:error, :permission_denied} =
             User.update_user(
               target.user_id,
               %{"nickname" => "不应保存"},
               authorization: %{principal: principal, permission: "system:user:edit"}
             )
  end

  defp users_fixture do
    actor_dept = insert_dept("actor")
    target_dept = insert_dept("target")

    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: unique("scope_role"),
        role_key: unique("scope_role"),
        role_sort: 1,
        data_scope: 3,
        status: 1
      })
      |> Repo.insert!()

    menu =
      %SysMenu{}
      |> SysMenu.changeset(%{
        menu_name: "用户编辑",
        menu_type: 0,
        parent_id: 0,
        permission: "system:user:edit",
        status: 1
      })
      |> Repo.insert!()

    Repo.insert!(%SysRoleMenu{role_id: role.role_id, menu_id: menu.menu_id})

    actor =
      Repo.insert!(%SysUser{
        username: unique("scope_actor"),
        password: "password-hash",
        role_id: role.role_id,
        dept_id: actor_dept.dept_id,
        status: 1
      })

    target =
      Repo.insert!(%SysUser{
        username: unique("scope_target"),
        password: "password-hash",
        dept_id: target_dept.dept_id,
        status: 1,
        nickname: "范围外用户"
      })

    {actor, target}
  end

  defp insert_dept(label) do
    %SysDept{}
    |> SysDept.changeset(%{
      dept_name: "#{label}-#{unique("department")}",
      parent_id: 0,
      ancestors: "0",
      status: 1
    })
    |> Repo.insert!()
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
