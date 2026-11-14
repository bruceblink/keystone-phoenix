defmodule KeystonePhoenixWeb.MenuController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list: "menu:read",
      dropdown: "menu:read",
      assign_roles: "menu:manage",
      create: "menu:create",
      update: "menu:update",
      delete: "menu:delete"
    }

  plug KeystonePhoenixWeb.Plugs.RequireResourceScope, resource: :menu

  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Authz
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns the menu and permission list."
  def list(conn, params) do
    case Menu.list_menus(params, authorization: %{principal: conn.assigns.current_user}) do
      {:ok, rows} -> json(conn, ApiResponse.ok(rows))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Returns the menu dropdown source."
  def dropdown(conn, _params) do
    case Menu.list_dropdown(authorization: %{principal: conn.assigns.current_user}) do
      {:ok, rows} -> json(conn, ApiResponse.ok(rows))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Replaces the role codes assigned to a menu."
  def assign_roles(conn, %{"menu_id" => menu_id, "roleCodes" => role_codes})
      when is_list(role_codes) do
    case Menu.RoleAssignment.replace(menu_id, role_codes,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      :ok -> json(conn, ApiResponse.ok(%{"updated" => true}))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def assign_roles(conn, _params), do: render_error(conn, :invalid_role_codes)

  @doc "Creates a menu or button permission."
  def create(conn, params) do
    if Authz.menu_metadata_allowed?(conn.assigns.current_user, params) do
      case Menu.create_menu(params,
             authorization: %{
               principal: conn.assigns.current_user,
               permission: "menu:create"
             }
           ) do
        {:ok, _menu} -> conn |> put_status(:created) |> json(ApiResponse.ok())
        {:error, reason} -> render_error(conn, reason)
      end
    else
      render_error(conn, :permission_denied)
    end
  end

  @doc "Updates a menu or button permission."
  def update(conn, %{"menu_id" => menu_id} = params) do
    if Authz.menu_metadata_allowed?(conn.assigns.current_user, params) do
      case Menu.update_menu(menu_id, params,
             authorization: %{
               principal: conn.assigns.current_user,
               permission: "menu:update"
             }
           ) do
        {:ok, _menu} -> json(conn, ApiResponse.ok())
        {:error, reason} -> render_error(conn, reason)
      end
    else
      render_error(conn, :permission_denied)
    end
  end

  @doc "Soft deletes a menu or button permission."
  def delete(conn, %{"menu_id" => menu_id}) do
    case Menu.delete_menu(menu_id,
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "menu:delete"
           }
         ) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(:validation_failed, "找不到请求的菜单"))
  end

  defp render_error(conn, :permission_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:permission_denied, "没有操作权限"))
  end

  defp render_error(conn, :data_scope_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:data_scope_denied, "没有数据权限"))
  end

  defp render_error(conn, reason) when reason in [:invalid_role_codes, :role_not_found] do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "角色编码无效"))
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
    |> json(ApiResponse.error(:validation_failed, Map.fetch!(messages, reason)))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "参数校验失败", errors))
  end
end
