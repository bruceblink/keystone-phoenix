defmodule KeystonePhoenixWeb.DepartmentController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list: "system:dept:list",
      show: "system:dept:query",
      dropdown: "system:dept:list",
      create: "system:dept:add",
      update: "system:dept:edit",
      delete: "system:dept:remove"
    },
    data_scope: %{update: {:dept, "dept_id"}, delete: {:dept, "dept_id"}}

  plug KeystonePhoenixWeb.Plugs.Authenticate,
       [admin: true]
       when action in [:create, :update, :delete]

  alias KeystonePhoenix.Department
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns departments in display order."
  def list(conn, params) do
    json(conn, ApiResponse.ok(Department.list_depts(params)))
  end

  @doc "Returns a department."
  def show(conn, %{"dept_id" => dept_id}) do
    case Department.get_dept(dept_id) do
      {:ok, dept} -> json(conn, ApiResponse.ok(Department.dept_to_map(dept)))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  @doc "Returns the department dropdown source."
  def dropdown(conn, _params) do
    json(conn, ApiResponse.ok(Department.list_dropdown()))
  end

  @doc "Creates a department."
  def create(conn, params) do
    case Department.create_dept(params, conn.assigns.current_user.user_id) do
      {:ok, _dept} -> conn |> put_status(:created) |> json(ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Updates a department."
  def update(conn, %{"dept_id" => dept_id} = params) do
    case Department.update_dept(dept_id, params, conn.assigns.current_user.user_id) do
      {:ok, _dept} -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Soft deletes a department."
  def delete(conn, %{"dept_id" => dept_id}) do
    case Department.delete_dept(dept_id, conn.assigns.current_user.user_id) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, reason} -> render_error(conn, reason)
    end
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(10001, "找不到请求的部门"))
  end

  defp render_error(conn, reason)
       when reason in [
              :parent_not_found,
              :parent_disabled,
              :invalid_parent,
              :name_exists,
              :status_invalid,
              :has_children,
              :has_users,
              :update_failed
            ] do
    messages = %{
      parent_not_found: "父部门不存在",
      parent_disabled: "父部门已停用",
      invalid_parent: "父部门无效",
      name_exists: "同级部门名称已存在",
      status_invalid: "部门存在启用的子部门，不能停用",
      has_children: "部门存在子部门，不能删除",
      has_users: "部门存在用户，不能删除",
      update_failed: "部门更新失败"
    }

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(10002, Map.fetch!(messages, reason)))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(99999, "参数校验失败", errors))
  end
end
