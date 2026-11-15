defmodule KeystonePhoenixWeb.Live.OrganizationFiltersTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationFilters

  test "filters organization rows by keyword and status" do
    rows = [
      %{"deptName" => "平台部", "leaderName" => "李雷", "status" => 1},
      %{"deptName" => "市场部", "leaderName" => "韩梅梅", "status" => 0}
    ]

    assert OrganizationFilters.filtered_depts(rows, %{"keyword" => "市场", "status" => "all"}) ==
             [Enum.at(rows, 1)]

    assert OrganizationFilters.filtered_depts(rows, %{"keyword" => "", "status" => "1"}) ==
             [Enum.at(rows, 0)]
  end

  test "resets event filter values and preserves existing values on refresh" do
    previous = %{"keyword" => "旧值", "status" => "0"}

    assert OrganizationFilters.organization_filter(%{"reset" => "true"}, previous, [
             "keyword",
             "status"
           ]) == %{"keyword" => "", "status" => "all"}

    assert OrganizationFilters.organization_filter(%{}, previous, ["keyword", "status"]) ==
             previous
  end

  test "filters menu rows by route and permission values" do
    rows = [
      %{"menuName" => "用户", "path" => "/users", "permission" => "user:read"},
      %{"menuName" => "角色", "path" => "/roles", "permission" => "role:read"}
    ]

    assert OrganizationFilters.filtered_menus(rows, "user:read") == [Enum.at(rows, 0)]
    assert OrganizationFilters.menu_filter(%{"menuKeyword" => " /roles "}, "") == "/roles"
  end

  test "keeps menu ancestors when a descendant matches" do
    rows = [
      %{"menuId" => "root", "parentId" => nil, "menuName" => "系统", "depth" => 0},
      %{"menuId" => "child", "parentId" => "root", "menuName" => "用户", "depth" => 1},
      %{
        "menuId" => "grandchild",
        "parentId" => "child",
        "menuName" => "用户列表",
        "permission" => "user:read",
        "depth" => 2
      }
    ]

    assert OrganizationFilters.filtered_menus(rows, "user:read") == rows
  end

  test "keeps mixed identifier types connected in a filtered menu tree" do
    rows = [
      %{"menuId" => 1, "parentId" => "0", "menuName" => "系统"},
      %{"menuId" => 2, "parentId" => "1", "menuName" => "用户"},
      %{"menuId" => 3, "parentId" => 2, "menuName" => "详情", "permission" => "user:detail"}
    ]

    assert OrganizationFilters.filtered_menus(rows, "user:detail") == rows
  end

  test "excludes the current menu and all descendants from parent choices" do
    rows = [
      %{"menuId" => "root", "parentId" => nil},
      %{"menuId" => "child", "parentId" => "root"},
      %{"menuId" => "grandchild", "parentId" => "child"},
      %{"menuId" => "sibling", "parentId" => "root"}
    ]

    assert OrganizationFilters.menu_parent_rows(rows, "child") ==
             [Enum.at(rows, 0), Enum.at(rows, 3)]
  end
end
