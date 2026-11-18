defmodule KeystonePhoenixWeb.AdminMenuRoleRetryTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.{Identity, Menu, Repo, Role}
  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.User.SysUser

  setup do
    role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: unique("菜单恢复管理员"),
        role_key: unique("menu_retry_admin"),
        role_sort: 1,
        data_scope: "ALL",
        dept_id_set: "",
        status: 1
      })
      |> Repo.insert!()

    for permission <- Repo.all(SysPermission) do
      Repo.insert!(%SysRolePermission{
        role_id: role.role_id,
        permission_id: permission.permission_id
      })
    end

    user =
      Repo.insert!(%SysUser{
        user_id: Identity.v7(),
        role_id: role.role_id,
        username: unique("menu_retry_admin"),
        password: Bcrypt.hash_pwd_salt("Strong!123"),
        status: 1
      })

    {:ok, user: user}
  end

  # 权限标识为可选字段；空值在创建时不绑定权限，编辑时清除原有绑定。
  test "blank permission creates a menu and clears an existing permission", %{
    conn: conn,
    user: user
  } do
    {:ok, existing} =
      Menu.create_menu(
        %{
          "code" => unique("permission_clear_menu"),
          "name" => "清除权限标识菜单",
          "menuType" => "MENU",
          "permission" => "menu:read",
          "enabled" => true
        },
        authorization: %{principal: user, permission: "menu:create"}
      )

    {:ok, view} = login(conn, user)
    render_click(view, "show-panel", %{"panel" => "menus"})

    create_code = unique("empty_permission_menu")

    render_submit(view, "save-menu", %{
      "menuId" => "",
      "code" => create_code,
      "name" => "无权限标识菜单",
      "menuType" => "MENU",
      "parentId" => "",
      "permission" => "  ",
      "enabled" => "true",
      "menuRoleCodes[]" => []
    })

    assert render(view) =~ "菜单已创建"
    created = Repo.get_by!(SysMenu, menu_code: create_code)
    assert Menu.menu_to_map(created)["permission"] == nil

    render_click(view, "edit-menu", %{"menu-id" => to_string(existing.menu_id)})

    render_submit(view, "save-menu", %{
      "menuId" => to_string(existing.menu_id),
      "code" => existing.menu_code,
      "name" => existing.menu_name,
      "menuType" => "MENU",
      "permission" => " \t ",
      "enabled" => "true",
      "menuRoleCodes[]" => []
    })

    assert render(view) =~ "菜单已更新"
    assert Menu.menu_to_map(Repo.get!(SysMenu, existing.menu_id))["permission"] == nil
  end

  # 菜单创建与角色绑定分步保存；绑定失败后，重试必须更新已创建的菜单。
  test "menu creation retry updates the saved menu after role binding fails", %{
    conn: conn,
    user: user
  } do
    menu_code = unique("retry_binding_menu")
    role_code = unique("menu_retry_role")
    role = insert_role(role_code)

    {:ok, view} = login(conn, user)
    render_click(view, "show-panel", %{"panel" => "menus"})

    params = menu_params(menu_code, "deleted_role_between_load_and_save")
    render_submit(view, "save-menu", params)

    assert Repo.query!("SELECT EXISTS (SELECT 1 FROM sys_menu WHERE menu_code = $1)", [menu_code]).rows ==
             [[true]]

    assert live_socket(view).assigns.active_modal == "menu"
    assert has_element?(view, "#menu-modal #menu-feedback", "所选角色不存在或已停用，请重新选择后重试")
    assert has_element?(view, "#menu-modal #menu-feedback", "错误码：resource_not_found")
    refute has_element?(view, ".menus-page > #menu-feedback")
    assert length(Regex.scan(~r/\bid="menu-feedback"/, render(view))) == 1
    saved_menu_id = live_socket(view).assigns.menu_form["menuId"]
    assert is_binary(saved_menu_id) and saved_menu_id != ""
    assert live_socket(view).assigns.menu_form["enabled"]

    params = params |> Map.put("menuId", saved_menu_id) |> Map.put("menuRoleCodes[]", [role_code])
    render_submit(view, "save-menu", params)

    assert render(view) =~ "菜单已更新"
    assert live_socket(view).assigns.active_modal == nil

    assert Repo.query!("SELECT COUNT(*) FROM sys_menu WHERE menu_code = $1", [menu_code]).rows ==
             [[1]]

    assert Enum.map(Role.menu_ids_for_role(role.role_id), &to_string/1) == [saved_menu_id]
  end

  defp insert_role(role_code) do
    %SysRole{role_id: Identity.v7()}
    |> SysRole.changeset(%{
      role_name: unique("可访问菜单角色"),
      role_key: role_code,
      role_sort: 2,
      data_scope: "ALL",
      dept_id_set: "",
      status: 1
    })
    |> Repo.insert!()
  end

  defp menu_params(menu_code, role_code) do
    %{
      "menuId" => "",
      "code" => menu_code,
      "name" => "待重试菜单",
      "menuType" => "MENU",
      "parentId" => "",
      "path" => "/retry-menu",
      "permission" => "menu:read",
      "enabled" => "true",
      "menuRoleCodes[]" => [role_code]
    }
  end

  defp login(conn, user) do
    {:ok, view, _html} = live(conn, "/")
    render_submit(view, "login", %{"username" => user.username, "password" => "Strong!123"})
    assert has_element?(view, "nav[aria-label='主导航']")
    {:ok, view}
  end

  defp live_socket(view), do: find_socket(:sys.get_state(view.pid))
  defp find_socket(%Phoenix.LiveView.Socket{} = socket), do: socket
  defp find_socket(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_socket/1)

  defp find_socket(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&find_socket/1)

  defp find_socket(list) when is_list(list), do: Enum.find_value(list, &find_socket/1)
  defp find_socket(_value), do: nil
  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
