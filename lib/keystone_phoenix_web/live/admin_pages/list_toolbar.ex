defmodule KeystonePhoenixWeb.Live.AdminPages.ListToolbar do
  @moduledoc "列表页筛选条件下方的操作按钮组。"

  use Phoenix.Component

  attr :label, :string, required: true
  slot :inner_block, required: true

  # 保持按钮在初次加载和查询失败时可见，并为辅助技术提供操作组名称。
  def list_toolbar(assigns) do
    ~H"""
    <div class="list-toolbar" role="group" aria-label={@label}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end
end
