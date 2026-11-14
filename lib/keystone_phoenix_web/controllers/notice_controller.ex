defmodule KeystonePhoenixWeb.NoticeController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
       [
         permissions: %{
           manage_list: "notice:read",
           create: "notice:create",
           update: "notice:update",
           publish: "notice:update",
           delete: "notice:delete"
         }
       ]
       when action in [:manage_list, :create, :update, :publish, :delete]

  plug KeystonePhoenixWeb.Plugs.RequireResourceScope,
       [
         resource: :notice,
         defer_owner: true
       ]
       when action in [:manage_list, :create, :update, :publish, :delete]

  plug KeystonePhoenixWeb.Plugs.NoRepeat, [interval: 60] when action in [:create]

  alias KeystonePhoenix.Notice
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns published and enabled notices without authentication."
  def public_list(conn, _params) do
    json(conn, ApiResponse.ok(Notice.list_public_notices()))
  end

  @doc "Returns all notices in the current data scope using the Native DTO."
  def manage_list(conn, params) do
    case Notice.list_managed_notices(params, authorization(conn)) do
      {:ok, rows} -> json(conn, ApiResponse.ok(rows))
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "Creates a notice."
  def create(conn, params) do
    case Notice.create_notice(params, authorization(conn)) do
      {:ok, notice} ->
        conn
        |> put_status(:created)
        |> json(ApiResponse.ok(native_notice(conn, notice)))

      {:error, changeset} ->
        render_error(conn, changeset)
    end
  end

  @doc "Updates a notice."
  def update(conn, %{"notice_id" => notice_id} = params) do
    case Notice.update_notice(notice_id, params, authorization(conn)) do
      {:ok, notice} -> json(conn, ApiResponse.ok(native_notice(conn, notice)))
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Publishes or unpublishes a notice."
  def publish(conn, %{"notice_id" => notice_id, "published" => published})
      when is_boolean(published) do
    case Notice.publish_notice(notice_id, published, authorization(conn)) do
      {:ok, notice} -> json(conn, ApiResponse.ok(native_notice(conn, notice)))
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def publish(conn, _params), do: render_error(conn, :invalid_published)

  @doc "Soft deletes notices."
  def delete(conn, %{"notice_ids" => notice_ids}) do
    delete_notices(conn, notice_ids, false)
  end

  def delete(conn, %{"ids" => ids}), do: delete_notices(conn, ids, false)

  def delete(conn, %{"notice_id" => notice_id}), do: delete_notices(conn, notice_id, true)

  def delete(conn, _params), do: render_error(conn, :invalid_ids)

  defp delete_notices(conn, notice_ids, single?) do
    case Notice.delete_notices_count(String.split(notice_ids, ","), authorization(conn)) do
      {:ok, count} ->
        deleted = if(single?, do: true, else: count)
        json(conn, ApiResponse.ok(%{"deleted" => deleted}))

      {:error, :invalid_ids} ->
        render_error(conn, :invalid_ids)

      {:error, :not_found} ->
        render_error(conn, :not_found)

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  defp authorization(conn), do: [authorization: %{principal: conn.assigns.current_user}]

  defp native_notice(conn, notice) do
    principal = conn.assigns[:current_user] || %{}
    name = Map.get(principal, :username) || Map.get(principal, "username") || notice.creator_id
    Notice.native_notice_to_map(notice, %{notice.creator_id => name})
  end

  defp render_error(conn, :not_found) do
    conn |> put_status(:not_found) |> json(ApiResponse.error(:validation_failed, "找不到请求的公告"))
  end

  defp render_error(conn, :invalid_ids) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "公告编号无效"))
  end

  defp render_error(conn, :invalid_published) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "published 必须是布尔值"))
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

  defp render_error(conn, _reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "参数校验失败"))
  end
end
