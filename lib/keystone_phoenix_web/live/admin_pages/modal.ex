defmodule KeystonePhoenixWeb.Live.AdminPages.Modal do
  @moduledoc "共享管理表单模态框组件。"

  use Phoenix.Component

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil

  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div class="modal-backdrop" role="presentation">
      <div
        id={@id}
        class="modal-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        phx-click-away="close-modal"
        phx-window-keydown="close-modal"
        phx-key="Escape"
      >
        <div class="modal-header">
          <div>
            <p class="modal-kicker">数据维护</p>
            <h2 id={"#{@id}-title"}><%= @title %></h2>
            <p :if={@description} class="modal-description"><%= @description %></p>
          </div>
          <button type="button" class="modal-close" aria-label="关闭弹窗" phx-click="close-modal">×</button>
        </div>
        <div class="modal-body"><%= render_slot(@inner_block) %></div>
      </div>
    </div>
    """
  end
end
