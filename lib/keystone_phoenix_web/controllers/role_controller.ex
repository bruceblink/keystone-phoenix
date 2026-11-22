defmodule KeystonePhoenixWeb.RoleController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list: "role:read",
      export: "role:export",
      create: "role:create",
      update: "role:update",
      delete: "role:delete",
      permissions: "role:manage",
      users: "role:read",
      allocated_users: "role:read",
      unallocated_users: "role:read",
      assign_users: "role:assign",
      revoke_users: "role:assign",
      unassign_users: "role:assign"
    }

  # 角色和角色成员写操作改变授权结果，必须使用 AAL2 会话。
  plug KeystonePhoenixWeb.Plugs.RequireMfaStepUp
       when action in [:create, :update, :delete, :permissions, :assign_users, :revoke_users]

  plug KeystonePhoenixWeb.Plugs.RequireResourceScope, resource: :role

  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Role.NativeQuery
  alias KeystonePhoenix.Role.Permissions
  alias KeystonePhoenixWeb.ApiResponse
  alias KeystonePhoenixWeb.ExcelResponse
  alias KeystonePhoenixWeb.NativeContract

  @role_export_headers ["角色ID", "角色名称", "角色标识", "角色排序", "角色状态", "备注", "创建时间", "数据范围"]
  @max_pagination_value 2_147_483_647

  @doc "按 Native 约定返回角色数组或分页结果。"
  def list(conn, params) do
    query_params = role_query_params(params)
    paged? = NativeContract.pagination_requested?(params)

    result =
      if paged? do
        Role.list_roles(query_params, authorization: %{principal: conn.assigns.current_user})
      else
        NativeQuery.list_all(query_params, authorization: %{principal: conn.assigns.current_user})
      end

    case result do
      {:ok, page} ->
        payload =
          if paged?,
            do: NativeContract.roles_page(page, query_params),
            else: Enum.map(page, &native_role_map/1)

        json(conn, ApiResponse.ok(payload))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  # Native 使用 keyword/status，领域层继续使用 roleName/status 查询字段。
  defp role_query_params(params) do
    params
    |> NativeContract.pagination_params()
    |> Map.put_new("pageNum", "1")
    |> Map.put_new("pageSize", "20")
    |> maybe_copy_role_keyword()
    |> maybe_copy_role_status()
  end

  defp maybe_copy_role_keyword(params) do
    keyword = params["keyword"] || params["roleKeyword"]

    if is_nil(params["roleName"]) and is_binary(keyword),
      do: Map.put(params, "roleName", keyword),
      else: params
  end

  defp maybe_copy_role_status(params) do
    status = params["roleStatus"]

    if is_nil(params["status"]) and is_binary(status) and status not in ["", "all"],
      do: Map.put(params, "status", status),
      else: params
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

  @doc "Creates a role and assigns its display menus and explicit permissions."
  def create(conn, params) do
    attrs = NativeContract.role_params(params)

    if Authz.role_metadata_allowed?(conn.assigns.current_user, attrs) do
      case Role.create_role(attrs,
             authorization: %{
               principal: conn.assigns.current_user,
               permission: "role:create"
             }
           ) do
        {:ok, role} -> conn |> put_status(:created) |> json(ApiResponse.ok(native_role(role)))
        {:error, changeset} -> render_error(conn, changeset)
      end
    else
      render_error(conn, :permission_denied)
    end
  end

  @doc "Updates a role and optionally replaces its display menus and explicit permissions."
  def update(conn, params) do
    attrs = NativeContract.role_params(params)

    if Authz.role_metadata_allowed?(conn.assigns.current_user, attrs) do
      case Role.update_role(
             params["role_id"],
             attrs,
             authorization: %{
               principal: conn.assigns.current_user,
               permission: "role:update"
             }
           ) do
        {:ok, role} -> json(conn, ApiResponse.ok(native_role(role)))
        {:error, :not_found} -> render_error(conn, :not_found)
        {:error, changeset} -> render_error(conn, changeset)
      end
    else
      render_error(conn, :permission_denied)
    end
  end

  @doc "Soft deletes a role."
  def delete(conn, %{"ids" => ids}), do: delete_roles(conn, ids)

  def delete(conn, %{"role_id" => role_id}) do
    case Role.delete_role(role_id,
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "role:delete"
           }
         ) do
      {:ok, _} -> json(conn, ApiResponse.ok(%{"deleted" => true}))
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def delete(conn, _params), do: render_error(conn, :invalid_role_ids)

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
    with {:ok, _role} <- Role.get_role(role_id) do
      case role_users(role_id, params, conn.assigns.current_user, &Role.list_allocated_users/3) do
        {:ok, users} -> json(conn, ApiResponse.ok(users))
        {:error, reason} -> render_error(conn, reason)
      end
    else
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  @doc "Lists users that are not assigned to a role."
  def unallocated_users(conn, %{"role_id" => role_id} = params) do
    with {:ok, _role} <- Role.get_role(role_id) do
      case role_users(
             role_id,
             params,
             conn.assigns.current_user,
             &Role.list_unallocated_users/3
           ) do
        {:ok, users} -> json(conn, ApiResponse.ok(users))
        {:error, reason} -> render_error(conn, reason)
      end
    else
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  @doc "Assigns users to a role."
  def assign_users(conn, %{"role_id" => role_id, "userIds" => user_ids}) do
    assign_users_to_role(conn, role_id, user_ids)
  end

  def assign_users(conn, _params), do: render_error(conn, :invalid_ids)

  defp assign_users_to_role(conn, role_id, user_ids) do
    case Role.assign_users(role_id, user_ids,
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "role:assign"
           }
         ) do
      :ok -> json(conn, ApiResponse.ok(%{"updated" => true}))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Removes role assignments from users."
  def revoke_users(conn, %{"role_id" => role_id, "userIds" => user_ids}) do
    revoke_users_from_role(conn, role_id, user_ids)
  end

  def revoke_users(conn, _params), do: render_error(conn, :invalid_ids)

  defp revoke_users_from_role(conn, role_id, user_ids) do
    case Role.unassign_users(role_id, user_ids,
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "role:assign"
           }
         ) do
      :ok -> json(conn, ApiResponse.ok(%{"updated" => true}))
      {:error, :forbidden} -> render_error(conn, :forbidden)
      {:error, :invalid_ids} -> render_error(conn, :invalid_ids)
      # 混合目标由领域层整体回滚，并按不存在目标返回稳定的 HTTP 错误。
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  defp native_role(role) do
    role
    |> Role.role_to_map()
    |> Map.put("permissions", Permissions.list(role.role_id))
    |> NativeContract.role()
  end

  defp native_role_map(row) do
    row
    |> Map.put("permissions", Permissions.list(row["roleId"]))
    |> NativeContract.role()
  end

  # 新分页参数返回一页；旧参数继续触发有界分批读取并保留数组响应。
  defp role_users(role_id, params, actor, fetch_page) do
    if role_users_pagination_requested?(params) do
      paged_role_users(role_id, params, actor, fetch_page)
    else
      all_role_users(role_id, params, actor, fetch_page)
    end
  end

  defp paged_role_users(role_id, params, actor, fetch_page) do
    page = pagination_value(params, "page", 1)
    size = pagination_value(params, "size", 20) |> min(100)

    query_params =
      params
      |> Map.put("pageNum", page)
      |> Map.put("pageSize", size)

    case fetch_page.(role_id, query_params, actor) do
      %{rows: rows, total: total} ->
        {:ok,
         %{
           items: role_user_items(rows, params),
           page: page,
           size: size,
           total: total
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp all_role_users(role_id, params, actor, fetch_page) do
    case Excel.all_rows_result(
           fn page_params -> fetch_page.(role_id, page_params, actor) end,
           params
         ) do
      {:ok, rows} -> {:ok, role_user_items(rows, params)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp role_user_items(rows, %{"include" => "identity"}), do: rows
  defp role_user_items(rows, _params), do: NativeContract.role_user_ids(rows)

  defp role_users_pagination_requested?(params),
    do:
      Map.has_key?(params, "page") or Map.has_key?(params, :page) or
        Map.has_key?(params, "size") or Map.has_key?(params, :size)

  defp pagination_value(params, key, default) do
    if Map.has_key?(params, key) or Map.has_key?(params, pagination_atom(key)),
      do: normalized_positive_integer(param(params, key), 1),
      else: default
  end

  defp param(params, "page"), do: Map.get(params, "page", Map.get(params, :page))
  defp param(params, "size"), do: Map.get(params, "size", Map.get(params, :size))
  defp pagination_atom("page"), do: :page
  defp pagination_atom("size"), do: :size

  defp normalized_positive_integer(value, _default)
       when is_integer(value) and value > 0 and value <= @max_pagination_value,
       do: value

  defp normalized_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 and number <= @max_pagination_value -> number
      _ -> default
    end
  end

  defp normalized_positive_integer(_value, default), do: default

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
    |> json(ApiResponse.error(:resource_not_found, "找不到请求的角色"))
  end

  # 保留角色删除现有 422 状态，只将两个阻止条件映射到不同代码。
  defp render_error(conn, :protected_role) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:role_protected, "管理员角色不能删除"))
  end

  defp render_error(conn, :has_users) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:role_has_members, "角色存在用户，不能删除"))
  end

  defp render_error(conn, :role_unavailable) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:resource_conflict, "角色已停用"))
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
    |> json(ApiResponse.error(:permission_not_found, "权限不存在或已停用"))
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
