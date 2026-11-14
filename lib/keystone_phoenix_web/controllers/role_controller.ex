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
      permissions: "role:manage",
      users: "role:read",
      allocated_users: "role:read",
      unallocated_users: "role:read",
      assign_users: "role:assign",
      revoke_users: "role:assign",
      unassign_users: "role:update"
    }

  plug KeystonePhoenixWeb.Plugs.RequireResourceScope, resource: :role

  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Role.Permissions
  alias KeystonePhoenixWeb.ApiResponse
  alias KeystonePhoenixWeb.ExcelResponse

  @role_export_headers ["角色ID", "角色名称", "角色标识", "角色排序", "角色状态", "备注", "创建时间", "数据范围"]

  @doc "Returns a paginated list of roles."
  def list(conn, params) do
    case Role.list_roles(params, authorization: %{principal: conn.assigns.current_user}) do
      {:ok, rows} -> json(conn, ApiResponse.ok(rows))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Exports all roles matching the current filters."
  def export(conn, params) do
    authorization = [authorization: %{principal: conn.assigns.current_user}]

    case Role.Authorization.authorize_read(authorization, "role:export") do
      :ok ->
        case Excel.all_rows_result(
               export_fetcher(&Role.list_roles_for_export/2, authorization),
               params
             ) do
          {:ok, rows} ->
            ExcelResponse.send_xlsx(
              conn,
              "roles.xlsx",
              @role_export_headers,
              Enum.map(rows, &role_export_row/1)
            )

          {:error, reason} ->
            render_error(conn, reason)
        end

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  defp export_fetcher(fetcher, authorization) do
    fn params ->
      case fetcher.(params, authorization) do
        {:ok, page} -> {:ok, page}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "Returns a role."
  def show(conn, %{"role_id" => role_id}) do
    authorization = [authorization: %{principal: conn.assigns.current_user}]

    with {:ok, role} <- Role.get_role(role_id, authorization),
         {:ok, menu_ids} <- Role.menu_ids_for_role(role.role_id, authorization),
         {:ok, permissions} <- Permissions.list_for_role(role.role_id, authorization) do
      data =
        role
        |> Role.role_to_map()
        |> Map.merge(%{
          "menuIds" => menu_ids,
          "selectedMenuList" => menu_ids,
          "permissions" => permissions,
          "selectedDeptList" => Role.dept_ids_for_role(role)
        })

      json(conn, ApiResponse.ok(data))
    else
      {:error, :not_found} ->
        render_error(conn, :not_found)

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @doc "Creates a role and assigns its display menus and explicit permissions."
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

  @doc "Updates a role and optionally replaces its display menus and explicit permissions."
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
  def delete(conn, %{"role_ids" => role_ids}) do
    delete_roles(conn, role_ids)
  end

  def delete(conn, %{"ids" => ids}), do: delete_roles(conn, ids)

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

  defp delete_roles(conn, role_ids) do
    case Role.delete_roles(String.split(to_string(role_ids), ","),
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "role:delete"
           }
         ) do
      {:ok, deleted} -> json(conn, ApiResponse.ok(%{"deleted" => deleted}))
      {:error, :invalid_ids} -> render_error(conn, :invalid_role_ids)
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
           },
           permission: "role:manage"
         ) do
      {:ok, _role} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Replaces a role's explicit permission bindings."
  def permissions(conn, %{"role_id" => role_id} = params) do
    case Role.update_role(
           role_id,
           %{"permissions" => params["permissions"] || params[:permissions]},
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "role:manage"
           },
           permission: "role:manage"
         ) do
      {:ok, _role} -> json(conn, ApiResponse.ok(%{"updated" => true}))
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Lists users assigned to a role."
  def users(conn, %{"role_id" => _role_id} = params) do
    if to_string(params["allocated"] || "true") in ["false", "0"] do
      unallocated_users(conn, params)
    else
      allocated_users(conn, params)
    end
  end

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
  def assign_users(conn, %{"role_id" => role_id} = params) do
    user_ids = params["userIds"] || params["user_ids"]

    if is_nil(user_ids) do
      render_error(conn, :invalid_ids)
    else
      assign_users_to_role(conn, role_id, user_ids)
    end
  end

  def assign_users(conn, _params), do: render_error(conn, :invalid_ids)

  defp assign_users_to_role(conn, role_id, user_ids) do
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

  @doc "Removes role assignments from users."
  def revoke_users(conn, %{"role_id" => _role_id} = params) do
    user_ids = params["userIds"] || params["user_ids"]

    if is_nil(user_ids) do
      render_error(conn, :invalid_ids)
    else
      unassign_users(conn, %{"user_ids" => user_ids})
    end
  end

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
      # 混合目标由领域层整体回滚，并按不存在目标返回稳定的 HTTP 错误。
      {:error, :not_found} -> render_error(conn, :not_found)
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
    |> json(ApiResponse.error(:validation_failed, "找不到请求的角色"))
  end

  defp render_error(conn, reason) when reason in [:protected_role, :has_users] do
    message = if reason == :protected_role, do: "管理员角色不能删除", else: "角色存在用户，不能删除"

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, message))
  end

  defp render_error(conn, :role_unavailable) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "角色已停用"))
  end

  defp render_error(conn, :forbidden) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:permission_denied, "需要管理员权限"))
  end

  defp render_error(conn, :permission_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:permission_denied, "没有操作权限"))
  end

  defp render_error(conn, :data_scope_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:data_scope_denied, "没有数据权限"))
  end

  defp render_error(conn, :authorization_required) do
    conn
    |> put_status(:unauthorized)
    |> json(ApiResponse.error(:authentication_required, "需要登录"))
  end

  defp render_error(conn, :menu_not_found) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "菜单不存在"))
  end

  defp render_error(conn, :permission_not_found) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "权限不存在或已停用"))
  end

  defp render_error(conn, :invalid_ids) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "用户编号无效"))
  end

  defp render_error(conn, :invalid_role_ids) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "角色编号无效"))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "参数校验失败", errors))
  end
end
