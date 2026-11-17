defmodule KeystonePhoenixWeb.NotificationController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.RejectApiKey
  plug KeystonePhoenixWeb.Plugs.Authenticate

  alias KeystonePhoenix.Notification
  alias KeystonePhoenix.Params
  alias KeystonePhoenixWeb.ApiResponse

  @doc "返回当前人类用户的通知列表和完整未读数。"
  def index(conn, _params) do
    case Notification.list_for_user(current_user_id(conn)) do
      {:ok, inbox} ->
        json(
          conn,
          ApiResponse.ok(%{
            "items" => inbox.items,
            "unreadCount" => inbox.unread_count
          })
        )

      {:error, :service_unavailable} ->
        unavailable(conn)

      {:error, _reason} ->
        not_found(conn)
    end
  end

  @doc "返回当前用户指定的通知；不区分不存在和其他用户的通知。"
  def show(conn, %{"id" => id}) do
    with {:ok, id} <- Params.parse_uuid(id),
         {:ok, notification} <- Notification.get_for_user(current_user_id(conn), id) do
      json(conn, ApiResponse.ok(notification))
    else
      {:error, :service_unavailable} -> unavailable(conn)
      _ -> not_found(conn)
    end
  end

  @doc "将当前用户的通知标记为已读，并返回更新后的同一条记录。"
  def read(conn, %{"id" => id}) do
    with {:ok, id} <- Params.parse_uuid(id),
         {:ok, notification} <- Notification.mark_read(current_user_id(conn), id) do
      json(conn, ApiResponse.ok(notification))
    else
      {:error, :service_unavailable} -> unavailable(conn)
      _ -> not_found(conn)
    end
  end

  defp current_user_id(conn), do: conn.assigns.current_user.user_id

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(:resource_not_found, "找不到通知"))
  end

  defp unavailable(conn) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(:service_unavailable, "站内通知暂不可用"))
  end
end
