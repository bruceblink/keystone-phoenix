defmodule KeystonePhoenixWeb.Live.AdminPages.Confirmation do
  @moduledoc "为需要确认的列表操作提供共用原生弹窗。"

  use Phoenix.Component

  @doc "确认文本由触发按钮提供；取消是默认焦点。"
  def dialog(assigns) do
    ~H"""
    <dialog id="phx-confirm-dialog" class="modal modal-sm phx-confirm-dialog" aria-labelledby="phx-confirm-title" aria-describedby="phx-confirm-message">
      <header class="modal-header"><div><h2 id="phx-confirm-title">确认操作</h2><p>请检查操作内容后继续。</p></div><button id="phx-confirm-close" type="button" class="modal-close" aria-label="关闭">×</button></header>
      <div class="modal-body"><p id="phx-confirm-message"></p></div>
      <footer class="modal-footer"><button id="phx-confirm-cancel" type="button" class="button button-ghost" autofocus>取消</button><button id="phx-confirm-accept" type="button" class="button button-danger">确认</button></footer>
    </dialog>
    """
  end
end
