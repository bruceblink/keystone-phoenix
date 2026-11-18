defmodule KeystonePhoenixWeb.AdminUserDisabledRoleLiveTest do
  @moduledoc "验证用户编辑页保留停用角色，并要求用户明确取消绑定。"

  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import KeystonePhoenixWeb.LiveAuthenticationTestSupport,
    only: [
      clear_config_cache: 0,
      disable_captcha: 0,
      ensure_captcha_config: 0,
      login_view: 2,
      unique: 1
    ]

  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.{RoleMembership, SysUser}

  setup do
    ensure_captcha_config()
    disable_captcha()
    clear_config_cache()
    on_exit(&clear_config_cache/0)
    :ok
  end

  @tag :integration
  test "saving profile fields without changing roles preserves an assigned disabled role", %{
    conn: conn
  } do
    actor = create_actor()
    disabled_role = create_role("profile_disabled", 0)
    active_role = create_role("profile_active", 1)
    {:ok, target} = create_user(%{"role_id" => disabled_role.role_id})
    RoleMembership.replace_user_roles([target.user_id], [disabled_role.role_id])
    {:ok, view, _html} = login_view(conn, actor)
    render_click(view, "show-panel", %{"panel" => "users"})
    render_click(view, "edit-user", %{"user-id" => to_string(target.user_id)})

    assert has_element?(view, disabled_role_selector(disabled_role, "[checked]"))
    assert has_element?(view, role_selector(active_role, "[disabled]"))
    refute has_element?(view, "input[name='roleCodes[]']")

    view
    |> form("#user-form", %{"nickname" => "只更新资料"})
    |> render_submit()

    assert Repo.get!(SysUser, target.user_id).nickname == "只更新资料"
    assert target_role_ids(target) == [disabled_role.role_id]
  end

  @tag :integration
  test "removing a disabled role enables active role selection and replaces the binding", %{
    conn: conn
  } do
    actor = create_actor()
    disabled_role = create_role("replace_disabled", 0)
    unassigned_disabled_role = create_role("unassigned_disabled", 0)
    active_role = create_role("replacement_active", 1)
    {:ok, target} = create_user(%{"role_id" => disabled_role.role_id})
    RoleMembership.replace_user_roles([target.user_id], [disabled_role.role_id])
    {:ok, view, _html} = login_view(conn, actor)
    render_click(view, "show-panel", %{"panel" => "users"})
    render_click(view, "edit-user", %{"user-id" => to_string(target.user_id)})

    assert has_element?(view, disabled_role_selector(disabled_role, "[checked]"))
    assert has_element?(view, role_selector(disabled_role, "[phx-value-selected='false']"))
    assert has_element?(view, role_selector(unassigned_disabled_role, "[disabled]"))
    assert has_element?(view, role_selector(active_role, "[disabled]"))

    render_click(view, "toggle-user-role", %{
      "role-code" => unassigned_disabled_role.role_key,
      "selected" => "true"
    })

    render_click(view, "toggle-user-role", %{
      "role-code" => active_role.role_key,
      "selected" => "true"
    })

    assert has_element?(view, role_selector(active_role, "[disabled]"))
    refute has_element?(view, role_selector(active_role, "[checked]"))

    render_click(view, "toggle-user-role", %{
      "role-code" => disabled_role.role_key,
      "selected" => "false"
    })

    refute has_element?(view, role_selector(disabled_role, "[checked]"))
    assert has_element?(view, role_selector(active_role, "[phx-value-selected='true']"))
    refute has_element?(view, role_selector(active_role, "[disabled]"))

    render_click(view, "toggle-user-role", %{
      "role-code" => active_role.role_key,
      "selected" => "true"
    })

    assert has_element?(view, role_selector(active_role, "[checked]"))
    assert has_element?(view, "input[name='roleCodes[]'][value='#{active_role.role_key}']")

    view
    |> form("#user-form", %{"nickname" => "已替换角色"})
    |> render_submit()

    assert target_role_ids(target) == [active_role.role_id]
    assert Repo.get!(SysUser, target.user_id).role_id == active_role.role_id
  end

  defp create_actor do
    role =
      create_role("disabled_role_actor", 1, [
        "user:read",
        "user:update",
        "role:read",
        "role:assign"
      ])

    {:ok, actor} = create_user(%{"role_id" => role.role_id})
    actor
  end

  defp create_role(prefix, status, permissions \\ []) do
    role =
      %SysRole{}
      |> SysRole.changeset(%{
        role_name: unique(prefix),
        role_key: unique(prefix <> "_key"),
        role_sort: 1,
        data_scope: "ALL",
        dept_id_set: "",
        status: status
      })
      |> Repo.insert!()

    Enum.each(permissions, fn permission ->
      entry = Repo.get_by!(SysPermission, permission: permission)

      Repo.insert!(%SysRolePermission{
        role_id: role.role_id,
        permission_id: entry.permission_id
      })
    end)

    PolicyCache.invalidate()
    role
  end

  defp create_user(attrs) do
    attrs =
      Map.merge(
        %{
          "username" => unique("disabled_role_user"),
          "nickname" => "停用角色测试用户",
          "password" => "Strong!123",
          "status" => 1
        },
        attrs
      )

    user =
      %SysUser{}
      |> SysUser.create_changeset(attrs)
      |> Repo.insert!()

    {:ok, user}
  end

  defp target_role_ids(user) do
    user.user_id
    |> RoleMembership.list_role_ids_for_user()
    |> Enum.sort()
  end

  defp role_selector(role, suffix),
    do: "input[type='checkbox'][phx-value-role-code='#{role.role_key}']#{suffix}"

  defp disabled_role_selector(role, suffix), do: role_selector(role, suffix)
end
