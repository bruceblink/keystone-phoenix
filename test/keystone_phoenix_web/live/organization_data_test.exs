defmodule KeystonePhoenixWeb.Live.OrganizationDataTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationData

  test "maps organization display labels" do
    assert OrganizationData.data_scope_label("DEPARTMENT_AND_CHILDREN") == "本部门及以下"
    assert OrganizationData.data_scope_label(99) == "未知"
    assert OrganizationData.menu_type_label(2, false) == "目录"
    assert OrganizationData.menu_type_label(0, true) == "按钮"
    assert OrganizationData.menu_type_label("DIRECTORY", false) == "目录"
    assert OrganizationData.menu_type_label("MENU", false) == "菜单"
    assert OrganizationData.menu_type_label("BUTTON", false) == "按钮"
  end

  test "normalizes native enabled and string menu fields" do
    assert OrganizationData.menu_enabled?(%{"status" => "1"})
    refute OrganizationData.menu_enabled?(%{"status" => "0"})

    rows = [
      %{
        "id" => "root",
        "parentId" => nil,
        "code" => "system",
        "name" => "系统",
        "menuType" => "MENU",
        "enabled" => true,
        "sortOrder" => 1
      },
      %{
        "id" => "button",
        "parentId" => "root",
        "code" => "system:button",
        "name" => "操作",
        "menuType" => "BUTTON",
        "enabled" => false,
        "sortOrder" => 1
      },
      %{
        "id" => "directory",
        "parentId" => "root",
        "code" => "system:directory",
        "name" => "目录",
        "menuType" => "DIRECTORY",
        "status" => "1",
        "sortOrder" => 2
      }
    ]

    assert OrganizationData.menu_tree_rows(rows)
           |> Enum.map(&{&1["id"], &1["enabled"], &1["status"], &1["menuTypeStr"]}) ==
             [{"root", true, 1, "菜单"}, {"button", false, 0, "按钮"}, {"directory", true, 1, "目录"}]
  end

  test "calculates department and menu depth safely" do
    assert OrganizationData.dept_depth(nil) == 0
    assert OrganizationData.dept_depth("0,1,2") == 2

    menus = %{
      1 => %{"parentId" => 0},
      2 => %{"parentId" => 1},
      3 => %{"parentId" => 3}
    }

    assert OrganizationData.menu_depth(0, menus, MapSet.new()) == 0
    assert OrganizationData.menu_depth(2, menus, MapSet.new()) == 2
    assert OrganizationData.menu_depth(3, menus, MapSet.new([3])) == 0
  end

  test "orders menu rows as a multi-level tree with mixed root identifiers" do
    rows = [
      %{
        "menuId" => "grandchild",
        "parentId" => "child",
        "menuName" => "详情",
        "sortOrder" => 1,
        "status" => 1
      },
      %{
        "menuId" => "root",
        "parentId" => "0",
        "menuName" => "系统",
        "sortOrder" => 1,
        "status" => 1
      },
      %{
        "menuId" => "child",
        "parentId" => "root",
        "menuName" => "用户",
        "sortOrder" => 1,
        "status" => 1
      }
    ]

    assert OrganizationData.menu_tree_rows(rows)
           |> Enum.map(&{&1["menuName"], &1["depth"]}) ==
             [{"系统", 0}, {"用户", 1}, {"详情", 2}]
  end

  test "treats string zero as a root parent when calculating depth" do
    menus = %{"root" => %{"parentId" => "0"}}

    assert OrganizationData.menu_depth("root", menus, MapSet.new()) == 1
    assert OrganizationData.menu_depth("0", menus, MapSet.new()) == 0
  end
end
