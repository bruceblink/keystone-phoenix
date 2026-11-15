defmodule KeystonePhoenixWeb.Live.AdminPages.Notifications do
  @moduledoc "站内通知列表与详情组件。"

  use Phoenix.Component

  @doc "渲染只读的站内通知列表或选中通知详情。"
  def menu(assigns) do
    ~H"""
    <div class="notification-menu">
      <button type="button" class="icon-button" phx-click="toggle-notifications" aria-label="通知" aria-expanded={@open}>
        <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" /><path d="M13.73 21a2 2 0 0 1-3.46 0" /></svg>
        <span :if={@notifications != []} class="notification-dot" aria-hidden="true"></span>
      </button>
      <section :if={@open} class="notification-popover" role="dialog" aria-label="站内通知">
        <header class="notification-popover-header">
          <button :if={@selected} type="button" class="button button-ghost button-sm" phx-click="back-notifications" aria-label="返回通知列表">←</button>
          <span :if={!@selected} class="notification-popover-icon" aria-hidden="true">●</span>
          <div><strong><%= if @selected, do: "通知详情", else: "站内通知" %></strong><span><%= if @selected, do: "查看通知内容", else: "#{length(@notifications)} 条可见通知" %></span></div>
          <button type="button" class="button button-ghost button-sm" phx-click="close-notifications" aria-label="关闭通知">×</button>
        </header>
        <%= if @selected do %>
          <article class="notification-detail">
            <p class="notification-detail-meta"><%= notification_time(@selected["publishAt"] || @selected["createdAt"]) %> · <%= @selected["noticeType"] || "通知" %></p>
            <h3><%= @selected["title"] %></h3>
            <p><%= @selected["content"] %></p>
          </article>
        <% else %>
          <div class="notification-list" role="list">
            <%= if @notifications == [] do %>
              <div class="notification-state" role="status">暂无站内通知</div>
            <% else %>
              <%= for notification <- @notifications do %>
                <button type="button" class="notification-list-item" phx-click="open-notification" phx-value-notification-id={notification["id"]}>
                  <span class="notification-list-dot" aria-hidden="true"></span>
                  <span><strong><%= notification["title"] %></strong><small><%= notification_time(notification["publishAt"] || notification["createdAt"]) %></small></span>
                </button>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  def notification_time(nil), do: "刚刚"
  def notification_time(value), do: to_string(value)
end
