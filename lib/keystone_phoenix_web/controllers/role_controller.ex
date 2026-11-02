defmodule KeystonePhoenixWeb.RoleController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate, admin: true

  alias KeystonePhoenix.Role
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns a paginated list of roles."
  def list(conn, params) do
    json(conn, ApiResponse.ok(Role.list_roles(params)))
  end

  @doc "Returns a role."
  def show(conn, %{"role_id" => role_id}) do
    case Role.get_role(role_id) do
      {:ok, role} ->
        data = Role.role_to_map(role) |> Map.put("menuIds", Role.menu_ids_for_role(role.role_id))
        json(conn, ApiResponse.ok(data))

      {:error, :not_found} ->
        render_error(conn, :not_found)
    end
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(10001, "找不到请求的角色"))
  end
end
