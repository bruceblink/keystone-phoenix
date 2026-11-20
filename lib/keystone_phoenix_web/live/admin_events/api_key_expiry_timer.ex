defmodule KeystonePhoenixWeb.Live.AdminEvents.ApiKeyExpiryTimer do
  @moduledoc "管理 API Key 状态更新使用的一次性 LiveView 计时器。"

  import Phoenix.Component, only: [assign: 2]

  # Erlang 计时器有延迟上限；较远的到期时间醒来一次后会重新安排。
  @max_delay_ms 2_147_483_647

  # 切换页面或结束 LiveView 时取消待处理计时器。
  def cancel(socket) do
    case socket.assigns[:api_key_expiry_timer] do
      nil -> :ok
      timer -> Process.cancel_timer(timer)
    end

    assign(socket, api_key_expiry_timer: nil, api_key_expiry_token: nil)
  end

  # 消息令牌可识别替换前已进入队列的旧计时消息。
  def schedule(socket, %DateTime{} = expires_at) do
    socket = cancel(socket)
    token = make_ref()
    delay = max(DateTime.diff(expires_at, DateTime.utc_now(), :millisecond), 0)
    timer = Process.send_after(self(), {:api_key_expiry_tick, token}, min(delay, @max_delay_ms))

    assign(socket, api_key_expiry_timer: timer, api_key_expiry_token: token)
  end
end
