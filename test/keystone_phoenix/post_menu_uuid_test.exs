defmodule KeystonePhoenix.PostMenuUuidTest do
  use KeystonePhoenix.DataCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Authz.SysMenuPermission
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Post.SysPost
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRoleMenu

  test "post and menu changesets generate UUIDv7 identifiers" do
    post = SysPost.changeset(%SysPost{}, %{post_code: "uuid-post", post_name: "UUID 岗位"})
    menu = SysMenu.changeset(%SysMenu{}, %{menu_name: "UUID 菜单", menu_type: 2, parent_id: nil})

    post_id = Ecto.Changeset.get_change(post, :post_id)
    menu_id = Ecto.Changeset.get_change(menu, :menu_id)
    assert Identity.canonical?(post_id)
    assert Identity.canonical?(menu_id)
    assert String.at(post_id, 14) == "7"
    assert String.at(menu_id, 14) == "7"
    assert Ecto.Changeset.get_field(menu, :parent_id) == nil
  end

  test "uuid menu relations use binary UUID columns" do
    %{rows: rows} =
      Repo.query!("""
      SELECT table_name, column_name, data_type
      FROM information_schema.columns
      WHERE table_schema = current_schema()
        AND ((table_name = 'sys_post' AND column_name = 'post_id')
          OR (table_name = 'sys_menu' AND column_name IN ('menu_id', 'parent_id'))
          OR (table_name = 'sys_role_menu' AND column_name = 'menu_id')
          OR (table_name = 'sys_menu_permission' AND column_name = 'menu_id')
          OR (table_name = 'sys_user' AND column_name = 'post_id'))
      ORDER BY table_name, column_name
      """)

    assert length(rows) == 6
    assert Enum.all?(rows, &(&1 |> Enum.at(2) == "uuid"))
    refute Repo.exists?(from relation in SysRoleMenu, where: is_nil(relation.menu_id))
    refute Repo.exists?(from relation in SysMenuPermission, where: is_nil(relation.menu_id))
  end

  test "replaying the identity migration keeps existing records" do
    migration =
      Path.expand(
        "../../priv/repo/migrations/20261114120000_rebuild_post_menu_ids_as_uuid.exs",
        __DIR__
      )

    source = File.read!(migration)
    assert source =~ "unless uuid_ready?()"
    assert source =~ "count == 6"

    assert source =~
             "TRUNCATE TABLE sys_menu_permission, sys_role_menu, sys_menu, sys_post CASCADE"
  end
end
