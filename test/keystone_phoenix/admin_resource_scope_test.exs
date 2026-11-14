defmodule KeystonePhoenix.AdminResourceScopeTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Menu

  test "menu service commands reject a department-scoped principal" do
    authorization = [authorization: %{principal: principal("DEPARTMENT", menu_permissions())}]

    assert {:error, :data_scope_denied} = Menu.list_menus(%{}, authorization)
    assert {:error, :data_scope_denied} = Menu.list_dropdown(authorization)
    assert {:error, :data_scope_denied} = Menu.get_menu(Identity.v7(), authorization)

    assert {:error, :data_scope_denied} =
             Menu.create_menu(
               %{"menuName" => "越界菜单", "menuType" => 1, "status" => 1},
               authorization
             )

    assert {:error, :data_scope_denied} =
             Menu.update_menu(Identity.v7(), %{"menuName" => "越界修改"}, authorization)

    assert {:error, :data_scope_denied} = Menu.delete_menu(Identity.v7(), authorization)
  end

  test "menu service commands use the tenant scope for the complete lifecycle" do
    authorization = [authorization: %{principal: principal("TENANT", menu_permissions())}]

    assert {:ok, menu} =
             Menu.create_menu(
               %{"menuName" => "范围菜单", "menuType" => 1, "status" => 1},
               authorization
             )

    assert {:ok, menus} = Menu.list_menus(%{"status" => 1}, authorization)
    assert Enum.any?(menus, &(&1["menuId"] == menu.menu_id))
    assert {:ok, loaded} = Menu.get_menu(menu.menu_id, authorization)
    assert loaded.menu_id == menu.menu_id

    assert {:ok, updated} =
             Menu.update_menu(menu.menu_id, %{"menuName" => "范围菜单已更新"}, authorization)

    assert updated.menu_name == "范围菜单已更新"
    assert :ok = Menu.delete_menu(menu.menu_id, authorization)
  end

  test "configuration service commands enforce scope for reads, writes and refresh" do
    permissions = ["config:read", "config:create", "config:update", "config:refresh"]
    blocked = [authorization: %{principal: principal("DEPARTMENT", permissions)}]

    assert {:error, :data_scope_denied} = Config.list_configs(%{}, blocked)
    assert {:error, :data_scope_denied} = Config.get_config(Identity.v7(), blocked)
    assert {:error, :data_scope_denied} = Config.refresh_cache(blocked)

    assert {:error, :data_scope_denied} =
             Config.create_config(%{"configName" => "越界配置"}, blocked)

    allowed = [authorization: %{principal: principal("TENANT", permissions)}]
    key = "scope.config.#{System.unique_integer([:positive])}"

    assert {:ok, config} =
             Config.create_config(
               %{
                 "configName" => "范围配置",
                 "configKey" => key,
                 "configValue" => "enabled",
                 "configOptions" => ["enabled", "disabled"],
                 "isAllowChange" => true
               },
               allowed
             )

    assert {:ok, page} = Config.list_configs(%{"configKey" => key}, allowed)
    assert Enum.any?(page.rows, &(&1["configId"] == config.config_id))
    assert {:ok, loaded} = Config.get_config(config.config_id, allowed)
    assert loaded.config_id == config.config_id

    assert {:ok, updated} =
             Config.update_config(config.config_id, %{"configValue" => "disabled"}, allowed)

    assert updated.config_value == "disabled"
    assert :ok = Config.refresh_cache(allowed)
  end

  test "service reads require an explicit authorization context" do
    assert {:error, :authorization_required} = Menu.list_menus(%{}, [])
    assert {:error, :authorization_required} = Config.list_configs(%{}, [])
  end

  defp menu_permissions do
    ["menu:read", "menu:create", "menu:update", "menu:delete"]
  end

  defp principal(data_scope, permissions), do: %{data_scope: data_scope, permissions: permissions}
end
