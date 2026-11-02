defmodule KeystonePhoenixWeb.UserController do
  use KeystonePhoenixWeb, :controller

  alias KeystonePhoenix.User
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns a paginated list of users."
  def list(conn, params) do
    json(conn, ApiResponse.ok(User.list_users(params)))
  end

  @doc "Returns a user without exposing its password."
  def show(conn, %{"user_id" => user_id}) do
    case User.get_user(user_id) do
      {:ok, user} -> json(conn, ApiResponse.ok(User.user_to_map(user)))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(10001, "找不到请求的用户"))
  end
end
