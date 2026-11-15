defmodule KeystonePhoenixWeb.Live.MenuTreeRenderTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.Organization

  test "menu panel renders every tree level with stable hierarchy metadata" do
    html =
      render_component(&Organization.menus/1, %{
        menu_rows: [
          %{
            "menuId" => "root",
            "parentId" => nil,
            "menuName" => "系统",
            "menuCode" => "system",
            "depth" => 0,
            "status" => 1,
            "menuTypeStr" => "目录"
          },
          %{
            "menuId" => "child",
            "parentId" => "root",
            "menuName" => "用户",
            "menuCode" => "user",
            "depth" => 1,
            "status" => 1,
            "menuTypeStr" => "菜单"
          },
          %{
            "menuId" => "grandchild",
            "parentId" => "child",
            "menuName" => "详情",
            "menuCode" => "detail",
            "depth" => 2,
            "status" => 1,
            "menuTypeStr" => "菜单"
          }
        ],
        menu_form: %{"menuId" => ""},
        menu_feedback: nil,
        read_only: true
      })

    assert html =~ ~s(data-menu-id="root")
    assert html =~ ~s(data-parent-menu-id="root")
    assert html =~ ~s(data-menu-depth="2")
    assert html =~ "--menu-depth: 2"
    assert html =~ "详情"
  end

  test "menu panel renders native enabled and type fields" do
    html =
      render_component(&Organization.menus/1, %{
        menu_rows: [
          %{
            "id" => "native-menu",
            "parentId" => nil,
            "name" => "用户",
            "code" => "user",
            "depth" => 0,
            "enabled" => true,
            "menuType" => "MENU"
          }
        ],
        menu_form: %{"menuId" => ""},
        menu_feedback: nil,
        read_only: true
      })

    assert html =~ ~s(data-menu-id="native-menu")
    assert html =~ "菜单"
    assert html =~ "启用"
    assert html =~ "status-badge--normal"
  end
end
