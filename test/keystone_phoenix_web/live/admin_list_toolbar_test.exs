defmodule KeystonePhoenixWeb.AdminListToolbarTest do
  @moduledoc "覆盖管理列表工具栏的位置、操作顺序和表单关联。"

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.{Accounts, Organization}

  # 列表操作留在结果卡内并位于标题前，初次读取错误时也保持可见。
  test "用户和组织列表在空结果或错误状态下保留工具栏" do
    user_html =
      render_component(&Accounts.users/1, %{
        user_rows: [],
        user_feedback: {:error, "读取用户失败"},
        permissions: ["user:import", "user:export", "user:delete"]
      })

    assert_toolbar_in_card(user_html, "users-filter-card", "users-table-card")

    assert_event_order(user_html, [
      ~s(phx-click="new-user"),
      ~s(phx-click="new-user-import"),
      ~s(phx-click="export-users"),
      ~s(phx-click="delete-users"),
      ~s(phx-click="refresh-users")
    ])

    assert [toolbar_html] =
             Regex.run(~r/<div class="list-toolbar".*?<div class="card-header">/s, user_html)

    assert length(Regex.scan(~r/class="nav-icon-svg"/, toolbar_html)) == 4
    assert Regex.match?(~r/phx-disable-with="查询中…"><svg class="nav-icon-svg"/, user_html)

    department_html =
      render_component(&Organization.departments/1, %{
        dept_rows: [],
        dept_feedback: {:error, "读取组织失败"}
      })

    assert_toolbar_in_card(department_html, "departments-filter-card", "departments-table-card")

    assert_event_order(department_html, [~s(phx-click="new-dept"), ~s(phx-click="refresh-depts")])

    post_html =
      render_component(&Organization.posts/1, %{
        post_rows: [],
        post_feedback: {:error, "读取岗位失败"},
        permissions: ["post:export"]
      })

    assert_toolbar_in_card(post_html, "posts-filter-card", "posts-table-card")

    assert_event_order(post_html, [
      ~s(phx-click="new-post"),
      ~s(phx-click="export-posts"),
      ~s(phx-click="refresh-posts")
    ])

    role_html =
      render_component(&Organization.roles/1, %{
        role_rows: [],
        role_feedback: {:error, "读取角色失败"},
        permissions: ["role:export"]
      })

    assert_toolbar_in_card(role_html, "roles-filter-card", "roles-table-card")
    assert role_html =~ ~s(phx-click="new-role")
    assert role_html =~ ~s(phx-click="export-roles")
    assert role_html =~ ~s(id="role-delete-toolbar-action")
    assert role_html =~ ~s(phx-click="refresh-roles")

    assert role_html =~
             ~s(id="role-delete-toolbar-action" class="button button-danger button-sm" phx-click="open-role-delete" disabled)

    assert_event_order(role_html, [
      ~s(phx-click="new-role"),
      ~s(phx-click="export-roles"),
      ~s(id="role-delete-toolbar-action"),
      ~s(phx-click="refresh-roles")
    ])

    menu_html =
      render_component(&Organization.menus/1, %{
        menu_rows: [],
        menu_feedback: {:error, "读取菜单失败"}
      })

    assert_toolbar_in_card(menu_html, "menus-filter-card", "menus-table-card")
    assert_event_order(menu_html, [~s(phx-click="new-menu"), ~s(phx-click="refresh-menus")])
  end

  # 确认框内的提交按钮仍指向包含角色复选框的原批量删除表单。
  test "角色批量删除确认按钮提交角色选择表单" do
    role = %{
      "roleId" => 7,
      "roleName" => "测试角色",
      "roleKey" => "toolbar_test",
      "dataScopeStr" => "全部数据",
      "permissionCount" => 1,
      "status" => 1
    }

    html =
      render_component(&Organization.roles/1, %{
        role_rows: [role],
        selected_role_ids: ["7"],
        role_feedback: nil,
        active_modal: "role-delete"
      })

    assert html =~ ~s(phx-click="open-role-delete")
    assert html =~ ~s(form="role-delete-form")
    assert html =~ "确认删除 1 条"
    assert html =~ ~s(phx-disable-with="删除中…")

    assert html =~ ~s(<form id="role-delete-form" phx-submit="delete-role">)
    form_start = index!(html, ~s(<form id="role-delete-form"))
    form_end = index!(html, "</form>", form_start)
    form_html = binary_part(html, form_start, form_end - form_start)

    assert Regex.run(
             ~r/<input\b[^>]*name="role-ids\[\]"[^>]*value="7"[^>]*checked[^>]*>/,
             form_html
           )
  end

  # 用户表格直接使用 admin-web 的滚动区域，避免旧 table-scroll 外观叠加。
  test "用户表格使用页面级横向滚动容器" do
    html =
      render_component(&Accounts.users/1, %{
        user_rows: [
          %{"userId" => "user-1", "username" => "operator", "nickname" => "操作员", "status" => 1}
        ],
        user_feedback: nil,
        permissions: []
      })

    assert html =~ ~s(class="users-table-wrap" role="region" tabindex="0" aria-label="用户列表")
    refute html =~ ~s(class="table-scroll" role="region" tabindex="0" aria-label="用户列表")
    assert html =~ ~s(<th scope="col">用户</th>)
  end

  defp assert_toolbar_in_card(html, filter_class, results_class) do
    filter_index = index!(html, filter_class)
    results_index = index!(html, results_class)
    toolbar_index = index!(html, ~s(<div class="list-toolbar"), results_index)
    heading_index = index!(html, ~s(class="card-header"), toolbar_index)

    assert filter_index < results_index
    assert results_index < toolbar_index
    assert toolbar_index < heading_index
  end

  defp assert_event_order(html, markers) do
    toolbar_start = index!(html, ~s(<div class="list-toolbar"))
    toolbar_end = index!(html, "</div>", toolbar_start)
    toolbar_html = binary_part(html, toolbar_start, toolbar_end - toolbar_start)
    positions = Enum.map(markers, &index!(toolbar_html, &1))
    assert positions == Enum.sort(positions)
  end

  defp index!(html, marker, offset \\ 0) do
    case :binary.match(html, marker, scope: {offset, byte_size(html) - offset}) do
      {index, _length} -> index
      :nomatch -> flunk("找不到预期的页面标记：#{marker}")
    end
  end
end
