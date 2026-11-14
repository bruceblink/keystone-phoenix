defmodule KeystonePhoenixWeb.UnassignedRoleTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.{Menu, Repo}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.User.SysUser

  test "a user without a role can log in and receives no routes or permissions" do
    user =
      Repo.insert!(%SysUser{
        user_id: Identity.v7(),
        username: "unassigned_#{System.unique_integer([:positive])}",
        password: Bcrypt.hash_pwd_salt("Strong!123"),
        status: 1
      })

    assert Menu.menus_for_user(user) == []
  end

  test "an unassigned role cannot expose menus" do
    _menu =
      %SysMenu{menu_id: Identity.v7()}
      |> SysMenu.changeset(%{
        menu_name: "菜单读取测试",
        menu_type: 1,
        path: "/unassigned-role-test",
        parent_id: nil,
        status: 1
      })
      |> Repo.insert!()

    rows = Menu.menus_for_user(%{role_id: nil})
    assert rows == []
  end
end
