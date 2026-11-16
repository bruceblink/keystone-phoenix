defmodule KeystonePhoenixWeb.LoginNotifications do
  @moduledoc "管理登录后站内通知弹层的读取和状态转换。"

  import Phoenix.Component, only: [assign: 2]

  require Phoenix.LiveView

  alias KeystonePhoenixWeb.Live.AdminSupport

  @async_name :public_notifications
  @load_error "站内通知暂时无法读取，请重试"

  @doc "切换通知弹层；打开时先显示读取状态，再异步读取公开通知。"
  def toggle(socket) do
    if socket.assigns.notifications_open, do: close(socket), else: load(socket)
  end

  @doc "重新读取公开通知，并清除上一次的详情和错误状态。"
  def retry(socket), do: load(socket)

  @doc "关闭弹层并取消尚未完成的读取，避免关闭后异步结果再次更新界面。"
  def close(socket) do
    socket = Phoenix.LiveView.cancel_async(socket, @async_name)

    {:noreply,
     assign(socket,
       notifications_open: false,
       notifications_loading: false,
       notifications_error: nil,
       selected_notification_id: nil
     )}
  end

  @doc "返回通知列表并清除当前详情。"
  def back(socket), do: {:noreply, assign(socket, selected_notification_id: nil)}

  @doc "仅允许打开当前已加载列表中的通知详情。"
  def open(%{"notification-id" => notification_id}, socket) do
    if Enum.any?(socket.assigns.in_app_notifications, &(to_string(&1["id"]) == notification_id)),
      do: {:noreply, assign(socket, selected_notification_id: notification_id)},
      else: {:noreply, socket}
  end

  @doc "将选中的通知映射为组件所需的详情数据。"
  def selected(notifications, notification_id) do
    Enum.find(notifications, &(to_string(&1["id"]) == to_string(notification_id)))
  end

  @doc "处理异步读取结果；弹层关闭后忽略已经失效的结果。"
  def handle_async(@async_name, {:ok, {:ok, notifications}}, socket),
    do: finish_load(socket, notifications, nil)

  def handle_async(@async_name, {:ok, {:error, message}}, socket),
    do: finish_load(socket, [], message)

  def handle_async(@async_name, {:exit, _reason}, socket),
    do: finish_load(socket, [], @load_error)

  def handle_async(_name, _result, socket), do: {:noreply, socket}

  defp load(socket) do
    socket =
      socket
      |> Phoenix.LiveView.cancel_async(@async_name)
      |> assign(
        notifications_open: true,
        notifications_loading: true,
        notifications_error: nil,
        selected_notification_id: nil
      )
      |> Phoenix.LiveView.start_async(
        @async_name,
        &AdminSupport.load_public_notifications_result/0
      )

    {:noreply, socket}
  end

  defp finish_load(socket, notifications, error) do
    if socket.assigns.notifications_open do
      {:noreply,
       assign(socket,
         notifications_loading: false,
         notifications_error: error,
         selected_notification_id: nil,
         in_app_notifications: notifications
       )}
    else
      {:noreply, socket}
    end
  end
end
