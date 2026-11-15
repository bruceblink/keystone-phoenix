defmodule KeystonePhoenixWeb.Live.AdminReadSupport do
  @moduledoc "LiveView 读取结果辅助模块，保留查询失败以便页面显示重试反馈。"

  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Notice
  alias KeystonePhoenix.Post
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

  @doc "读取岗位列表并区分空结果和服务端读取失败。"
  def posts(socket) do
    if Support.admin_socket?(socket) do
      load_all(&Post.list_posts/1)
    else
      load_authorized(&Post.list_posts(&1, Support.authorization_options(socket)))
    end
  end

  @doc "读取字典类型和当前类型条目，并保留任一读取失败结果。"
  def dictionary(socket, selected, params \\ %{}) do
    options = Support.authorization_options(socket)

    with {:ok, types} <- dictionary_types(socket, options, params),
         selected <- selected_dictionary_type(selected, types),
         {:ok, data} <- dictionary_data(socket, selected, options) do
      {:ok, %{types: types, selected: selected, data: data}}
    end
  end

  @doc "读取字典条目，并区分空类型和读取失败。"
  def dictionary_data(_socket, "", _options), do: {:ok, []}

  def dictionary_data(socket, dict_type, options) when is_binary(dict_type) do
    params = %{"dictType" => dict_type}

    if Support.admin_socket?(socket) do
      load_all(&Dictionary.list_dict_data/1, params)
    else
      load_authorized(fn page -> Dictionary.list_dict_data(page, options) end, params)
    end
  end

  @doc "读取公告列表并保留服务端错误。"
  def notices(socket, params \\ %{}) do
    options = Support.authorization_options(socket)

    if Support.admin_socket?(socket) do
      load_all(&Notice.list_notices/1, params)
    else
      load_authorized(fn page -> Notice.list_notices(page, options) end, params)
    end
  end

  defp dictionary_types(socket, options, params) do
    if Support.admin_socket?(socket) do
      load_all(&Dictionary.list_dict_types/1, params)
    else
      load_authorized(fn page -> Dictionary.list_dict_types(page, options) end, params)
    end
  end

  defp selected_dictionary_type(selected, types) do
    if selected != "" and Enum.any?(types, &(&1["dictType"] == selected)),
      do: selected,
      else: List.first(types, %{})["dictType"] || ""
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
