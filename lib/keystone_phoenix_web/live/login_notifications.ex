defmodule KeystonePhoenixWeb.LoginNotifications do
  @moduledoc "管理登录用户的私有站内通知收件箱。"

  import Phoenix.Component, only: [assign: 2]

  require Phoenix.LiveView

  alias KeystonePhoenix.Notification

  @async_name :user_notifications
  @load_error "站内通知暂时无法读取，请重试"
  @missing_error "通知不存在或已移除，请刷新后重试"

  @doc "切换通知弹层；打开时异步读取当前用户的收件箱。"
  def toggle(socket) do
    if socket.assigns.notifications_open, do: close(socket), else: load(socket)
  end

  @doc "重新读取当前用户收件箱，并清除上一次的详情和错误状态。"
  def retry(socket), do: load(socket)

  @doc "同步刷新当前用户的收件箱和未读数，供登录及通知写入后更新顶栏。"
  def refresh(socket) do
    socket = cancel_current_async(socket)
    user_id = current_user_id(socket)

    if is_binary(user_id) and user_id == socket.assigns.notifications_user_id do
      refresh_current_user(socket, user_id)
    else
      assign(socket,
        notifications_loading: false,
        notifications_async_name: nil,
        notifications_error: nil,
        notification_read_error: nil,
        notification_read_error_action: nil,
        notification_read_error_label: nil,
        notifications_user_id: user_id,
        notifications_unread_count: 0,
        in_app_notifications: [],
        selected_notification_id: nil
      )
    end
  end

  @doc "账号会话切换前取消当前用户的收件箱读取。"
  def cancel(socket), do: cancel_current_async(socket)

  @doc "关闭弹层并取消读取，避免关闭后旧结果更新页面。"
  def close(socket) do
    socket = cancel_current_async(socket)

    {:noreply,
     assign(socket,
       notifications_open: false,
       notifications_loading: false,
       notifications_error: nil,
       notification_read_error: nil,
       notification_read_error_action: nil,
       notification_read_error_label: nil,
       notifications_async_name: nil,
       selected_notification_id: nil
     )}
  end

  @doc "返回通知列表并清除当前详情。"
  def back(socket) do
    {:noreply,
     assign(socket,
       selected_notification_id: nil,
       notification_read_error: nil,
       notification_read_error_action: nil,
       notification_read_error_label: nil
     )}
  end

  @doc "仅打开当前用户列表中的通知，并立即标记为已读。"
  def open(%{"notification-id" => notification_id}, socket) do
    user_id = current_user_id(socket)
    notification = selected(socket.assigns.in_app_notifications, notification_id)

    if is_binary(user_id) and user_id == socket.assigns.notifications_user_id and notification do
      mark_selected_read(socket, user_id, notification_id, notification)
    else
      {:noreply, socket}
    end
  end

  def open(_params, socket), do: {:noreply, socket}

  @doc "重试将当前详情标记为已读。"
  def retry_read(socket) do
    user_id = current_user_id(socket)
    notification_id = socket.assigns.selected_notification_id
    notification = selected(socket.assigns.in_app_notifications, notification_id)

    if is_binary(user_id) and user_id == socket.assigns.notifications_user_id and notification do
      mark_selected_read(socket, user_id, notification_id, notification)
    else
      {:noreply, socket}
    end
  end

  @doc "将列表中的通知映射为组件所需的详情数据。"
  def selected(notifications, notification_id) do
    Enum.find(notifications, &(to_string(&1["id"]) == to_string(notification_id)))
  end

  @doc "处理异步结果；账号、弹层或请求改变后忽略旧结果。"
  def handle_async(
        {@async_name, user_id, _request_id} = async_name,
        {:ok, {result_user_id, {:ok, %{items: items, unread_count: unread_count}}}},
        socket
      )
      when user_id == result_user_id do
    finish_load(socket, async_name, user_id, items, unread_count, nil)
  end

  def handle_async(
        {@async_name, user_id, _request_id} = async_name,
        {:ok, {result_user_id, {:error, _reason}}},
        socket
      )
      when user_id == result_user_id,
      do: finish_load(socket, async_name, user_id, nil, nil, @load_error)

  def handle_async({@async_name, user_id, _request_id} = async_name, {:exit, _reason}, socket) do
    finish_load(socket, async_name, user_id, nil, nil, @load_error)
  end

  def handle_async(_name, _result, socket), do: {:noreply, socket}

  defp load(socket) do
    user_id = current_user_id(socket)

    if is_binary(user_id) do
      async_name = {@async_name, user_id, make_ref()}

      socket =
        socket
        |> cancel_current_async()
        |> clear_previous_user_data(user_id)
        |> assign(
          notifications_open: true,
          notifications_loading: true,
          notifications_error: nil,
          notification_read_error: nil,
          notification_read_error_action: nil,
          notification_read_error_label: nil,
          selected_notification_id: nil,
          notifications_user_id: user_id,
          notifications_async_name: async_name
        )
        |> Phoenix.LiveView.start_async(async_name, fn ->
          {user_id, Notification.list_for_user(user_id)}
        end)

      {:noreply, socket}
    else
      {:noreply,
       assign(socket,
         notifications_open: true,
         notifications_loading: false,
         notifications_error: @load_error,
         notification_read_error: nil,
         notification_read_error_action: nil,
         notification_read_error_label: nil,
         selected_notification_id: nil,
         in_app_notifications: [],
         notifications_unread_count: 0,
         notifications_user_id: nil,
         notifications_async_name: nil
       )}
    end
  end

  defp mark_selected_read(socket, user_id, notification_id, notification) do
    case Notification.mark_read(user_id, notification_id) do
      {:ok, updated} ->
        unread_count =
          if is_nil(notification["readAt"]),
            do: max(socket.assigns.notifications_unread_count - 1, 0),
            else: socket.assigns.notifications_unread_count

        notifications = replace_notification(socket.assigns.in_app_notifications, updated)

        {:noreply,
         assign(socket,
           in_app_notifications: notifications,
           notifications_unread_count: unread_count,
           notifications_error: nil,
           notification_read_error: nil,
           notification_read_error_action: nil,
           notification_read_error_label: nil,
           selected_notification_id: notification_id
         )}

      {:error, :not_found} ->
        {:noreply,
         assign(socket,
           notifications_error: nil,
           notification_read_error: @missing_error,
           notification_read_error_action: "retry-notifications",
           notification_read_error_label: "刷新通知列表",
           selected_notification_id: notification_id
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           notifications_error: nil,
           notification_read_error: @load_error,
           notification_read_error_action: "retry-notification-read",
           notification_read_error_label: "重试标记已读",
           selected_notification_id: notification_id
         )}
    end
  end

  defp finish_load(socket, async_name, user_id, items, unread_count, error) do
    if socket.assigns.notifications_open and
         socket.assigns.notifications_async_name == async_name and
         socket.assigns.notifications_user_id == user_id and
         current_user_id(socket) == user_id do
      values = [
        notifications_loading: false,
        notifications_error: error,
        notifications_async_name: nil
      ]

      values =
        if is_nil(error),
          do:
            Keyword.merge(values,
              in_app_notifications: items,
              notifications_unread_count: unread_count
            ),
          else: values

      {:noreply, assign(socket, values)}
    else
      {:noreply, socket}
    end
  end

  defp clear_previous_user_data(socket, user_id) do
    if socket.assigns.notifications_user_id == user_id do
      socket
    else
      assign(socket, in_app_notifications: [], notifications_unread_count: 0)
    end
  end

  defp refresh_current_user(%{assigns: %{notifications_open: true}} = socket, user_id) do
    case Notification.list_for_user(user_id) do
      {:ok, %{items: items, unread_count: unread_count}} ->
        assign(socket,
          notifications_loading: false,
          notifications_error: nil,
          notifications_user_id: user_id,
          notifications_unread_count: unread_count,
          in_app_notifications: items
        )

      {:error, _reason} ->
        assign(socket,
          notifications_loading: false,
          notifications_async_name: nil,
          notifications_error: @load_error
        )
    end
  end

  defp refresh_current_user(socket, user_id) do
    case Notification.unread_count_for_user(user_id) do
      {:ok, unread_count} ->
        assign(socket,
          notifications_loading: false,
          notifications_error: nil,
          notifications_async_name: nil,
          notifications_user_id: user_id,
          notifications_unread_count: unread_count
        )

      {:error, _reason} ->
        assign(socket, notifications_loading: false, notifications_async_name: nil)
    end
  end

  defp replace_notification(notifications, updated) do
    Enum.map(notifications, fn notification ->
      if notification["id"] == updated["id"], do: updated, else: notification
    end)
  end

  defp current_user_id(socket) do
    user = socket.assigns[:current_user]
    if is_map(user), do: Map.get(user, "userId") || Map.get(user, :user_id), else: nil
  end

  defp cancel_current_async(socket) do
    socket =
      case socket.assigns[:notifications_async_name] do
        nil -> socket
        async_name -> Phoenix.LiveView.cancel_async(socket, async_name)
      end

    assign(socket, notifications_async_name: nil)
  end
end
