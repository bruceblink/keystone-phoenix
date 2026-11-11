defmodule KeystonePhoenixWeb.Live.AdminSupport do
  @moduledoc "Shared dashboard loading, form defaults, and authorization helpers."

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Log
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Notice
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Role
  alias KeystonePhoenixWeb.Live.AdminPages.Forms
  alias KeystonePhoenixWeb.Live.AdminPages.MonitorSnapshot
  alias KeystonePhoenix.User
  alias KeystonePhoenixWeb.Live.AdminPages.Feedback
  alias KeystonePhoenixWeb.Live.Authentication

  @panel_permissions %{
    "depts" => ["system:dept:list"],
    "posts" => ["system:post:list"],
    "roles" => ["system:role:list"],
    "menus" => ["system:menu:list"],
    "users" => ["system:user:list"],
    "configs" => ["system:config:list"],
    "dicts" => ["system:dict:list"],
    "notices" => ["system:notice:list"],
    "logs" => ["monitor:logininfor:list", "monitor:operlog:list"],
    "jobs" => ["system:job:list"],
    "job-logs" => ["system:job:list"],
    "monitor" => ["monitor:cache:list", "monitor:server:list", "monitor:online:list"]
  }

  def load_dashboard do
    logs = load_logs()
    dictionary = load_dictionary("")

    %{
      user_rows: load_users(),
      dept_rows: load_depts(),
      post_rows: load_posts(),
      role_rows: load_roles(),
      selected_role_id: "",
      selected_role_name: "",
      allocated_role_user_rows: [],
      unallocated_role_user_rows: [],
      role_user_feedback: nil,
      menu_rows: load_menus(),
      notice_rows: load_notices(),
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
      selected_role_id: "",
      selected_role_name: "",
      allocated_role_user_rows: [],
      unallocated_role_user_rows: [],
      role_user_feedback: nil,
      menu_rows: [],
      notice_rows: [],
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
    dictionary = if access["dicts"], do: load_dictionary(""), else: empty_dictionary()
    logs = logs_for_permissions(permissions)

    dashboard
    |> Map.put(:dept_rows, if(access["depts"], do: load_depts(), else: []))
    |> Map.put(:post_rows, if(access["posts"], do: load_posts(), else: []))
    |> Map.put(:role_rows, if(access["roles"], do: load_roles(), else: []))
    |> Map.put(:menu_rows, if(access["menus"], do: load_menus(), else: []))
    |> Map.put(:user_rows, if(access["users"], do: load_users_for_user(user), else: []))
    |> Map.put(:config_rows, if(access["configs"], do: load_configs(), else: []))
    |> Map.put(:dict_type_rows, dictionary.types)
    |> Map.put(:dict_data_rows, dictionary.data)
    |> Map.put(:selected_dict_type, dictionary.selected)
    |> Map.put(:notice_rows, if(access["notices"], do: load_notices(), else: []))
    |> Map.put(:job_rows, if(access["jobs"], do: load_jobs(), else: []))
    |> Map.put(:job_log_rows, if(access["job-logs"], do: load_job_logs(), else: []))
    |> Map.put(:login_log_rows, logs.login_log_rows)
    |> Map.put(:operation_log_rows, logs.operation_log_rows)
  end

  @doc "Returns panel visibility for a permission list."
  def panel_access(permissions, is_admin \\ false) do
    Enum.into(@panel_permissions, %{}, fn {panel, required} ->
      {panel, is_admin or Enum.any?(required, &(&1 in List.wrap(permissions)))}
    end)
    |> Map.put("overview", true)
    |> Map.put("profile", true)
  end

  def load_users, do: load_all(&User.list_users/1)

  def load_users_for_user(user) do
    load_all(fn params -> User.list_users(params, user) end)
  end

  def load_users_for_socket(socket) do
    if admin_socket?(socket),
      do: load_users(),
      else: load_users_for_user(socket.assigns.current_user)
  end

  def load_posts, do: load_all(&Post.list_posts/1)
  def load_configs, do: load_all(&Config.list_configs/1)
  def load_jobs, do: load_all(&Job.list_jobs/1)
  def load_job_logs, do: load_all(&Job.list_job_logs/1)

  def load_notices, do: load_all(&Notice.list_notices/1)

  def page_rows(rows, page_num, page_size) when is_list(rows) do
    page_num = if is_integer(page_num) and page_num > 0, do: page_num, else: 1
    page_size = if is_integer(page_size) and page_size > 0, do: page_size, else: 50
    Enum.slice(rows, (page_num - 1) * page_size, page_size)
  end

  def page_rows(_rows, _page_num, _page_size), do: []

  def load_dict_data(""), do: []

  def load_dict_data(dict_type),
    do: load_all(&Dictionary.list_dict_data/1, %{"dictType" => dict_type})

  def load_dict_data_for_socket(socket, dict_type) do
    if dict_type_allowed?(socket, dict_type), do: load_dict_data(dict_type), else: []
  end

  def dict_type_allowed?(socket, dict_type) when is_binary(dict_type) do
    admin_socket?(socket) or
      ("system:dict:list" in List.wrap(socket.assigns[:permissions]) and
         Enum.any?(socket.assigns[:dict_type_rows] || [], &(&1["dictType"] == dict_type)))
  end

  def dict_type_allowed?(_socket, _dict_type), do: false

  def load_dictionary(selected) do
    types = load_all(&Dictionary.list_dict_types/1)

    selected =
      if selected != "" and Enum.any?(types, &(&1["dictType"] == selected)),
        do: selected,
        else: List.first(types, %{})["dictType"] || ""

    %{types: types, selected: selected, data: load_dict_data(selected)}
  end

  def load_logs do
    %{
      login_log_rows: load_all(&Log.list_login_logs/1),
      operation_log_rows: load_all(&Log.list_operation_logs/1)
    }
  end

  def load_logs_for_socket(socket) do
    if admin_socket?(socket) do
      load_logs()
    else
      logs_for_permissions(socket.assigns.permissions)
    end
  end

  defp logs_for_permissions(permissions) do
    permissions = List.wrap(permissions)

    %{
      login_log_rows:
        if("monitor:logininfor:list" in permissions,
          do: load_all(&Log.list_login_logs/1),
          else: []
        ),
      operation_log_rows:
        if("monitor:operlog:list" in permissions,
          do: load_all(&Log.list_operation_logs/1),
          else: []
        )
    }
  end

  defp empty_dictionary, do: %{types: [], selected: "", data: []}

  defp load_all(fetcher, params \\ %{}), do: Excel.all_rows(fetcher, params)

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
  def empty_profile_form, do: Forms.empty_profile_form()
  def empty_password_form, do: Forms.empty_password_form()

  def notice_form_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> inspect()
  end

  def load_depts do
    Department.list_depts()
    |> Enum.map(fn dept -> Map.put(dept, "depth", dept_depth(dept["ancestors"])) end)
  end

  def load_roles do
    roles = Excel.all_rows(&Role.list_roles/1)
    user_counts = Role.user_counts(Enum.map(roles, & &1["roleId"]))

    roles
    |> Enum.map(fn role ->
      role
      |> Map.put("dataScopeStr", data_scope_label(role["dataScope"]))
      |> Map.put("statusStr", if(role["status"] == 1, do: "正常", else: "停用"))
      |> Map.put("userCount", Map.get(user_counts, role["roleId"], 0))
    end)
  end

  def load_role_users(role_id, actor \\ nil) do
    %{
      allocated:
        Excel.all_rows(fn params ->
          Role.list_allocated_users(role_id, params, actor)
        end),
      unallocated:
        Excel.all_rows(fn params ->
          Role.list_unallocated_users(role_id, params, actor)
        end)
    }
  end

  def data_scope_label(1), do: "全部数据"
  def data_scope_label(2), do: "自定义数据"
  def data_scope_label(3), do: "本部门数据"
  def data_scope_label(4), do: "本部门及以下"
  def data_scope_label(5), do: "仅本人数据"
  def data_scope_label(_scope), do: "未知"

  def load_menus do
    menus = Menu.list_menus()
    by_id = Map.new(menus, &{&1["menuId"], &1})

    Enum.map(menus, fn menu ->
      menu
      |> Map.put("depth", menu_depth(menu["parentId"], by_id, MapSet.new([menu["menuId"]])))
      |> Map.put("menuTypeStr", menu_type_label(menu["menuType"], menu["isButton"]))
      |> Map.put("statusStr", if(menu["status"] == 1, do: "正常", else: "停用"))
    end)
  end

  def menu_depth(0, _menus, _seen), do: 0

  def menu_depth(parent_id, menus, seen) do
    if MapSet.member?(seen, parent_id) do
      0
    else
      case Map.get(menus, parent_id) do
        nil -> 0
        parent -> 1 + menu_depth(parent["parentId"], menus, MapSet.put(seen, parent_id))
      end
    end
  end

  def menu_type_label(_type, true), do: "按钮"
  def menu_type_label(2, _is_button), do: "目录"
  def menu_type_label(1, _is_button), do: "菜单"
  def menu_type_label(0, _is_button), do: "权限"
  def menu_type_label(_type, _is_button), do: "其他"

  def dept_depth(nil), do: 0

  def dept_depth(ancestors) do
    max(length(String.split(ancestors, ",", trim: true)) - 1, 0)
  end

  def assign_monitor(socket, feedback \\ nil) do
    admin? = admin_socket?(socket)
    permissions = List.wrap(socket.assigns[:permissions])
    page_num = get_in(socket.assigns, [:page_nums, "online-users"]) || 1
    page_size = get_in(socket.assigns, [:page_sizes, "online-users"]) || 50
    monitor = MonitorSnapshot.load(admin?, permissions, page_num, page_size)

    assign(socket,
      active_panel: "monitor",
      monitor_server_info: monitor.server_info,
      monitor_cache_info: monitor.cache_info,
      online_user_rows: monitor.online_users,
      online_user_total: monitor.online_user_total,
      network_status: monitor.network_status,
      monitor_feedback: feedback || monitor.feedback
    )
  end

  def monitor_access?(socket) do
    admin_socket?(socket) or
      Enum.any?(
        ["monitor:cache:list", "monitor:server:list", "monitor:online:list"],
        &permission_socket?(socket, &1)
      )
  end

  def assign_profile(socket) do
    case User.profile(socket.assigns.current_user["userId"]) do
      {:ok, profile} ->
        profile_user = profile["user"] || profile

        assign(socket,
          active_panel: "profile",
          profile_form: profile_user,
          password_form: empty_password_form(),
          profile_feedback: nil
        )

      _ ->
        assign(socket, active_panel: "profile", profile_feedback: Feedback.error("个人资料暂不可用"))
    end
  end

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
    do: Feedback.error(notice_form_error(changeset))

  def form_error({:error, reason}), do: Feedback.error(human_error(reason))
  def form_error(:error), do: Feedback.error("操作失败")
  def form_error(other), do: Feedback.error(inspect(other))

  def human_error(:not_found), do: "记录不存在"
  def human_error(:invalid_ids), do: "编号无效"
  def human_error(:invalid_id), do: "编号无效"
  def human_error(:has_users), do: "记录仍被用户使用"
  def human_error(:has_children), do: "记录仍有下级数据"
  def human_error(:parent_not_found), do: "上级记录不存在"
  def human_error(:invalid_parent), do: "上级记录无效"
  def human_error(:protected_role), do: "管理员角色不能删除"
  def human_error(:protected_user), do: "当前用户或管理员不能删除"
  def human_error(:update_failed), do: "更新失败"
  def human_error(:has_data), do: "字典类型仍有数据"
  def human_error(:invalid_params), do: "参数无效"
  def human_error(:invalid_status), do: "状态无效"
  def human_error(:role_unavailable), do: "角色已停用"
  def human_error(:menu_not_found), do: "菜单不存在"
  def human_error(:invalid_log), do: "日志参数无效"
  def human_error(:unavailable), do: "服务暂不可用"
  def human_error(:invalid_upload), do: "头像文件无效"
  def human_error(:empty_upload), do: "头像文件不能为空"
  def human_error(:file_too_large), do: "头像文件不能超过 50 MB"
  def human_error(:filename_too_long), do: "头像文件名过长"
  def human_error(:type_not_allowed), do: "头像文件类型不支持"
  def human_error(:storage_error), do: "头像文件保存失败"
  def human_error(reason), do: "操作失败：#{inspect(reason)}"

  def admin_socket?(socket),
    do: is_map(socket.assigns.current_user) and socket.assigns.current_user["isAdmin"] == 1

  def authenticated_socket?(socket), do: is_map(socket.assigns.current_user)

  @doc "Checks a permission retained by the authenticated LiveView session."
  def permission_socket?(socket, permission) when is_binary(permission) do
    admin_socket?(socket) or permission in List.wrap(socket.assigns[:permissions])
  end

  def permission_socket?(_socket, _permission), do: false

  @doc "Checks whether a dashboard panel has at least one required permission."
  def panel_allowed?(socket, panel) do
    admin_socket?(socket) or
      (authenticated_socket?(socket) and
         (panel in ["overview", "profile"] or
            Enum.any?(Map.get(@panel_permissions, panel, []), &permission_socket?(socket, &1))))
  end

  def expire_authentication(socket, message) do
    Auth.logout(socket.assigns.refresh_token)
    Authentication.expire(socket, message)
  end
end
