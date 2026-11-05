defmodule KeystonePhoenixWeb.Live.AdminSupport do
  @moduledoc "Shared dashboard loading, form defaults, and authorization helpers."

  import Phoenix.Component, only: [assign: 2]

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Log
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Monitor
  alias KeystonePhoenix.Notice
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.User

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

  def load_users, do: User.list_users(%{"pageSize" => 50}).rows
  def load_posts, do: Post.list_posts(%{"pageSize" => 50}).rows
  def load_configs, do: Config.list_configs(%{"pageSize" => 50}).rows
  def load_jobs, do: Job.list_jobs(%{"pageSize" => 50}).rows
  def load_job_logs, do: Job.list_job_logs(%{"pageSize" => 50}).rows

  def load_notices, do: Notice.list_notices(%{"pageSize" => 50}).rows

  def load_dict_data(""), do: []

  def load_dict_data(dict_type),
    do: Dictionary.list_dict_data(%{"dictType" => dict_type, "pageSize" => 100}).rows

  def load_dictionary(selected) do
    types = Dictionary.list_dict_types(%{"pageSize" => 50}).rows

    selected =
      if selected != "" and Enum.any?(types, &(&1["dictType"] == selected)),
        do: selected,
        else: List.first(types, %{})["dictType"] || ""

    %{types: types, selected: selected, data: load_dict_data(selected)}
  end

  def load_logs do
    %{
      login_log_rows: Log.list_login_logs(%{"pageSize" => 50}).rows,
      operation_log_rows: Log.list_operation_logs(%{"pageSize" => 50}).rows
    }
  end

  def empty_notice_form do
    %{
      "noticeId" => "",
      "noticeTitle" => "",
      "noticeType" => 2,
      "noticeContent" => "",
      "status" => 1,
      "remark" => ""
    }
  end

  def empty_dept_form do
    %{
      "deptId" => "",
      "parentId" => "0",
      "deptName" => "",
      "orderNum" => 0,
      "leaderId" => "",
      "leaderName" => "",
      "phone" => "",
      "email" => "",
      "status" => 1
    }
  end

  def empty_post_form do
    %{
      "postId" => "",
      "postCode" => "",
      "postName" => "",
      "postSort" => 0,
      "status" => 1,
      "remark" => ""
    }
  end

  def empty_role_form do
    %{
      "roleId" => "",
      "roleName" => "",
      "roleKey" => "",
      "roleSort" => 0,
      "dataScope" => 1,
      "deptIdSet" => "",
      "status" => 1,
      "menuIds" => "",
      "remark" => ""
    }
  end

  def empty_menu_form do
    %{
      "menuId" => "",
      "menuName" => "",
      "menuType" => 1,
      "routerName" => "",
      "parentId" => 0,
      "path" => "",
      "isButton" => "false",
      "permission" => "",
      "metaInfo" => "{}",
      "status" => 1,
      "remark" => ""
    }
  end

  def empty_user_form do
    %{
      "userId" => "",
      "username" => "",
      "nickname" => "",
      "password" => "",
      "deptId" => "",
      "postId" => "",
      "roleId" => "",
      "email" => "",
      "phoneNumber" => "",
      "sex" => 2,
      "status" => 1,
      "remark" => ""
    }
  end

  def empty_config_form do
    %{
      "configId" => "",
      "configName" => "",
      "configKey" => "",
      "configOptions" => "",
      "configValue" => "",
      "isAllowChange" => "true",
      "remark" => ""
    }
  end

  def empty_dict_type_form do
    %{"dictId" => "", "dictName" => "", "dictType" => "", "status" => 1, "remark" => ""}
  end

  def empty_dict_data_form(dict_type \\ "") do
    %{
      "dictCode" => "",
      "dictType" => dict_type,
      "dictLabel" => "",
      "dictValue" => 0,
      "dictSort" => 0,
      "isDefault" => "false",
      "cssClass" => "",
      "listClass" => "",
      "status" => 1,
      "remark" => ""
    }
  end

  def empty_job_form do
    %{
      "jobId" => "",
      "jobName" => "",
      "jobGroup" => "DEFAULT",
      "invokeTarget" => "system:health",
      "jobParams" => "",
      "cronExpression" => "0 */5 * * * *",
      "concurrent" => 0,
      "status" => 1,
      "remark" => ""
    }
  end

  def empty_profile_form do
    %{"nickname" => "", "email" => "", "phoneNumber" => "", "sex" => 2, "avatar" => ""}
  end

  def empty_password_form do
    %{"oldPassword" => "", "newPassword" => ""}
  end

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
    roles = Role.list_roles(%{"pageSize" => 50}).rows
    user_counts = Role.user_counts(Enum.map(roles, & &1["roleId"]))

    roles
    |> Enum.map(fn role ->
      role
      |> Map.put("dataScopeStr", data_scope_label(role["dataScope"]))
      |> Map.put("statusStr", if(role["status"] == 1, do: "正常", else: "停用"))
      |> Map.put("userCount", Map.get(user_counts, role["roleId"], 0))
    end)
  end

  def load_role_users(role_id) do
    params = %{"pageSize" => 50}

    %{
      allocated: Role.list_allocated_users(role_id, params).rows,
      unallocated: Role.list_unallocated_users(role_id, params).rows
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

  def menu_type_label(_type, 1), do: "按钮"
  def menu_type_label(2, _is_button), do: "目录"
  def menu_type_label(1, _is_button), do: "菜单"
  def menu_type_label(0, _is_button), do: "权限"
  def menu_type_label(_type, _is_button), do: "其他"

  def dept_depth(nil), do: 0

  def dept_depth(ancestors) do
    max(length(String.split(ancestors, ",", trim: true)) - 1, 0)
  end

  def assign_monitor(socket, feedback \\ nil) do
    monitor = load_monitor()

    assign(socket,
      active_panel: "monitor",
      monitor_server_info: monitor.server_info,
      monitor_cache_info: monitor.cache_info,
      online_user_rows: monitor.online_users,
      network_status: monitor.network_status,
      monitor_feedback: feedback || monitor.feedback
    )
  end

  def load_monitor do
    {server_info, server_error} =
      case Monitor.server_info() do
        {:ok, info} -> {info, nil}
        {:error, :unavailable} -> {%{}, "主机监控数据暂不可用"}
      end

    {cache_info, cache_error} =
      case Monitor.redis_cache_info() do
        {:ok, info} -> {info, nil}
        _ -> {%{}, "Redis 监控数据暂不可用"}
      end

    {online_users, online_error} =
      case Monitor.online_users() do
        {:ok, %{rows: rows}} -> {rows, nil}
        _ -> {[], "在线会话数据暂不可用"}
      end

    feedback = Enum.find([server_error, cache_error, online_error], &is_binary/1)

    %{
      server_info: server_info,
      cache_info: cache_info,
      online_users: online_users,
      network_status: Monitor.network_status(),
      feedback: feedback
    }
  end

  def assign_profile(socket) do
    case User.profile(socket.assigns.current_user["userId"]) do
      {:ok, profile} ->
        assign(socket,
          active_panel: "profile",
          profile_form: profile,
          password_form: empty_password_form(),
          profile_feedback: nil
        )

      _ ->
        assign(socket, active_panel: "profile", profile_feedback: "个人资料暂不可用")
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

  def form_error({:error, %Ecto.Changeset{} = changeset}), do: notice_form_error(changeset)
  def form_error({:error, reason}), do: human_error(reason)
  def form_error(:error), do: "操作失败"
  def form_error(other), do: inspect(other)

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

  def expire_authentication(socket, message) do
    Auth.logout(socket.assigns.refresh_token)

    assign(socket,
      current_user: nil,
      access_token: nil,
      refresh_token: nil,
      active_panel: "overview",
      password: "",
      login_error: message
    )
  end
end
