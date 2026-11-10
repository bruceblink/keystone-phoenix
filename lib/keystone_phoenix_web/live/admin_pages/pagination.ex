defmodule KeystonePhoenixWeb.Live.AdminPages.Pagination do
  @moduledoc "Accessible pagination controls for LiveView data panels."

  use Phoenix.Component

  def pagination(assigns) do
    ~H"""
    <%= if @total > @page_size do %>
      <nav class="pagination" aria-label="分页">
        <button type="button" class="secondary" phx-click="paginate" phx-value-panel={@panel} phx-value-page={@page_num - 1} disabled={@page_num <= 1} phx-disable-with="加载中…">上一页</button>
        <span aria-live="polite">第 <%= @page_num %> / <%= page_count(@total, @page_size) %> 页，共 <%= @total %> 条</span>
        <button type="button" class="secondary" phx-click="paginate" phx-value-panel={@panel} phx-value-page={@page_num + 1} disabled={@page_num >= page_count(@total, @page_size)} phx-disable-with="加载中…">下一页</button>
      </nav>
    <% end %>
    """
  end

  def page_count(total, page_size) when total > 0 and page_size > 0,
    do: div(total + page_size - 1, page_size)

  def page_count(_total, _page_size), do: 1
end
