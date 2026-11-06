defmodule KeystonePhoenixWeb.MenuController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list: "system:menu:list",
      show: "system:menu:query",
      create: "system:menu:add",
      update: "system:menu:edit",
      delete: "system:menu:remove"
    }

  alias KeystonePhoenix.Menu
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns the menu and permission list."
  def list(conn, params) do
    json(conn, ApiResponse.ok(Menu.list_menus(params)))
  end

  @doc "Returns a menu."
  def show(conn, %{"menu_id" => menu_id}) do
    case Menu.get_menu(menu_id) do
      {:ok, menu} -> json(conn, ApiResponse.ok(Menu.menu_to_map(menu)))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  @doc "Returns the menu dropdown source."
  def dropdown(conn, _params) do
    json(conn, ApiResponse.ok(Menu.list_dropdown()))
  end

  @doc "Creates a menu or button permission."
  def create(conn, params) do
    case Menu.create_menu(params, conn.assigns.current_user.user_id) do
      {:ok, _menu} -> conn |> put_status(:created) |> json(ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Updates a menu or button permission."
  def update(conn, %{"menu_id" => menu_id} = params) do
    case Menu.update_menu(menu_id, params, conn.assigns.current_user.user_id) do
      {:ok, _menu} -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Soft deletes a menu or button permission."
  def delete(conn, %{"menu_id" => menu_id}) do
    case Menu.delete_menu(menu_id, conn.assigns.current_user.user_id) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(10001, "找不到请求的菜单"))
  end

  defp render_error(conn, reason)
       when reason in [
              :parent_not_found,
              :invalid_parent,
              :name_exists,
              :has_children,
              :assigned_to_role,
              :menu_type_locked,
              :button_parent_invalid,
              :menu_parent_invalid,
              :external_link_invalid
            ] do
    messages = %{
      parent_not_found: "父菜单不存在",
      invalid_parent: "父菜单无效",
      name_exists: "同级菜单名称已存在",
      has_children: "菜单存在子菜单，不能删除",
      assigned_to_role: "菜单已分配给角色，不能删除",
      menu_type_locked: "非按钮菜单不能修改菜单类型",
      button_parent_invalid: "内嵌或外链菜单下不能创建按钮",
      menu_parent_invalid: "只有目录菜单下可以创建子菜单",
      external_link_invalid: "外链菜单地址必须使用 HTTP 或 HTTPS"
    }

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(10002, Map.fetch!(messages, reason)))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(99999, "参数校验失败", errors))
  end
end
