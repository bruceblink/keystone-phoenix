defmodule KeystonePhoenixWeb.Live.AdminPages.LoginConfirmation do
  @moduledoc "重复登录确认弹窗。"

  use Phoenix.Component

  @doc "提示用户取消本次登录或接管已有活动会话。"
  def modal(assigns) do
    ~H"""
    <div :if={@open} class="modal-backdrop" role="presentation">
      <section class="modal modal-sm" role="dialog" aria-modal="true" aria-labelledby="force-login-title">
        <header class="modal-header">
          <div><h2 id="force-login-title">账号已有活动会话</h2><p>该账号已经在其他位置登录。你可以取消本次登录，或强制接管已有会话。</p></div>
          <button type="button" class="modal-close" phx-click="cancel-force-login" aria-label="关闭">×</button>
        </header>
        <div class="modal-body"><p class="login-session-warning" role="status">强制登录会使该账号的其他活动会话失效。</p></div>
        <footer class="modal-footer"><button type="button" class="button button-ghost" phx-click="cancel-force-login">取消登录</button><button type="button" class="button button-primary" phx-click="force-login" phx-disable-with="接管中…">强制登录</button></footer>
      </section>
    </div>
    """
  end
end
