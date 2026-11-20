defmodule KeystonePhoenixWeb.RoleMemberPaginationTest do
  @moduledoc "用真实数据库检查角色成员两栏的服务端分页。"

  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import KeystonePhoenixWeb.LiveAuthenticationTestSupport

  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUserRole

  setup do
    ensure_captcha_config()
    disable_captcha()
    on_exit(&clear_config_cache/0)

    admin_role = role("分页管理员")

    for code <- ["role:read", "role:assign"] do
      permission = Repo.get_by!(SysPermission, permission: code)

      Repo.insert!(%SysRolePermission{
        role_id: admin_role.role_id,
        permission_id: permission.permission_id
      })
    end

    {:ok, admin} = create_user(%{"role_id" => admin_role.role_id})
    target = role("分页目标角色")

    for _ <- 1..10 do
      {:ok, user} = create_user(%{})
      Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: target.role_id})
    end

    for _ <- 1..10, do: create_user(%{})

    PolicyCache.invalidate()
    {:ok, admin: admin, target: target}
  end

  @tag :integration
  test "两栏分页只加载当前页并保留独立页码", %{conn: conn, admin: admin, target: target} do
    {:ok, view, _html} = login_view(conn, admin)
    render_click(view, "show-panel", %{"panel" => "roles"})
    render_click(view, "select-role", %{"role-id" => to_string(target.role_id)})

    first = live_socket(view).assigns
    assert first.role_user_totals.allocated == 10
    assert length(first.allocated_role_user_rows) == 8
    first_ids = Enum.map(first.allocated_role_user_rows, & &1["userId"])
    assert render(view) =~ "已分配用户（10）"

    render_click(view, "paginate", %{"panel" => "role-users-allocated", "page" => "2"})
    second = live_socket(view).assigns
    assert second.page_nums["role-users-allocated"] == 2
    assert second.page_nums["role-users-unallocated"] == 1
    assert second.role_user_totals.allocated == 10
    assert length(second.allocated_role_user_rows) == 2
    assert Enum.all?(second.allocated_role_user_rows, &(&1["userId"] not in first_ids))

    unallocated_ids = Enum.map(second.unallocated_role_user_rows, & &1["userId"])
    render_click(view, "paginate", %{"panel" => "role-users-unallocated", "page" => "2"})
    other_page = live_socket(view).assigns
    assert other_page.page_nums["role-users-allocated"] == 2
    assert other_page.page_nums["role-users-unallocated"] == 2

    assert Enum.all?(
             other_page.unallocated_role_user_rows,
             &(&1["userId"] not in unallocated_ids)
           )

    render_click(view, "paginate", %{"panel" => "role-users-allocated", "page" => "99"})
    assert live_socket(view).assigns.page_nums["role-users-allocated"] == 2

    render_click(view, "close-role-users")
    assert live_socket(view).assigns.role_user_totals == %{allocated: 0, unallocated: 0}
  end

  defp role(label) do
    suffix = System.unique_integer([:positive])

    %SysRole{}
    |> SysRole.changeset(%{
      role_name: "#{label}#{suffix}",
      role_key: "member_page_#{suffix}",
      role_sort: 1,
      data_scope: "ALL",
      dept_id_set: "",
      status: 1
    })
    |> Repo.insert!()
  end
end
