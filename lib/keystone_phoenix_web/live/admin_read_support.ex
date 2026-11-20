defmodule KeystonePhoenixWeb.Live.AdminReadSupport do
  @moduledoc "LiveView 读取结果辅助模块，保留查询失败以便页面显示重试反馈。"

  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Notice
  alias KeystonePhoenix.Log
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Role
  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationData
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

  @doc "读取当前用户页，并保留服务端总数和授权错误。"
  def users_page(socket, params \\ %{}) do
    result =
      if Support.admin_socket?(socket),
        do: User.list_users(params),
        else: User.list_users(params, socket.assigns.current_user)

    {:ok, Map.merge(%{page: page_number(params), size: page_size(params)}, result)}
  rescue
    _error -> {:error, :service_unavailable}
  end

  def jobs(socket) do
    if Support.admin_socket?(socket),
      do: load_all(&Job.list_jobs/1),
      else: load_authorized(&Job.list_jobs(&1, Support.authorization_options(socket)))
  end

  @doc "读取当前任务页，并保留总数和服务错误。"
  def jobs_page(socket, params \\ %{}) do
    result =
      if Support.admin_socket?(socket),
        do: Job.list_jobs(params),
        else: Job.list_jobs(params, Support.authorization_options(socket))

    page_result(result)
  rescue
    _error -> {:error, :service_unavailable}
  end

  def job_logs(socket) do
    if Support.admin_socket?(socket),
      do: load_all(&Job.list_job_logs/1),
      else: load_authorized(&Job.list_job_logs(&1, Support.authorization_options(socket)))
  end

  @doc "读取当前任务的执行日志页，并保留总数和服务错误。"
  def job_logs_page(socket, params \\ %{}) do
    result =
      if Support.admin_socket?(socket),
        do: Job.list_job_logs(params),
        else: Job.list_job_logs(params, Support.authorization_options(socket))

    page_result(result)
  rescue
    _error -> {:error, :service_unavailable}
  end

  @doc "读取岗位列表并区分空结果和服务端读取失败。"
  def posts(socket) do
    if Support.admin_socket?(socket) do
      load_all(&Post.list_posts/1)
    else
      load_authorized(&Post.list_posts(&1, Support.authorization_options(socket)))
    end
  end

  @doc "读取当前岗位页，并保留总数和服务错误。"
  def posts_page(socket, params \\ %{}) do
    result =
      if Support.admin_socket?(socket),
        do: Post.list_posts(params),
        else: Post.list_posts(params, Support.authorization_options(socket))

    page_result(result)
  rescue
    _error -> {:error, :service_unavailable}
  end

  @doc "读取组织、角色和菜单数据，并保留刷新失败结果。"
  def departments(socket) do
    actor = if Support.admin_socket?(socket), do: nil, else: socket.assigns.current_user
    OrganizationData.load_depts_result(actor)
  end

  def roles(socket), do: OrganizationData.load_roles_result(organization_options(socket))

  @doc "读取角色当前页，并保留服务端总数和授权错误。"
  def roles_page(socket, params \\ %{}) do
    OrganizationData.load_roles_page_result(organization_options(socket), params)
  end

  def menus(socket), do: OrganizationData.load_menus_result(organization_options(socket))

  @doc "读取角色成员的两栏当前页，并区分空列表和服务失败。"
  def role_users(role_id, actor, page_size) do
    params = %{"pageNum" => 1, "pageSize" => page_size}
    allocated = Role.list_allocated_users(role_id, params, actor)
    unallocated = Role.list_unallocated_users(role_id, params, actor)
    {:ok, %{allocated: allocated, unallocated: unallocated}}
  rescue
    _error -> {:error, :service_unavailable}
  end

  @doc "读取指定成员栏的页面，页码越界时回到最后一页。"
  def role_users_page(role_id, actor, panel, page, page_size) do
    fetch =
      if panel == "role-users-allocated",
        do: &Role.list_allocated_users/3,
        else: &Role.list_unallocated_users/3

    result = fetch.(role_id, %{"pageNum" => page, "pageSize" => page_size}, actor)
    last_page = max(div(result.total + page_size - 1, page_size), 1)
    actual_page = min(page, last_page)

    result =
      if actual_page == page,
        do: result,
        else: fetch.(role_id, %{"pageNum" => actual_page, "pageSize" => page_size}, actor)

    {:ok, actual_page, result}
  rescue
    _error -> {:error, :service_unavailable}
  end

  @doc "读取系统配置并区分空结果和服务端读取失败。"
  def configs(socket, params \\ %{}) do
    options = Support.authorization_options(socket)

    if Support.admin_socket?(socket) do
      load_all(&Config.list_configs/1, params)
    else
      load_authorized(fn page -> Config.list_configs(page, options) end, params)
    end
  end

  @doc "读取当前配置页并保留页码、总数和服务错误。"
  def config_page(socket, params \\ %{}) do
    options = Support.authorization_options(socket)

    result =
      if Support.admin_socket?(socket) do
        Config.list_configs_page(params)
      else
        Config.list_configs_page(params, options)
      end

    case result do
      {:ok, page} -> {:ok, page}
      page when is_map(page) -> {:ok, page}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_page}
    end
  rescue
    _error -> {:error, :service_unavailable}
  end

  @doc "读取当前主体的 API Key 元数据，并保留授权或服务失败结果。"
  def api_keys(socket) do
    try do
      ApiKey.list(current_user_id(socket), Support.authorization_options(socket))
    rescue
      _error -> {:error, :service_unavailable}
    end
  end

  @doc "读取当前 API Key 页并保留页码、总数和服务失败结果。"
  def api_keys_page(socket, params \\ %{}) do
    try do
      ApiKey.list_page(current_user_id(socket), params, Support.authorization_options(socket))
    rescue
      _error -> {:error, :service_unavailable}
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

  @doc "读取字典类型和当前条目页，并保留分页总数和服务错误。"
  def dictionary_page(socket, selected, params \\ %{}) do
    options = Support.authorization_options(socket)

    with {:ok, types} <- dictionary_types(socket, options, %{}),
         selected <- selected_dictionary_type(selected, types),
         {:ok, page} <- dictionary_data_page(socket, selected, params) do
      {:ok, %{types: types, selected: selected, data: page}}
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

  @doc "读取指定类型的服务端字典条目页。"
  def dictionary_data_page(_socket, "", params) do
    {:ok, %{items: [], page: page_number(params), size: page_size(params), total: 0}}
  end

  def dictionary_data_page(socket, dict_type, params) when is_binary(dict_type) do
    options = Support.authorization_options(socket)

    result =
      if Support.admin_socket?(socket) do
        Dictionary.list_dict_data_page_by_type(dict_type, params)
      else
        Dictionary.list_dict_data_page_by_type(dict_type, params, options)
      end

    case result do
      {:ok, page} -> {:ok, page}
      page when is_map(page) -> {:ok, page}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_page}
    end
  rescue
    _error -> {:error, :service_unavailable}
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

  @doc "读取公告当前页，并保留总数和服务错误。"
  def notices_page(socket, params \\ %{}) do
    options = Support.authorization_options(socket)

    result =
      if Support.admin_socket?(socket),
        do: Notice.list_notices_page(params),
        else: Notice.list_notices_page(params, options)

    case result do
      {:ok, page} -> {:ok, page}
      page when is_map(page) -> {:ok, page}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_page}
    end
  rescue
    _error -> {:error, :service_unavailable}
  end

  @doc "读取当前页登录日志，并保留授权或数据库失败结果。"
  def login_logs_page(socket, params \\ %{}) do
    read_log_page(
      socket,
      "login-log:read",
      &Log.list_login_logs/1,
      &Log.list_login_logs/2,
      params,
      "login-logs"
    )
  end

  @doc "读取当前页操作审计，并保留授权或数据库失败结果。"
  def operation_logs_page(socket, params \\ %{}) do
    read_log_page(
      socket,
      "operation-log:read",
      &Log.list_operation_logs/1,
      &Log.list_operation_logs/2,
      params,
      "operation-logs"
    )
  end

  @doc "读取登录日志和操作审计，并保留任一查询失败结果。"
  def logs(socket, filters \\ %{}) do
    login_filter = Map.get(filters, "login", %{})
    operation_filter = Map.get(filters, "operation", %{})

    with {:ok, login_page} <-
           login_logs_page(socket, login_filter),
         {:ok, operation_page} <-
           operation_logs_page(socket, operation_filter) do
      {:ok,
       %{
         login_log_rows: login_page.rows,
         login_log_total: login_page.total,
         operation_log_rows: operation_page.rows,
         operation_log_total: operation_page.total
       }}
    end
  end

  defp read_log_page(socket, permission, admin_fetcher, authorized_fetcher, params, panel) do
    log_page(
      socket,
      Support.authorization_options(socket),
      permission,
      admin_fetcher,
      authorized_fetcher,
      params,
      panel
    )
  rescue
    _error -> {:error, :service_unavailable}
  end

  defp dictionary_types(socket, options, params) do
    if Support.admin_socket?(socket) do
      load_all(&Dictionary.list_dict_types/1, params)
    else
      load_authorized(fn page -> Dictionary.list_dict_types(page, options) end, params)
    end
  end

  defp log_page(socket, options, permission, admin_fetcher, authorized_fetcher, filters, panel) do
    params = page_params(socket, panel, filters)

    cond do
      Support.admin_socket?(socket) ->
        {:ok, admin_fetcher.(params)}

      permission in List.wrap(socket.assigns[:permissions]) ->
        authorized_fetcher.(params, options)

      true ->
        {:ok, %{rows: [], total: 0, page: params["pageNum"], size: params["pageSize"]}}
    end
  end

  defp page_params(socket, panel, filters) do
    filters
    |> Map.put_new("pageNum", get_in(socket.assigns, [:page_nums, panel]) || 1)
    |> Map.put_new("pageSize", get_in(socket.assigns, [:page_sizes, panel]) || 20)
  end

  defp selected_dictionary_type(selected, types) do
    if selected != "" and Enum.any?(types, &(&1["dictType"] == selected)),
      do: selected,
      else: List.first(types, %{})["dictType"] || ""
  end

  defp page_result({:ok, page}), do: {:ok, page}
  defp page_result(page) when is_map(page), do: {:ok, page}
  defp page_result({:error, reason}), do: {:error, reason}
  defp page_result(_other), do: {:error, :invalid_page}

  defp page_number(params),
    do:
      positive_param(params["page"] || params[:page] || params["pageNum"] || params[:page_num], 1)

  defp page_size(params),
    do:
      positive_param(
        params["size"] || params[:size] || params["pageSize"] || params[:page_size],
        50
      )

  defp positive_param(value, default) do
    case Integer.parse(to_string(value || default)) do
      {number, ""} when number > 0 -> min(number, 100)
      _ -> default
    end
  end

  defp current_user_id(socket),
    do: socket.assigns.current_user["userId"] || socket.assigns.current_user[:user_id]

  defp organization_options(socket) do
    if Support.admin_socket?(socket), do: [], else: Support.authorization_options(socket)
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
