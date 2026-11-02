defmodule KeystonePhoenixWeb.DepartmentController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate, admin: true

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

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(10001, "找不到请求的部门"))
  end
end
