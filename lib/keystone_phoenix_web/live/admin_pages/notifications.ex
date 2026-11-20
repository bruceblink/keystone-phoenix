defmodule KeystonePhoenixWeb.Live.AdminPages.Notifications do
  @moduledoc "站内通知列表与详情组件。"

  use Phoenix.Component

  @doc "渲染只读的站内通知列表或选中通知详情。"
  def menu(assigns) do
    assigns =
      assigns
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:unread_count, fn -> 0 end)
      |> assign_new(:read_error, fn -> nil end)
      |> assign_new(:page, fn -> 1 end)
      |> assign_new(:has_more, fn -> false end)
      |> assign_new(:read_error_action, fn -> "retry-notification-read" end)
      |> assign_new(:read_error_label, fn -> "重试标记已读" end)

    ~H"""
    <div class="notification-menu">
      <button type="button" class="icon-button" phx-click="toggle-notifications" aria-label={notification_label(@unread_count)} aria-expanded={@open}>
        <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" /><path d="M13.73 21a2 2 0 0 1-3.46 0" /></svg>
        <span :if={@unread_count > 0} class="notification-dot" aria-hidden="true"></span>
      </button>
      <section :if={@open} class="notification-popover" role="dialog" aria-label="站内通知">
        <header class="notification-popover-header">
          <button :if={@selected} type="button" class="button button-ghost button-sm" phx-click="back-notifications" aria-label="返回通知列表">←</button>
          <span :if={!@selected} class="notification-popover-icon" aria-hidden="true"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" /><path d="M13.73 21a2 2 0 0 1-3.46 0" /></svg></span>
          <div><strong><%= if @selected, do: "通知详情", else: "站内通知" %></strong><span><%= if @selected, do: "查看通知内容", else: "#{length(@notifications)} 条本页通知 · 第 #{@page} 页" %></span></div>
          <button type="button" class="button button-ghost button-sm" phx-click="close-notifications" aria-label="关闭通知">×</button>
        </header>
        <%= cond do %>
          <% @loading == true and @notifications == [] -> %>
            <div class="notification-state" role="status" aria-live="polite">正在读取通知</div>
          <% not is_nil(@error) and @notifications == [] -> %>
            <div class="notification-state notification-state-error" role="alert"><span><%= @error %></span><button type="button" class="button button-ghost button-sm" phx-click="retry-notifications">重试</button></div>
          <% @selected -> %>
            <article class="notification-detail">
              <p class="notification-detail-meta"><.local_time id="notification-detail-created-at" value={@selected["createdAt"]} /></p>
              <h3><%= @selected["title"] %></h3>
              <p><%= @selected["content"] %></p>
              <div :if={@read_error} class="notification-state notification-state-error" role="alert"><span><%= @read_error %></span><button type="button" class="button button-ghost button-sm" phx-click={@read_error_action}><%= @read_error_label %></button></div>
            </article>
          <% true -> %>
            <!-- 后台刷新失败时保留旧列表，同时显示错误和重试入口。 -->
            <div :if={@error} class="notification-state notification-state-error" role="alert"><span><%= @error %></span><button type="button" class="button button-ghost button-sm" phx-click="retry-notifications">重试</button></div>
            <div class="notification-list" role="list">
              <%= if @notifications == [] do %>
                <div class="notification-state" role="status">暂无站内通知</div>
              <% else %>
                <%= for notification <- @notifications do %>
                  <button type="button" class={if is_nil(notification["readAt"]), do: "notification-list-item notification-unread", else: "notification-list-item"} phx-click="open-notification" phx-value-notification-id={notification["id"]}>
                    <span :if={is_nil(notification["readAt"])} class="notification-list-dot" aria-hidden="true"></span>
                    <span><strong><%= notification["title"] %></strong><small><.local_time id={"notification-created-at-#{notification["id"]}"} value={notification["createdAt"]} /><%= if is_nil(notification["readAt"]), do: " · 未读", else: "" %></small></span>
                  </button>
                <% end %>
              <% end %>
            </div>
        <% end %>
        <nav :if={!@selected} class="notification-pagination" aria-label="通知分页">
          <button type="button" class="button button-ghost button-sm" phx-click="paginate-notifications" phx-value-page={@page - 1} disabled={@page <= 1 or @loading}>上一页</button>
          <span>第 <%= @page %> 页</span>
          <button type="button" class="button button-ghost button-sm" phx-click="paginate-notifications" phx-value-page={@page + 1} disabled={!@has_more or @loading}>下一页</button>
        </nav>
      </section>
    </div>
    """
  end

  @doc "通过 LocalDateTime hook 在浏览器本地时区显示 UTC 时间戳。"
  def local_time(assigns) do
    ~H"""
    <time id={@id} phx-hook="LocalDateTime" data-utc-time={@value}><%= @value %></time>
    """
  end

  def notification_label(0), do: "通知"
  def notification_label(count), do: "通知，#{count} 条未读"
end
