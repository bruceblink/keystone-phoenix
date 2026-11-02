defmodule KeystonePhoenixWeb.PostController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate, admin: true

  alias KeystonePhoenix.Post
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns a paginated list of posts."
  def list(conn, params) do
    json(conn, ApiResponse.ok(Post.list_posts(params)))
  end

  @doc "Returns a post."
  def show(conn, %{"post_id" => post_id}) do
    case Post.get_post(post_id) do
      {:ok, post} -> json(conn, ApiResponse.ok(Post.post_to_map(post)))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(10001, "找不到请求的岗位"))
  end
end
