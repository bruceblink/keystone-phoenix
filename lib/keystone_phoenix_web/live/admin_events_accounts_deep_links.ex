defmodule KeystonePhoenixWeb.Live.AdminEvents.AccountsDeepLinks do
  @moduledoc "登录后恢复用户列表深链接中的筛选条件和服务端分页状态。"

  alias KeystonePhoenixWeb.Live.AdminEvents.AccountsPagination

  # 复用用户列表的有效页校正；读取失败时保留原 URL 并显示列表错误。
  def restore_users_from_deep_link(socket) do
    {:noreply,
     AccountsPagination.assign_reloaded(socket, %{
       selected_user_ids: [],
       user_feedback: nil
     })}
  end
end
