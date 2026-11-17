defmodule KeystonePhoenixWeb.Live.AdminPages.InitialPassword do
  use Phoenix.Component

  # 密码字段只随表单提交传给服务端，不通过 phx-change 写入 LiveView assigns。
  def initial_password(assigns) do
    ~H"""
    <section class="initial-password-panel" aria-labelledby="initial-password-title">
      <form id="initial-password-form" class="login-form initial-password-form" phx-submit="change-initial-password">
        <p id="initial-password-title" class="form-status" role="status">该账号需要先更换初始密码，完成后请使用新密码登录。</p>
        <p class="form-status">账号：<%= @username %></p>
        <div id="initial-password-fields" phx-update="ignore">
          <label for="initial-current-password">当前密码</label>
          <div class="input-wrap"><svg xmlns="http://www.w3.org/2000/svg" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="4" y="10" width="16" height="10" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg><input id="initial-current-password" name="currentPassword" type="password" autocomplete="current-password" required /></div>
          <label for="initial-new-password">新密码</label>
          <div class="input-wrap"><svg xmlns="http://www.w3.org/2000/svg" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="4" y="10" width="16" height="10" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg><input id="initial-new-password" name="newPassword" type="password" autocomplete="new-password" required /></div>
          <label for="initial-confirm-password">确认新密码</label>
          <div class="input-wrap"><svg xmlns="http://www.w3.org/2000/svg" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="4" y="10" width="16" height="10" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg><input id="initial-confirm-password" name="confirmPassword" type="password" autocomplete="new-password" required /></div>
        </div>
        <p class="login-footnote initial-password-policy">新密码需满足当前系统的安全策略。</p>
        <p :if={@error} class="form-error" role="alert"><%= @error %></p>
        <button type="submit" class="login-submit" phx-disable-with="正在更新…">更新密码 <svg xmlns="http://www.w3.org/2000/svg" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14" /><path d="m13 6 6 6-6 6" /></svg></button>
        <button type="button" class="button button-ghost button-sm initial-password-cancel" phx-click="cancel-initial-password">取消并返回登录</button>
      </form>
    </section>
    """
  end
end
