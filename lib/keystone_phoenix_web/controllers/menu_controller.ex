defmodule KeystonePhoenixWeb.MenuController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate, admin: true

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

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(10001, "找不到请求的菜单"))
  end
end
