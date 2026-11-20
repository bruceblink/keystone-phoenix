defmodule KeystonePhoenixWeb.Live.AdminSupport do
  @moduledoc "Shared dashboard loading, form defaults, and authorization helpers."
  require Logger

  import Phoenix.Component, only: [assign: 2]
  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Log
  alias KeystonePhoenix.Notice
  alias KeystonePhoenix.Post
  alias KeystonePhoenixWeb.Live.AdminPages.Forms
  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationData
  alias KeystonePhoenixWeb.Live.AdminPages.RoleDirectory
  alias KeystonePhoenixWeb.Live.AdminPages.Pagination
  alias KeystonePhoenix.User
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.AdminReadSupport
  alias KeystonePhoenixWeb.Live.MonitorSupport
  # 个人资料读取失败使用稳定错误码。
  @profile_unavailable_feedback Feedback.error(:service_unavailable, "个人资料暂不可用")

  @panel_permissions %{
    "depts" => ["department:read"],
    "posts" => ["post:read"],
    "roles" => ["role:read"],
    "menus" => ["menu:read"],
    "api-keys" => ["api-key:read"],
    "users" => ["user:read"],
    "configs" => ["config:read"],
    "dicts" => ["dictionary:read"],
    "notices" => ["notice:read"],
    "logs" => ["login-log:read", "operation-log:read"],
    "login-logs" => ["login-log:read"],
    "operation-logs" => ["operation-log:read"],
    "jobs" => ["job:read"],
    "job-logs" => ["job:read"],
    "monitor" => ["cache:refresh", "server:read", "online-session:read", "audit:read"]
  }

  @panel_resources %{
    "posts" => :post,
    "roles" => :role,
    "menus" => :menu,
    "api-keys" => :api_key,
    "configs" => :config,
    "dicts" => :dictionary,
    "notices" => :notice,
    "logs" => :audit,
    "login-logs" => :audit,
    "operation-logs" => :audit,
    "jobs" => :job,
    "job-logs" => :job,
    "monitor" => :session
  }

  def load_dashboard do
    logs = load_logs()
    dictionary = load_dictionary("")
    role_directory = RoleDirectory.load([])

    %{
      user_rows: load_users(),
      dept_rows: load_depts(),
      post_rows: load_posts(),
      role_rows: role_directory.rows,
      role_directory_feedback: role_directory.feedback,
      selected_role_ids: [],
      selected_role_id: "",
      selected_role_name: "",
      allocated_role_user_rows: [],
      unallocated_role_user_rows: [],
      role_user_totals: %{allocated: 0, unallocated: 0},
      role_user_feedback: nil,
      menu_rows: load_menus(),
      notice_rows: load_notices(),
      selected_notice_ids: [],
      notice_filter: %{"title" => "", "published" => "all"},
      login_log_rows: logs.login_log_rows,
      operation_log_rows: logs.operation_log_rows,
      config_rows: load_configs(),
      dict_type_rows: dictionary.types,
      dict_data_rows: dictionary.data,
      selected_dict_type: dictionary.selected,
      job_rows: load_jobs(),
      job_log_rows: load_job_logs()
    }
  end

  def empty_dashboard,
    do: %{
      user_rows: [],
      dept_rows: [],
      post_rows: [],
      role_rows: [],
      role_directory_feedback: nil,
      selected_role_ids: [],
      selected_role_id: "",
      selected_role_name: "",
      allocated_role_user_rows: [],
      unallocated_role_user_rows: [],
      role_user_totals: %{allocated: 0, unallocated: 0},
      role_user_feedback: nil,
      menu_rows: [],
      notice_rows: [],
      selected_notice_ids: [],
      notice_filter: %{"title" => "", "published" => "all"},
      login_log_rows: [],
      operation_log_rows: [],
      config_rows: [],
      dict_type_rows: [],
      dict_data_rows: [],
      selected_dict_type: "",
      job_rows: [],
      job_log_rows: []
    }

  @doc "Loads only list data granted to a non-admin LiveView session."
  def load_dashboard_for_permissions(user, permissions) do
    access = panel_access(permissions)
    dashboard = empty_dashboard()
    options = [authorization: %{principal: Map.put(user, :permissions, permissions)}]
    dictionary = if access["dicts"], do: load_dictionary("", options), else: empty_dictionary()
    logs = logs_for_permissions(permissions, options, %{})

    role_scope_allowed =
      Authz.resource_scope_allowed?(Map.put(user, :permissions, permissions), :role)

    role_directory =
      if role_scope_allowed and "role:read" in permissions,
        do: RoleDirectory.load(options),
        else: RoleDirectory.empty()

    dashboard
    |> Map.put(:dept_rows, if(access["depts"], do: load_depts_for_user(user), else: []))
    |> Map.put(:post_rows, if(access["posts"], do: load_posts(options), else: []))
    |> Map.put(:role_rows, role_directory.rows)
    |> Map.put(:role_directory_feedback, role_directory.feedback)
    |> Map.put(:role_scope_allowed, role_scope_allowed)
    |> Map.put(:menu_rows, if(access["menus"], do: load_menus(options), else: []))
    |> Map.put(:user_rows, if(access["users"], do: load_users_for_user(user), else: []))
    |> Map.put(:config_rows, if(access["configs"], do: load_configs(options), else: []))
    |> Map.put(:dict_type_rows, dictionary.types)
    |> Map.put(:dict_data_rows, dictionary.data)
    |> Map.put(:selected_dict_type, dictionary.selected)
    |> Map.put(:notice_rows, if(access["notices"], do: load_notices(options), else: []))
    |> Map.put(:job_rows, if(access["jobs"], do: load_jobs(options), else: []))
    |> Map.put(:job_log_rows, if(access["job-logs"], do: load_job_logs(options), else: []))
    |> Map.put(:login_log_rows, logs.login_log_rows)
    |> Map.put(:operation_log_rows, logs.operation_log_rows)
  end

  @doc "Returns panel visibility for a permission list."
  def panel_access(permissions, user \\ nil) do
    Enum.into(@panel_permissions, %{}, fn {panel, required} ->
      {panel,
       Enum.any?(required, &(&1 in List.wrap(permissions))) and
         scope_panel_allowed?(user, panel, permissions)}
    end)
    |> Map.put("overview", true)
    |> Map.put("profile", true)
  end

  def load_users(params \\ %{}), do: load_all(&User.list_users/1, params)

  def load_users_for_user(user, params \\ %{}) do
    load_all(fn page -> User.list_users(page, user) end, params)
  end

  def load_users_for_socket(socket, params \\ %{}) do
    if admin_socket?(socket),
      do: load_users(params),
      else: load_users_for_user(socket.assigns.current_user, params)
  end

  def load_users_for_socket_result(socket, params \\ %{}),
    do: AdminReadSupport.users_page(socket, params)

  def load_api_keys_for_socket(socket) do
    case ApiKey.list(current_user_id(socket), authorization_options(socket)) do
      {:ok, rows} -> rows
      _ -> []
    end
  end

  @doc "读取 API Key 元数据并保留失败结果，供 LiveView 刷新反馈使用。"
  def load_api_keys_for_socket_result(socket), do: AdminReadSupport.api_keys(socket)

  def load_posts, do: load_all(&Post.list_posts/1)
  def load_posts(options) when is_list(options), do: load_authorized(&Post.list_posts/2, options)
  def load_posts_for_socket(socket), do: load_posts(authorization_options(socket))

  @doc "读取岗位列表并保留失败结果，供 LiveView 刷新反馈使用。"
  def load_posts_for_socket_result(socket), do: AdminReadSupport.posts(socket)
  def load_configs, do: load_all(&Config.list_configs/1)

  def load_configs(options) when is_list(options),
    do: load_authorized(&Config.list_configs/2, options)

  def load_configs_for_socket(socket), do: load_configs(authorization_options(socket))

  @doc "读取系统配置并保留失败结果，供 LiveView 刷新反馈使用。"
  def load_configs_for_socket_result(socket, params \\ %{}),
    do: AdminReadSupport.configs(socket, params)

  def load_jobs, do: load_all(&Job.list_jobs/1)
  def load_jobs(options) when is_list(options), do: load_authorized(&Job.list_jobs/2, options)
  def load_jobs_for_socket(socket), do: load_jobs(authorization_options(socket))

  def load_jobs_for_socket_result(socket), do: AdminReadSupport.jobs(socket)

  def load_job_logs, do: load_all(&Job.list_job_logs/1)

  def load_job_logs(options) when is_list(options),
    do: load_authorized(&Job.list_job_logs/2, options)

  def load_job_logs_for_socket(socket), do: load_job_logs(authorization_options(socket))

  def load_job_logs_for_socket_result(socket), do: AdminReadSupport.job_logs(socket)

  def load_notices, do: load_all(&Notice.list_notices/1)

  def load_notices(options) when is_list(options),
    do: load_authorized(&Notice.list_notices/2, options)

  def load_notices_for_socket(socket), do: load_notices(authorization_options(socket))

  @doc "读取公告列表并保留失败结果，供 LiveView 刷新反馈使用。"
  def load_notices_for_socket_result(socket, params \\ %{}),
    do: AdminReadSupport.notices(socket, params)

  def page_rows(rows, page_num, page_size), do: Pagination.page_rows(rows, page_num, page_size)

  def load_dict_data(""), do: []

  def load_dict_data(dict_type),
    do: load_all(&Dictionary.list_dict_data/1, %{"dictType" => dict_type})

  def load_dict_data("", _options), do: []

  def load_dict_data(dict_type, options) when is_list(options),
    do: load_authorized(&Dictionary.list_dict_data/2, options, %{"dictType" => dict_type})

  def load_dict_data_for_socket(socket, dict_type) do
    if dict_type_allowed?(socket, dict_type),
      do: load_dict_data(dict_type, authorization_options(socket)),
      else: []
  end

  @doc "读取字典条目并保留失败结果，供 LiveView 选择类型反馈使用。"
  def load_dict_data_for_socket_result(socket, dict_type),
    do: AdminReadSupport.dictionary_data(socket, dict_type, authorization_options(socket))

  def dict_type_allowed?(socket, dict_type) when is_binary(dict_type) do
    admin_socket?(socket) or
      ("dictionary:read" in List.wrap(socket.assigns[:permissions]) and
         Enum.any?(socket.assigns[:dict_type_rows] || [], &(&1["dictType"] == dict_type)))
  end

  def dict_type_allowed?(_socket, _dict_type), do: false

  def load_dictionary(selected), do: load_dictionary(selected, [], %{})

  def load_dictionary_for_socket(socket, selected),
    do: load_dictionary(selected, authorization_options(socket), %{})

  def load_dictionary_for_socket(socket, selected, params),
    do: load_dictionary(selected, authorization_options(socket), params)

  @doc "读取字典类型和条目并保留失败结果，供 LiveView 刷新反馈使用。"
  def load_dictionary_for_socket_result(socket, selected, params \\ %{}),
    do: AdminReadSupport.dictionary(socket, selected, params)

  def load_dictionary(selected, options) when is_list(options),
    do: load_dictionary(selected, options, %{})

  def load_dictionary(selected, options, params) when is_list(options) and is_map(params) do
    types =
      if options == [],
        do: load_all(&Dictionary.list_dict_types/1, params),
        else: load_authorized(&Dictionary.list_dict_types/2, options, params)

    selected =
      if selected != "" and Enum.any?(types, &(&1["dictType"] == selected)),
        do: selected,
        else: List.first(types, %{})["dictType"] || ""

    data = if options == [], do: load_dict_data(selected), else: load_dict_data(selected, options)
    %{types: types, selected: selected, data: data}
  end

  def load_logs, do: load_logs([], %{})

  def load_logs(options) when is_list(options), do: load_logs(options, %{})

  def load_logs(options, filters) when is_list(options) and is_map(filters) do
    login_filter = Map.get(filters, "login", %{})
    operation_filter = Map.get(filters, "operation", %{})

    %{
      login_log_rows:
        load_log_rows(
          options,
          &Log.list_login_logs/1,
          &Log.list_login_logs/2,
          login_filter,
          "login-logs"
        ),
      operation_log_rows:
        load_log_rows(
          options,
          &Log.list_operation_logs/1,
          &Log.list_operation_logs/2,
          operation_filter,
          "operation-logs"
        )
    }
  end

  def load_logs_for_socket(socket), do: load_logs_for_socket(socket, %{})

  def load_logs_for_socket(socket, filters) when is_map(filters) do
    if admin_socket?(socket) do
      load_logs(authorization_options(socket), filters)
    else
      logs_for_permissions(socket.assigns.permissions, authorization_options(socket), filters)
    end
  end

  @doc "读取审计日志并保留失败结果，供 LiveView 刷新反馈使用。"
  def load_logs_for_socket_result(socket, filters \\ %{}) when is_map(filters),
    do: AdminReadSupport.logs(socket, filters)

  defp logs_for_permissions(permissions, options, filters) do
    permissions = List.wrap(permissions)
    login_filter = Map.get(filters, "login", %{})
    operation_filter = Map.get(filters, "operation", %{})

    %{
      login_log_rows:
        if("login-log:read" in permissions,
          do: load_authorized(&Log.list_login_logs/2, options, login_filter),
          else: []
        ),
      operation_log_rows:
        if("operation-log:read" in permissions,
          do: load_authorized(&Log.list_operation_logs/2, options, operation_filter),
          else: []
        )
    }
  end

  defp empty_dictionary, do: %{types: [], selected: "", data: []}
  defp load_all(fetcher, params \\ %{}), do: Excel.all_rows(fetcher, params)

  # 登录时预加载隐藏的审计列表；当前页面会再执行带错误反馈的单表读取。
  defp load_log_rows([], admin_fetcher, _authorized_fetcher, params, panel) do
    load_all(admin_fetcher, params)
  rescue
    _error ->
      Logger.warning(
        "admin dashboard audit preload failed; panel read will report its own result",
        panel: panel
      )

      []
  end

  defp load_log_rows(options, _admin_fetcher, authorized_fetcher, params, _panel),
    do: load_authorized(authorized_fetcher, options, params)

  defp load_authorized(fetcher, options, params \\ %{}) do
    case Excel.all_rows_result(fn page -> fetcher.(page, options) end, params) do
      {:ok, rows} -> rows
      {:error, _reason} -> []
    end
  end

  def empty_notice_form, do: Forms.empty_notice_form()
  def empty_dept_form, do: Forms.empty_dept_form()
  def empty_post_form, do: Forms.empty_post_form()
  def empty_role_form, do: Forms.empty_role_form()
  def empty_menu_form, do: Forms.empty_menu_form()
  def empty_user_form, do: Forms.empty_user_form()
  def empty_config_form, do: Forms.empty_config_form()
  def empty_dict_type_form, do: Forms.empty_dict_type_form()
  def empty_dict_data_form, do: Forms.empty_dict_data_form()
  def empty_dict_data_form(dict_type), do: Forms.empty_dict_data_form(dict_type)
  def empty_job_form, do: Forms.empty_job_form()
  def empty_api_key_form, do: %{name: "", scopes: "", expires_at: ""}
  def empty_profile_form, do: Forms.empty_profile_form()
  def empty_password_form, do: Forms.empty_password_form()

  def notice_form_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> inspect()
  end

  def load_depts_for_user(user) do
    OrganizationData.load_depts(user)
  end

  def load_depts_for_socket(socket) do
    if admin_socket?(socket),
      do: load_depts(),
      else: load_depts_for_user(socket.assigns.current_user)
  end

  def load_depts do
    OrganizationData.load_depts()
  end

  def load_roles, do: OrganizationData.load_roles([])
  def load_roles(options) when is_list(options), do: OrganizationData.load_roles(options)

  def load_roles_for_socket(socket), do: load_roles(authorization_options(socket))

  def data_scope_label(scope), do: OrganizationData.data_scope_label(scope)

  def load_menus, do: OrganizationData.load_menus([])
  def load_menus(options) when is_list(options), do: OrganizationData.load_menus(options)
  def load_menus_for_socket(socket), do: load_menus(authorization_options(socket))

  def menu_depth(parent_id, menus, seen), do: OrganizationData.menu_depth(parent_id, menus, seen)

  def menu_type_label(type, is_button),
    do: OrganizationData.menu_type_label(type, is_button)

  def dept_depth(ancestors), do: OrganizationData.dept_depth(ancestors)

  def assign_monitor(socket, feedback \\ nil) do
    MonitorSupport.assign_monitor(socket, feedback)
  end

  def assign_monitor_resource(socket, resource),
    do: MonitorSupport.assign_monitor_resource(socket, resource)

  def monitor_access?(socket), do: MonitorSupport.access?(socket)

  def assign_profile(socket, refresh? \\ false) do
    case User.profile(socket.assigns.current_user["userId"]) do
      {:ok, profile} ->
        profile_user = profile["user"] || profile
        dirty? = socket.assigns[:profile_dirty] == true

        socket =
          assign(socket,
            active_panel: "profile",
            profile_baseline_form: profile_user,
            profile_loaded: true,
            password_form: empty_password_form(),
            profile_feedback: profile_refresh_feedback(dirty?, refresh?)
          )

        if dirty? do
          socket
        else
          assign(socket, profile_form: profile_user, profile_dirty: false)
        end

      _ ->
        assign(socket, active_panel: "profile", profile_feedback: @profile_unavailable_feedback)
    end
  rescue
    # 数据库读取异常时保留已有资料和加载状态，页面仍可重试。
    _error ->
      assign(socket, active_panel: "profile", profile_feedback: @profile_unavailable_feedback)
  end

  defp profile_refresh_feedback(true, _refresh?),
    do: "资料已重新读取；未保存的修改仍保留。"

  defp profile_refresh_feedback(false, true), do: "个人资料已刷新。"
  defp profile_refresh_feedback(false, false), do: nil

  def normalize_options_param(params) do
    options =
      params["configOptions"]
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    Map.put(params, "configOptions", Jason.encode!(options))
  end

  # 将服务端失败转换为带级别的反馈，页面据此选择警示语义和视觉样式。
  def form_error({:error, %Ecto.Changeset{} = changeset}),
    do: Feedback.error(:validation_failed, notice_form_error(changeset))

  def form_error({:error, reason}), do: Feedback.from_reason(reason)
  def form_error(:error), do: Feedback.error(:internal_error, "操作失败")
  def form_error(_other), do: Feedback.error(:internal_error, "操作失败")

  def read_error_feedback(reason, message),
    do: AdminReadSupport.read_error_feedback(reason, message)

  def human_error(reason), do: Feedback.human_error(reason)

  def admin_socket?(socket) do
    case socket.assigns[:current_user] do
      user when is_map(user) ->
        Authz.admin?(Map.put(user, :permissions, List.wrap(socket.assigns[:permissions])))

      _ ->
        false
    end
  end

  def authenticated_socket?(socket), do: is_map(socket.assigns.current_user)

  defp current_user_id(socket),
    do: socket.assigns.current_user["userId"] || socket.assigns.current_user[:user_id]

  @doc "Returns the current LiveView principal as service-layer authorization options."
  def authorization_options(socket, permission \\ nil) do
    principal =
      (socket.assigns[:current_user] || %{})
      |> Map.put(:permissions, List.wrap(socket.assigns[:permissions]))

    authorization = %{principal: principal}

    authorization =
      if is_binary(permission),
        do: Map.put(authorization, :permission, permission),
        else: authorization

    [authorization: authorization]
  end

  @doc "Checks a permission retained by the authenticated LiveView session."
  def permission_socket?(socket, permission) when is_binary(permission) do
    case socket.assigns[:current_user] do
      user when is_map(user) ->
        Authz.allowed?(
          Map.put(user, :permissions, List.wrap(socket.assigns[:permissions])),
          permission
        )

      _ ->
        false
    end
  end

  def permission_socket?(_socket, _permission), do: false

  def panel_allowed?(socket, panel) do
    admin_socket?(socket) or
      (authenticated_socket?(socket) and
         (panel in ["overview", "profile"] or
            (Enum.any?(Map.get(@panel_permissions, panel, []), &permission_socket?(socket, &1)) and
               scope_panel_allowed?(
                 socket.assigns.current_user,
                 panel,
                 socket.assigns[:permissions]
               ))))
  end

  defp scope_panel_allowed?(nil, _panel, _permissions), do: true

  defp scope_panel_allowed?(user, panel, permissions) when is_map(user) do
    if is_nil(Map.get(user, :user_id, Map.get(user, "userId"))) do
      true
    else
      principal = Map.put(user, :permissions, List.wrap(permissions))

      case Map.get(@panel_resources, panel) do
        nil ->
          true

        resource ->
          Authz.resource_scope_allowed?(principal, resource, panel_scope_context(resource))
      end
    end
  end

  defp scope_panel_allowed?(_user, _panel, _permissions), do: false

  defp panel_scope_context(resource) when resource in [:job, :notice], do: %{defer_owner: true}

  defp panel_scope_context(_resource), do: %{}

  defdelegate expire_authentication(socket, message),
    to: KeystonePhoenixWeb.Live.AdminAuthentication
end
