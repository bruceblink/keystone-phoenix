defmodule KeystonePhoenixWeb.Live.AdminPages.AccountReload do
  @moduledoc "账号写入后关联角色列表的结果型重新读取。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminReadSupport

  @doc "重新读取角色列表；失败时保留旧列表并显示错误码。"
  def after_user_write(socket, success) do
    case AdminReadSupport.roles(socket) do
      {:ok, rows} -> assign(socket, role_rows: rows, role_feedback: success)
      {:error, reason} -> assign(socket, role_feedback: error_feedback(reason))
    end
  end

  defp error_feedback(reason),
    do: Feedback.error(Feedback.code(Feedback.from_reason(reason)), "角色列表刷新失败，请重试")
end
