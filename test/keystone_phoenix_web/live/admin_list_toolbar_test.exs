defmodule KeystonePhoenixWeb.AdminListToolbarTest do
  @moduledoc "覆盖管理列表工具栏的位置、操作顺序和表单关联。"

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KeystonePhoenixWeb.Live.AdminPages.{Accounts, Organization}

  # 列表操作必须在筛选卡之后、结果卡之前，避免依赖查询结果渲染。
  test "用户和组织列表在空结果或错误状态下保留工具栏" do
    user_html =
      render_component(&Accounts.users/1, %{
        user_rows: [],
        user_feedback: {:error, "读取用户失败"},
        permissions: ["user:import", "user:export", "user:delete"]
      })

    assert_toolbar_between(user_html, "users-filter-card", "list-toolbar", "users-table-card")

    assert_event_order(user_html, [
      ~s(phx-click="new-user"),
      ~s(phx-click="new-user-import"),
      ~s(phx-click="export-users"),
      ~s(phx-click="delete-users"),
      ~s(phx-click="refresh-users")
    ])

    department_html =
      render_component(&Organization.departments/1, %{
        dept_rows: [],
        dept_feedback: {:error, "读取组织失败"}
      })

    assert_toolbar_between(
      department_html,
      "departments-filter-card",
      "list-toolbar",
      "departments-table-card"
    )

    assert_event_order(department_html, [~s(phx-click="new-dept"), ~s(phx-click="refresh-depts")])

    post_html =
      render_component(&Organization.posts/1, %{
        post_rows: [],
        post_feedback: {:error, "读取岗位失败"},
        permissions: ["post:export"]
      })

    assert_toolbar_between(post_html, "posts-filter-card", "list-toolbar", "posts-table-card")

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

    assert_toolbar_between(role_html, "roles-filter-card", "list-toolbar", "roles-table-card")
    assert role_html =~ ~s(phx-click="new-role")
    assert role_html =~ ~s(phx-click="export-roles")
    assert role_html =~ ~s(id="role-delete-toolbar-action")
    assert role_html =~ ~s(phx-click="refresh-roles")

    assert role_html =~
             ~s(id="role-delete-toolbar-action" class="button button-danger button-sm" phx-disable-with="删除中…" disabled)

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

    assert_toolbar_between(menu_html, "menus-filter-card", "list-toolbar", "menus-table-card")
    assert_event_order(menu_html, [~s(phx-click="new-menu"), ~s(phx-click="refresh-menus")])
  end

  # 外置提交按钮仍指向包含角色复选框的原批量删除表单。
  test "角色批量删除工具栏按钮提交角色选择表单" do
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
        role_feedback: nil
      })

    assert [delete_button] =
             Regex.run(~r/<button\b(?=[^>]*id="role-delete-toolbar-action")[^>]*>/, html)

    assert delete_button =~ ~s(form="role-delete-form")
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

  defp assert_toolbar_between(html, filter_class, toolbar_class, results_class) do
    filter_index = index!(html, filter_class)
    toolbar_index = index!(html, toolbar_class)
    results_index = index!(html, results_class)

    assert filter_index < toolbar_index
    assert toolbar_index < results_index
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
