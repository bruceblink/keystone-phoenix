defmodule KeystonePhoenixWeb.Live.AdminPages.Reload do
  @moduledoc "管理页面刷新和写入后重新读取的统一结果处理。"

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenixWeb.Live.AdminPages.Feedback

  @doc "刷新列表；失败时保留旧列表，只更新错误反馈和筛选状态。"
  def refresh(socket, loader, rows_key, feedback_key, message, extra \\ []) do
    case loader.(socket) do
      {:ok, rows} ->
        assign(socket, Keyword.merge(extra, [{rows_key, rows}, {feedback_key, nil}]))

      {:error, reason} ->
        assign(socket, Keyword.merge(extra, [{feedback_key, error_feedback(reason, message)}]))
    end
  end

  @doc "写入成功后重新读取列表；读取失败时保留旧列表并显示错误码。"
  def after_success(socket, loader, rows_key, feedback_key, success, message, extra \\ []) do
    case loader.(socket) do
      {:ok, rows} ->
        assign(socket, Keyword.merge(extra, [{rows_key, rows}, {feedback_key, success}]))

      {:error, reason} ->
        assign(socket, Keyword.merge(extra, [{feedback_key, error_feedback(reason, message)}]))
    end
  end

  defp error_feedback(reason, message) do
    Feedback.error(Feedback.code(Feedback.from_reason(reason)), message)
  end
end
