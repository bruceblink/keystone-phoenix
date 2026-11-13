defmodule KeystonePhoenixWeb.Live.OrganizationDataTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationData

  test "maps organization display labels" do
    assert OrganizationData.data_scope_label("DEPARTMENT_AND_CHILDREN") == "本部门及以下"
    assert OrganizationData.data_scope_label(99) == "未知"
    assert OrganizationData.menu_type_label(2, false) == "目录"
    assert OrganizationData.menu_type_label(0, true) == "按钮"
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
end
