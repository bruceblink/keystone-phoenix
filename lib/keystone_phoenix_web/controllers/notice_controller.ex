defmodule KeystonePhoenixWeb.NoticeController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list: "system:notice:list",
      show: "system:notice:query",
      create: "system:notice:add",
      update: "system:notice:edit",
      delete: "system:notice:remove"
    }

  alias KeystonePhoenix.Notice
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns a paginated list of notices."
  def list(conn, params) do
    json(conn, ApiResponse.ok(Notice.list_notices(params)))
  end

  @doc "Returns a notice."
  def show(conn, %{"notice_id" => notice_id}) do
    case Notice.get_notice(notice_id) do
      {:ok, notice} -> json(conn, ApiResponse.ok(Notice.notice_to_map(notice)))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  @doc "Creates a notice."
  def create(conn, params) do
    case Notice.create_notice(params) do
      {:ok, _notice} -> conn |> put_status(:created) |> json(ApiResponse.ok())
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Updates a notice."
  def update(conn, %{"notice_id" => notice_id} = params) do
    case Notice.update_notice(notice_id, params) do
      {:ok, _notice} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Soft deletes notices."
  def delete(conn, %{"notice_ids" => notice_ids}) do
    case Notice.delete_notices(String.split(notice_ids, ",")) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, :invalid_ids} -> render_error(conn, :invalid_ids)
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  def delete(conn, _params), do: render_error(conn, :invalid_ids)

  defp render_error(conn, :not_found) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(10001, "找不到请求的公告"))
  end

  defp render_error(conn, :invalid_ids) do
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(10002, "公告编号无效"))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    conn |> put_status(:unprocessable_entity) |> json(ApiResponse.error(99999, "参数校验失败", errors))
  end
end
