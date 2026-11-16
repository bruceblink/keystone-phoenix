defmodule KeystonePhoenix.MenuRoleAccessTest do
  use KeystonePhoenix.DataCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.User.SysUserRole

  test "menus and permissions use the union of all active persisted roles" do
    first_role = insert_role("menu_union_first", 1)
    second_role = insert_role("menu_union_second", 1)
    disabled_role = insert_role("menu_union_disabled", 0)

    first_menu = insert_menu("menu_union_first", "union:first", false)
    second_menu = insert_menu("menu_union_second", "union:second", true)
    disabled_menu = insert_menu("menu_union_disabled", "union:disabled", false)

    link_menu(first_role.role_id, first_menu.menu_id)
    link_menu(second_role.role_id, second_menu.menu_id)
    link_menu(disabled_role.role_id, disabled_menu.menu_id)
    grant_permission(first_role.role_id, "union:first")
    grant_permission(second_role.role_id, "union:second")
    grant_permission(disabled_role.role_id, "union:disabled")

    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        username: "menu_union_user_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        role_id: first_role.role_id,
        status: 1
      })
      |> Repo.insert!()

    user_id = user.user_id

    Repo.insert_all(SysUserRole, [
      %{user_id: user_id, role_id: first_role.role_id},
      %{user_id: user_id, role_id: second_role.role_id},
      %{user_id: user_id, role_id: disabled_role.role_id}
    ])

    principal = %{user_id: user_id, role_id: first_role.role_id}
    menu_ids = Menu.menus_for_user(principal) |> Enum.map(& &1["menuId"])

    assert first_menu.menu_id in menu_ids
    assert second_menu.menu_id in menu_ids
    refute disabled_menu.menu_id in menu_ids
    assert Menu.permissions_for_user(principal) == ["union:first", "union:second"]

    Repo.delete_all(
      from membership in SysUserRole,
        where: membership.user_id == ^user_id and membership.role_id == ^second_role.role_id
    )

    menu_ids = Menu.menus_for_user(principal) |> Enum.map(& &1["menuId"])
    assert first_menu.menu_id in menu_ids
    refute second_menu.menu_id in menu_ids
    assert Menu.permissions_for_user(principal) == ["union:first"]
  end

  defp insert_role(key, status) do
    %SysRole{}
    |> SysRole.changeset(%{
      role_name: key,
      role_key: key,
      role_sort: 1,
      data_scope: "ALL",
      status: status
    })
    |> Repo.insert!()
  end

  defp insert_menu(code, permission, button) do
    %SysMenu{}
    |> SysMenu.changeset(%{
      menu_code: code,
      menu_name: code,
      menu_type: 0,
      is_button: button,
      status: 1
    })
    |> Repo.insert!()
    |> then(fn menu ->
      link_permission(menu.menu_id, permission)
      menu
    end)
  end

  defp link_menu(role_id, menu_id),
    do: Repo.insert!(%SysRoleMenu{role_id: role_id, menu_id: menu_id})

  defp link_permission(menu_id, permission) do
    entry = ensure_permission(permission)

    Repo.insert!(%KeystonePhoenix.Authz.SysMenuPermission{
      menu_id: menu_id,
      permission_id: entry.permission_id
    })
  end

  defp grant_permission(role_id, permission) do
    entry = ensure_permission(permission)
    Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: entry.permission_id})
  end

  defp ensure_permission(permission) do
    Repo.get_by(SysPermission, permission: permission) ||
      Repo.insert!(%SysPermission{
        permission_id: Identity.permission_id(permission),
        permission: permission,
        resource: "union",
        domain: "union",
        action: "read",
        status: 1,
        deprecated: false
      })
  end
end
