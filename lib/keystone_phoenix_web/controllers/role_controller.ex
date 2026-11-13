defmodule KeystonePhoenixWeb.RoleController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list: "role:read",
      export: "role:export",
      show: "role:read",
      create: "role:create",
      update: "role:update",
      delete: "role:delete",
      change_status: "role:update",
      data_scope: "role:manage",
      allocated_users: "role:read",
      unallocated_users: "role:read",
      assign_users: "role:update",
      unassign_users: "role:update"
    }

  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Role
  alias KeystonePhoenixWeb.ApiResponse
  alias KeystonePhoenixWeb.ExcelResponse

  @role_export_headers ["角色ID", "角色名称", "角色标识", "角色排序", "角色状态", "备注", "创建时间", "数据范围"]

  @doc "Returns a paginated list of roles."
  def list(conn, params) do
    json(conn, ApiResponse.ok(Role.list_roles(params)))
  end

  @doc "Exports all roles matching the current filters."
  def export(conn, params) do
    rows = Excel.all_rows(&Role.list_roles/1, params)

    ExcelResponse.send_xlsx(
      conn,
      "roles.xlsx",
      @role_export_headers,
      Enum.map(rows, &role_export_row/1)
    )
  end

  @doc "Returns a role."
  def show(conn, %{"role_id" => role_id}) do
    case Role.get_role(role_id) do
      {:ok, role} ->
        menu_ids = Role.menu_ids_for_role(role.role_id)

        data =
          role
          |> Role.role_to_map()
          |> Map.merge(%{
            "menuIds" => menu_ids,
            "selectedMenuList" => menu_ids,
            "selectedDeptList" => Role.dept_ids_for_role(role)
          })

        json(conn, ApiResponse.ok(data))

      {:error, :not_found} ->
        render_error(conn, :not_found)
    end
  end

  @doc "Creates a role and assigns its menus."
  def create(conn, params) do
    if Authz.role_metadata_allowed?(conn.assigns.current_user, params) do
      case Role.create_role(params,
             authorization: %{
               principal: conn.assigns.current_user,
               permission: "role:create"
             }
           ) do
        {:ok, _role} -> conn |> put_status(:created) |> json(ApiResponse.ok())
        {:error, changeset} -> render_error(conn, changeset)
      end
    else
      render_error(conn, :permission_denied)
    end
  end

  @doc "Updates a role and optionally replaces its menu assignments."
  def update(conn, params) do
    if Authz.role_metadata_allowed?(conn.assigns.current_user, params) do
      case Role.update_role(
             params["roleId"] || params[:role_id],
             params,
             authorization: %{
               principal: conn.assigns.current_user,
               permission: "role:update"
             }
           ) do
        {:ok, _role} -> json(conn, ApiResponse.ok())
        {:error, :not_found} -> render_error(conn, :not_found)
        {:error, changeset} -> render_error(conn, changeset)
      end
    else
      render_error(conn, :permission_denied)
    end
  end

  @doc "Soft deletes a role."
  def delete(conn, %{"role_id" => role_id}) do
    case Role.delete_role(role_id,
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "role:delete"
           }
         ) do
      {:ok, _} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Changes a role's enabled status."
  def change_status(conn, %{"role_id" => role_id} = params) do
    case Role.change_status(
           role_id,
           params["status"] || params[:status],
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "role:update"
           }
         ) do
      {:ok, _role} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Changes a role's data scope and department set."
  def data_scope(conn, %{"role_id" => role_id} = params) do
    case Role.update_data_scope(role_id, params,
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "role:manage"
           }
         ) do
      {:ok, _role} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Lists users assigned to a role."
  def allocated_users(conn, %{"role_id" => role_id} = params) do
    json(
      conn,
      ApiResponse.ok(Role.list_allocated_users(role_id, params, conn.assigns.current_user))
    )
  end

  @doc "Lists users that are not assigned to a role."
  def unallocated_users(conn, %{"role_id" => role_id} = params) do
    json(
      conn,
      ApiResponse.ok(Role.list_unallocated_users(role_id, params, conn.assigns.current_user))
    )
  end

  @doc "Assigns users to a role."
  def assign_users(conn, %{"role_id" => role_id, "user_ids" => user_ids}) do
    case Role.assign_users(role_id, user_ids,
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "role:update"
           }
         ) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def assign_users(conn, _params), do: render_error(conn, :invalid_ids)

  @doc "Removes role assignments from users."
  def unassign_users(conn, %{"user_ids" => user_ids}) do
    case Role.unassign_users(user_ids,
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "role:update"
           }
         ) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, :forbidden} -> render_error(conn, :forbidden)
      {:error, :invalid_ids} -> render_error(conn, :invalid_ids)
    end
  end

  def unassign_users(conn, _params), do: render_error(conn, :invalid_ids)

  defp role_export_row(row) do
    [
      row["roleId"],
      row["roleName"],
      row["roleKey"],
      row["roleSort"],
      row["status"],
      row["remark"],
      row["createTime"],
      row["dataScope"]
    ]
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(10001, "找不到请求的角色"))
  end

  defp render_error(conn, reason) when reason in [:protected_role, :has_users] do
    message = if reason == :protected_role, do: "管理员角色不能删除", else: "角色存在用户，不能删除"
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10002, message))
  end

  defp render_error(conn, :role_unavailable) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10003, "角色已停用"))
  end

  defp render_error(conn, :forbidden) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(40301, "需要管理员权限"))
  end

  defp render_error(conn, :permission_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(40302, "没有操作权限"))
  end

  defp render_error(conn, :menu_not_found) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10005, "菜单不存在"))
  end

  defp render_error(conn, :invalid_ids) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10004, "用户编号无效"))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(99999, "参数校验失败", errors))
  end
end
