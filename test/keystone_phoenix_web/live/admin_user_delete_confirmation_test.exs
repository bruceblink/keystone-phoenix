defmodule KeystonePhoenixWeb.AdminUserDeleteConfirmationTest do
  @moduledoc "用真实 LiveView 和事务数据库验收用户批量删除确认。"

  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import KeystonePhoenixWeb.LiveAuthenticationTestSupport

  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  setup do
    ensure_captcha_config()
    disable_captcha()
    clear_config_cache()
    on_exit(&clear_config_cache/0)

    role = create_role(["user:read", "user:delete"])
    {:ok, admin} = create_user(%{"role_id" => role.role_id})
    {:ok, admin: admin}
  end

  @tag :integration
  test "取消关闭确认框但保留选择和用户", %{conn: conn, admin: admin} do
    {:ok, selected} = create_user(%{})
    {:ok, view, _html} = login_view(conn, admin)
    select_users(view, [selected])

    assert has_element?(view, "#user-delete-modal[data-open='true']")
    assert has_element?(view, "#user-delete-modal[aria-labelledby='user-delete-modal-title']")
    assert has_element?(view, "#user-delete-modal button[autofocus]", "取消")
    assert has_element?(view, "form#user-delete-cancel-form[method='dialog']")
    assert has_element?(view, "button[form='user-delete-cancel-form'][type='submit']")

    assert has_element?(
             view,
             "#user-delete-form input[name='user-ids'][value='#{selected.user_id}']"
           )

    render_click(view, "close-user-delete")

    assert live_socket(view).assigns.active_modal == nil
    assert live_socket(view).assigns.selected_user_ids == [to_string(selected.user_id)]
    refute Repo.get!(SysUser, selected.user_id).deleted
  end

  @tag :integration
  test "提交确认只删除选中用户", %{conn: conn, admin: admin} do
    {:ok, selected} = create_user(%{})
    {:ok, retained} = create_user(%{})
    {:ok, view, _html} = login_view(conn, admin)
    select_users(view, [selected])

    view
    |> form("#user-delete-form")
    |> render_submit()

    assert render(view) =~ "已删除 1 个用户"
    assert live_socket(view).assigns.active_modal == nil
    assert live_socket(view).assigns.selected_user_ids == []
    assert Repo.get!(SysUser, selected.user_id).deleted
    refute Repo.get!(SysUser, retained.user_id).deleted
  end

  @tag :integration
  test "删除失败时保留确认框、选择和错误反馈", %{conn: conn, admin: admin} do
    {:ok, unrelated} = create_user(%{})
    {:ok, view, _html} = login_view(conn, admin)
    select_users(view, [admin])

    view
    |> form("#user-delete-form")
    |> render_submit()

    assert has_element?(view, "#user-delete-modal [role='alert']", "当前用户或管理员不能删除")
    assert live_socket(view).assigns.active_modal == "user-delete"
    assert live_socket(view).assigns.selected_user_ids == [to_string(admin.user_id)]
    refute Repo.get!(SysUser, admin.user_id).deleted
    refute Repo.get!(SysUser, unrelated.user_id).deleted
  end

  @tag :integration
  test "表单 ID 与当前选择不一致时拒绝删除并保留错误", %{conn: conn, admin: admin} do
    {:ok, selected} = create_user(%{})
    {:ok, other} = create_user(%{})
    {:ok, view, _html} = login_view(conn, admin)
    select_users(view, [selected])

    render_submit(view, "delete-users", %{"user-ids" => to_string(other.user_id)})

    assert has_element?(view, "#user-delete-modal [role='alert']", "与当前选择不一致")
    assert live_socket(view).assigns.active_modal == "user-delete"
    assert live_socket(view).assigns.selected_user_ids == [to_string(selected.user_id)]
    refute Repo.get!(SysUser, selected.user_id).deleted
    refute Repo.get!(SysUser, other.user_id).deleted
  end

  @tag :integration
  test "没有删除权限时伪造确认事件不会删除用户", %{conn: conn} do
    role = create_role(["user:read"])
    {:ok, reader} = create_user(%{"role_id" => role.role_id})
    {:ok, target} = create_user(%{})
    {:ok, view, _html} = login_view(conn, reader)
    render_click(view, "show-panel", %{"panel" => "users"})

    refute has_element?(view, "#user-delete-toolbar-action")

    render_click(view, "toggle-user-selection", %{
      "user-id" => to_string(target.user_id),
      "selected" => "true"
    })

    render_click(view, "open-user-delete")
    render_submit(view, "delete-users", %{"user-ids" => to_string(target.user_id)})

    assert live_socket(view).assigns.active_modal == nil
    refute Repo.get!(SysUser, target.user_id).deleted
  end

  # 通过列表选择入口保留批量操作的真实 LiveView 事件顺序。
  defp select_users(view, users) do
    render_click(view, "show-panel", %{"panel" => "users"})

    for user <- users do
      render_click(view, "toggle-user-selection", %{
        "user-id" => to_string(user.user_id),
        "selected" => "true"
      })
    end

    render_click(view, "open-user-delete")
  end

  defp create_role(permissions) do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: unique("user_delete_role"),
        role_key: unique("user_delete_role_key"),
        role_sort: 1,
        data_scope: "ALL",
        dept_id_set: "",
        status: 1
      })
      |> Repo.insert!()

    for permission <- permissions do
      permission = Repo.get_by!(SysPermission, permission: permission)

      Repo.insert!(%SysRolePermission{
        role_id: role.role_id,
        permission_id: permission.permission_id
      })
    end

    PolicyCache.invalidate()
    role
  end
end
