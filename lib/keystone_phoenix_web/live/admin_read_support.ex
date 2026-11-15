defmodule KeystonePhoenixWeb.Live.AdminReadSupport do
  @moduledoc "LiveView 读取结果辅助模块，保留查询失败以便页面显示重试反馈。"

  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.User
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminSupport, as: Support

  def users(socket, params \\ %{}) do
    if Support.admin_socket?(socket) do
      load_all(&User.list_users/1, params)
    else
      load_authorized(fn page -> User.list_users(page, socket.assigns.current_user) end, params)
    end
  end

  def jobs(socket) do
    if Support.admin_socket?(socket),
      do: load_all(&Job.list_jobs/1),
      else: load_authorized(&Job.list_jobs(&1, Support.authorization_options(socket)))
  end

  def job_logs(socket) do
    if Support.admin_socket?(socket),
      do: load_all(&Job.list_job_logs/1),
      else: load_authorized(&Job.list_job_logs(&1, Support.authorization_options(socket)))
  end

  # 读取失败必须与空结果区分，避免页面把服务故障显示成“暂无数据”。
  def read_error_feedback(reason, message),
    do: Feedback.error(Feedback.code(Feedback.from_reason(reason)), message)

  defp load_all(fetcher, params \\ %{}) do
    {:ok, Excel.all_rows(fetcher, params)}
  rescue
    _error -> {:error, :service_unavailable}
  end

  defp load_authorized(fetcher, params \\ %{}) do
    case Excel.all_rows_result(fetcher, params) do
      {:ok, rows} -> {:ok, rows}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _error -> {:error, :service_unavailable}
  end
end
