defmodule KeystonePhoenixWeb.PostController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list: "system:post:list",
      export: "system:post:export",
      show: "system:post:query",
      create: "system:post:add",
      update: "system:post:edit",
      delete: "system:post:remove"
    }

  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Post
  alias KeystonePhoenixWeb.ApiResponse
  alias KeystonePhoenixWeb.ExcelResponse

  @post_export_headers ["岗位ID", "岗位编码", "岗位名称", "岗位排序", "备注", "状态", "创建时间"]

  @doc "Returns a paginated list of posts."
  def list(conn, params) do
    json(conn, ApiResponse.ok(Post.list_posts(params)))
  end

  @doc "Exports all posts matching the current filters."
  def export(conn, params) do
    rows = Excel.all_rows(&Post.list_posts/1, params)

    ExcelResponse.send_xlsx(
      conn,
      "posts.xlsx",
      @post_export_headers,
      Enum.map(rows, &post_export_row/1)
    )
  end

  @doc "Returns a post."
  def show(conn, %{"post_id" => post_id}) do
    case Post.get_post(post_id) do
      {:ok, post} -> json(conn, ApiResponse.ok(Post.post_to_map(post)))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  @doc "Creates a post."
  def create(conn, params) do
    case Post.create_post(params, conn.assigns.current_user.user_id) do
      {:ok, _post} -> conn |> put_status(:created) |> json(ApiResponse.ok())
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Updates a post."
  def update(conn, %{"post_id" => post_id} = params) do
    update_post(conn, post_id, params)
  end

  def update(conn, %{"postId" => post_id} = params) do
    update_post(conn, post_id, params)
  end

  def update(conn, _params), do: render_error(conn, :invalid_id)

  defp update_post(conn, post_id, params) do
    case Post.update_post(post_id, params, conn.assigns.current_user.user_id) do
      {:ok, _post} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Soft deletes posts."
  def delete(conn, %{"ids" => ids}) do
    case Post.delete_posts(String.split(ids, ","), conn.assigns.current_user.user_id) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, :invalid_ids} -> render_error(conn, :invalid_ids)
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, :has_users} -> render_error(conn, :has_users)
      {:error, :update_failed} -> render_error(conn, :update_failed)
    end
  end

  def delete(conn, _params), do: render_error(conn, :invalid_ids)

  defp post_export_row(row) do
    [
      row["postId"],
      row["postCode"],
      row["postName"],
      row["postSort"],
      row["remark"],
      status_label(row["status"]),
      row["createTime"]
    ]
  end

  defp status_label(1), do: "正常"
  defp status_label(0), do: "停用"
  defp status_label(status), do: to_string(status || "")

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(10001, "找不到请求的岗位"))
  end

  defp render_error(conn, :invalid_ids) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10002, "岗位编号无效"))
  end

  defp render_error(conn, :invalid_id), do: render_error(conn, :invalid_ids)

  defp render_error(conn, reason) when reason in [:has_users, :update_failed] do
    message = if reason == :has_users, do: "岗位存在用户，不能删除", else: "岗位更新失败"
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10003, message))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(99999, "参数校验失败", errors))
  end
end
