defmodule KeystonePhoenixWeb.NoticeController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
    permissions: %{
      list: "notice:read",
      show: "notice:read",
      create: "notice:create",
      update: "notice:update",
      delete: "notice:delete"
    }

  plug KeystonePhoenixWeb.Plugs.RequireResourceScope, resource: :notice, defer_owner: true

  plug KeystonePhoenixWeb.Plugs.NoRepeat, [interval: 60] when action in [:create]

  alias KeystonePhoenix.Notice
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns a paginated list of notices."
  def list(conn, params) do
    case Notice.list_notices(params, authorization: %{principal: conn.assigns.current_user}) do
      {:ok, rows} -> json(conn, ApiResponse.ok(rows))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Returns a notice."
  def show(conn, %{"notice_id" => notice_id}) do
    case Notice.get_notice(notice_id, authorization: %{principal: conn.assigns.current_user}) do
      {:ok, notice} -> json(conn, ApiResponse.ok(Notice.notice_to_map(notice)))
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Creates a notice."
  def create(conn, params) do
    case Notice.create_notice(params, authorization: %{principal: conn.assigns.current_user}) do
      {:ok, _notice} -> conn |> put_status(:created) |> json(ApiResponse.ok())
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Updates a notice."
  def update(conn, %{"notice_id" => notice_id} = params) do
    case Notice.update_notice(notice_id, params,
           authorization: %{principal: conn.assigns.current_user}
         ) do
      {:ok, _notice} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Soft deletes notices."
  def delete(conn, %{"notice_ids" => notice_ids}) do
    delete_notices(conn, notice_ids)
  end

  def delete(conn, %{"ids" => ids}), do: delete_notices(conn, ids)

  def delete(conn, %{"notice_id" => notice_id}), do: delete_notices(conn, notice_id)

  def delete(conn, _params), do: render_error(conn, :invalid_ids)

  defp delete_notices(conn, notice_ids) do
    case Notice.delete_notices(String.split(notice_ids, ","),
           authorization: %{principal: conn.assigns.current_user}
         ) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, :invalid_ids} -> render_error(conn, :invalid_ids)
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  defp render_error(conn, :not_found) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(:validation_failed, "找不到请求的公告"))
  end

  defp render_error(conn, :invalid_ids) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "公告编号无效"))
  end

  defp render_error(conn, :permission_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:permission_denied, "没有操作权限"))
  end

  defp render_error(conn, :data_scope_denied) do
    conn |> put_status(:forbidden) |> json(ApiResponse.error(:data_scope_denied, "没有数据权限"))
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "参数校验失败", errors))
  end
end
