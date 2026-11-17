defmodule KeystonePhoenixWeb.AdminLiveIntegrationTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Mfa.Totp
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Log
  alias KeystonePhoenix.Notice
  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.SysUser

  setup do
    username = "live_admin_#{System.unique_integer([:positive])}"
    admin_role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    {:ok, user} =
      %SysUser{}
      |> SysUser.create_changeset(%{
        "username" => username,
        "nickname" => "Live 管理员",
        "password" => "Strong!123",
        "role_id" => admin_role.role_id,
        "status" => 1
      })
      |> Repo.insert()

    {:ok, user} = Repo.update(Ecto.Changeset.change(user))

    {:ok, admin: user}
  end

  @tag :integration
  test "menu filter state is preserved in the deep link", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(conn, "/")

    render_submit(view, "login", %{
      "username" => admin.username,
      "password" => "Strong!123"
    })

    render_click(view, "show-panel", %{"panel" => "menus"})
    render_submit(view, "refresh-menus", %{"menuKeyword" => "role"})

    assert live_socket(view).assigns.active_panel == "menus"
    assert live_socket(view).assigns.menu_filter == "role"
    assert live_socket(view).assigns.current_uri =~ "/menus?menus_keyword=role"

    render_click(view, "refresh-menus", %{"reset" => "true"})
    assert live_socket(view).assigns.menu_filter == ""
    assert URI.parse(live_socket(view).assigns.current_uri).path == "/menus"
    assert URI.parse(live_socket(view).assigns.current_uri).query in [nil, ""]

    render_click(view, "show-panel", %{"panel" => "depts"})
    render_submit(view, "refresh-depts", %{"deptKeyword" => "root"})
    assert live_socket(view).assigns.dept_filter["keyword"] == "root"
    assert live_socket(view).assigns.current_uri =~ "/departments?departments_keyword=root"

    render_click(view, "refresh-depts", %{"reset" => "true"})
    assert live_socket(view).assigns.dept_filter["keyword"] == ""
    assert URI.parse(live_socket(view).assigns.current_uri).path == "/departments"
  end

  @tag :integration
  test "audit filters and pages are preserved in namespaced deep links", %{
    conn: conn,
    admin: admin
  } do
    {:ok, view, _html} = live(conn, "/")

    render_submit(view, "login", %{
      "username" => admin.username,
      "password" => "Strong!123"
    })

    render_click(view, "show-panel", %{"panel" => "login-logs"})

    render_submit(view, "filter-login-logs", %{
      "loginUsername" => admin.username,
      "loginStatus" => "SUCCESS"
    })

    uri = URI.parse(live_socket(view).assigns.current_uri)
    assert uri.path == "/audit/login"

    assert URI.decode_query(uri.query || "") == %{
             "login_logs_status" => "SUCCESS",
             "login_logs_username" => admin.username
           }

    render_click(view, "paginate", %{"panel" => "login-logs", "page" => "2"})
    uri = URI.parse(live_socket(view).assigns.current_uri)
    assert uri.query =~ "login_logs_page=2"
    assert live_socket(view).assigns.page_nums["login-logs"] == 2

    render_click(view, "reset-login-log-filter")
    uri = URI.parse(live_socket(view).assigns.current_uri)
    assert uri.path == "/audit/login"
    assert uri.query in [nil, ""]

    render_click(view, "show-panel", %{"panel" => "operation-logs"})

    render_submit(view, "filter-operation-logs", %{
      "operationActor" => admin.username,
      "operationAction" => "UPDATE",
      "operationResource" => "user"
    })

    uri = URI.parse(live_socket(view).assigns.current_uri)
    assert uri.path == "/audit/operations"

    assert URI.decode_query(uri.query || "") == %{
             "operations_audit_action" => "UPDATE",
             "operations_audit_actor" => admin.username,
             "operations_audit_resource" => "user"
           }
  end

  @tag :integration
  test "admin login and user management persist through LiveView", %{conn: conn, admin: admin} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ "把平台状态"

    render_submit(view, "login", %{
      "username" => admin.username,
      "password" => "Strong!123"
    })

    assert has_element?(view, "nav[aria-label='主导航']")
    assert has_element?(view, ".app-shell > .sidebar")
    assert has_element?(view, ".app-shell > .shell-content > header.topbar")
    assert has_element?(view, ".app-shell > .shell-content > main.shell-main")
    assert has_element?(view, ".sidebar > .primary-nav")
    shell_html = render(view)
    assert shell_html =~ "Admin Console"
    assert has_element?(view, ".topbar-context .context-kicker", "Keystone")
    assert has_element?(view, ".topbar-context .context-separator", "/")
    refute has_element?(view, ".topbar-context", "管理工作台")
    refute shell_html =~ "Phoenix LiveView"
    refute shell_html =~ "Keystone Phoenix"
    assert has_element?(view, ".sidebar-foot", "API 正常")
    assert has_element?(view, ".sidebar-version", "v0.1.0 · dev")
    assert has_element?(view, "button[aria-label='通知'] svg")
    assert has_element?(view, "button[aria-label='打开个人资料'] .profile-chevron")
    assert has_element?(view, "button.logout-button[aria-label='退出']")
    assert has_element?(view, "button.logout-button svg")
    assert has_element?(view, "nav[aria-label='主导航'] .nav-item .nav-icon-svg")
    assert has_element?(view, "a[href='/api/swagger'][phx-click='close-sidebar']", "接口文档")
    refute has_element?(view, ".nav-section-title", "系统")
    render_click(view, "toggle-monitor-help")
    assert has_element?(view, ".monitor-help-panel", "如何阅读监控")
    render_click(view, "toggle-monitor-help")
    refute has_element?(view, ".monitor-help-panel")
    refute has_element?(view, ".dashboard-topbar h2")
    assert has_element?(view, "button[aria-label='打开导航']")
    refute has_element?(view, "nav[aria-label='主导航'].sidebar-open")
    render_click(view, "toggle-sidebar")
    assert has_element?(view, "button[aria-label='关闭导航']")
    assert has_element?(view, "nav[aria-label='主导航'].sidebar-open")
    assert has_element?(view, "button.sidebar-scrim[aria-label='关闭导航']")
    render_click(view, "close-sidebar")
    refute has_element?(view, "nav[aria-label='主导航'].sidebar-open")
    render_click(view, "toggle-sidebar")
    render_click(view, "show-panel", %{"panel" => "depts"})
    assert live_socket(view).assigns.active_panel == "depts"
    refute has_element?(view, "nav[aria-label='主导航'].sidebar-open")
    assert has_element?(view, "button[aria-label='通知'][phx-click='toggle-notifications']")
    render_click(view, "toggle-notifications")
    assert has_element?(view, ".notification-popover[aria-label='站内通知']")
    render_click(view, "close-notifications")
    assert has_element?(view, "button[aria-label='打开个人资料'][phx-value-panel='profile']")
    refute has_element?(view, "nav[aria-label='主导航'] button", "个人资料")
    render_click(view, "show-panel", %{"panel" => "notices"})
    assert live_socket(view).assigns.active_panel == "notices"
    assert Log.list_login_logs(%{"username" => admin.username, "pageSize" => 10}).total >= 1
    mfa_secret = enroll_liveview_factor(view, admin)
    render_click(view, "logout")
    assert has_element?(view, "#login-form")

    render_submit(view, "login", %{
      "username" => admin.username,
      "password" => "Strong!123"
    })

    assert has_element?(view, "nav[aria-label='主导航']")

    # 此用例验证策略开启后的用户写操作 step-up；直接设置策略值以保留 AAL1 测试会话。
    Repo.update!(Ecto.Changeset.change(Repo.get!(SysUser, admin.user_id), mfa_required: true))
    render_click(view, "show-panel", %{"panel" => "profile"})
    refute has_element?(view, "#profile-avatar-upload-form")

    render_submit(view, "save-profile", %{
      "nickname" => "Live 管理员",
      "email" => "live-profile@example.com",
      "phoneNumber" => "13900000000",
      "avatar" => "https://example.com/avatar.png",
      "sex" => ""
    })

    assert render(view) =~ "个人资料已保存"
    assert {:ok, updated_admin} = User.get_user(admin.user_id)
    assert updated_admin.avatar == "https://example.com/avatar.png"
    assert updated_admin.sex == 2

    render_click(view, "show-panel", %{"panel" => "users"})
    assert live_socket(view).assigns.users_server_paged
    render_click(view, "paginate", %{"panel" => "users", "page" => "2"})
    assert live_socket(view).assigns.page_nums["users"] == 2
    assert live_socket(view).assigns.user_total >= 1
    assert live_socket(view).assigns.current_uri =~ "/users?users_page=2"
    render_click(view, "paginate", %{"panel" => "users", "page" => "1"})
    render_submit(view, "filter-users", %{"username" => admin.username, "displayName" => ""})
    filtered_usernames = Enum.map(live_socket(view).assigns.user_rows, & &1["username"])
    assert filtered_usernames != []
    assert Enum.all?(filtered_usernames, &String.contains?(&1, admin.username))
    assert live_socket(view).assigns.current_uri =~ "/users?users_username="
    assert has_element?(view, "#user-query[value='#{admin.username}']")

    render_click(view, "toggle-user-selection", %{
      "user-id" => to_string(admin.user_id),
      "selected" => "true"
    })

    assert to_string(admin.user_id) in live_socket(view).assigns.selected_user_ids
    refute has_element?(view, "button[phx-click='delete-users'][disabled]")
    render_click(view, "reset-user-filter")
    assert live_socket(view).assigns.selected_user_ids == []
    render_click(view, "export-users")
    assert_push_event(view, "download-xlsx", %{filename: "users.xlsx", content: content})
    assert byte_size(content) > 100

    {:ok, import_workbook} = Excel.export(["用户名"], [["mfa_blocked_user"]], "users.xlsx")

    render_click(view, "new-user-import")

    import_file =
      file_input(view, "#user-import-form", :user_import, [
        %{
          last_modified: 1_700_000_000_000,
          name: "users.xlsx",
          content: import_workbook,
          size: byte_size(import_workbook),
          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        }
      ])

    render_upload(import_file, "users.xlsx")
    render_submit(view, "import-users", %{})
    assert render(view) =~ "导入用户需要完成二次认证"

    render_click(view, "new-user")
    assert has_element?(view, "form[phx-submit='save-user']")
    assert has_element?(view, "input[name='roleCodes[]']")
    render_click(view, "edit-user", %{"user-id" => "999999999"})
    assert has_element?(view, "#user-feedback[role='alert']")
    assert render(view) =~ "找不到指定用户"

    created_username = "live_user_#{System.unique_integer([:positive])}"

    render_submit(view, "save-user", %{
      "userId" => "",
      "username" => created_username,
      "nickname" => "Live 用户",
      "password" => "Created!123",
      "email" => "live@example.com",
      "phoneNumber" => "",
      "sex" => "2",
      "deptId" => "",
      "postId" => "",
      "roleId" => "",
      "status" => "1",
      "remark" => ""
    })

    assert render(view) =~ "此操作需要完成二次认证"
    complete_liveview_step_up(view, mfa_secret)

    render_submit(view, "save-user", %{
      "userId" => "",
      "username" => created_username,
      "nickname" => "Live 用户",
      "password" => "Created!123",
      "email" => "live@example.com",
      "phoneNumber" => "",
      "sex" => "2",
      "deptId" => "",
      "postId" => "",
      "roleId" => "",
      "status" => "1",
      "remark" => ""
    })

    assert render(view) =~ "用户已创建"
    assert {:ok, created} = User.get_user_by_username(created_username)
    assert created.nickname == "Live 用户"

    render_click(view, "edit-user", %{"user-id" => to_string(created.user_id)})
    refute has_element?(view, "#user-reset-password-form")

    render_submit(view, "reset-user-password", %{
      "userId" => to_string(created.user_id),
      "password" => "Reset!456"
    })

    assert render(view) =~ "用户密码已重置"
    assert {:ok, updated} = User.get_user(created.user_id)
    assert Bcrypt.verify_pass("Reset!456", updated.password)

    role_name = "Live 角色 #{System.unique_integer([:positive])}"
    role_key = "live_role_#{System.unique_integer([:positive])}"

    render_click(view, "show-panel", %{"panel" => "roles"})

    render_submit(view, "save-role", %{
      "roleId" => "",
      "roleName" => role_name,
      "roleKey" => role_key,
      "roleSort" => "10",
      "dataScope" => "ALL",
      "deptIdSet" => "",
      "status" => "1",
      "menuIds" => "",
      "remark" => ""
    })

    assert render(view) =~ "角色已创建"
    role = Role.list_roles(%{"roleName" => role_name, "pageSize" => 10}).rows |> List.first()
    assert role["roleName"] == role_name

    render_click(view, "select-role", %{"role-id" => to_string(role["roleId"])})
    assert has_element?(view, "#role-user-management")
    render_click(view, "assign-role-user", %{"user-id" => to_string(created.user_id)})
    assert render(view) =~ "角色用户已更新"
    assert {:ok, assigned} = User.get_user(created.user_id)
    assert assigned.role_id == role["roleId"]
    assert has_element?(view, "#role-user-management")

    render_click(view, "select-role", %{"role-id" => to_string(role["roleId"])})
    render_click(view, "unassign-role-user", %{"user-id" => to_string(created.user_id)})
    assert {:ok, unassigned} = User.get_user(created.user_id)
    assert is_nil(unassigned.role_id)

    job_name = "Live 任务 #{System.unique_integer([:positive])}"

    render_click(view, "show-panel", %{"panel" => "jobs"})

    render_submit(view, "save-job", %{
      "jobId" => "",
      "jobName" => job_name,
      "jobGroup" => "DEFAULT",
      "invokeTarget" => "demoJobTask.printHeartbeat()",
      "jobParams" => "",
      "cronExpression" => "* * * * * *",
      "concurrent" => "0",
      "status" => "1",
      "remark" => ""
    })

    assert render(view) =~ "任务已创建"
    render_submit(view, "filter-jobs", %{"jobKeyword" => job_name})
    assert live_socket(view).assigns.job_total == 1
    assert Enum.any?(live_socket(view).assigns.job_rows, &(&1["jobName"] == job_name))

    job = Job.list_jobs(%{"jobName" => job_name, "pageSize" => 10}).rows |> List.first()
    assert job["jobName"] == job_name

    render_click(view, "cancel-job", %{"job-id" => to_string(job["jobId"])})
    assert render(view) =~ "没有正在运行的任务"

    config_name = "Live 配置 #{System.unique_integer([:positive])}"
    config_key = "live.config.#{System.unique_integer([:positive])}"

    render_click(view, "show-panel", %{"panel" => "configs"})

    render_submit(view, "save-config", %{
      "configId" => "",
      "configName" => config_name,
      "configKey" => config_key,
      "configOptions" => "alpha,beta",
      "configValue" => "alpha",
      "isAllowChange" => "true",
      "remark" => ""
    })

    assert render(view) =~ "配置已创建"

    config =
      Config.list_configs(%{"configKey" => config_key, "pageSize" => 10}).rows |> List.first()

    assert config["configValue"] == "alpha"

    render_click(view, "delete-config", %{"config-id" => to_string(config["configId"])})
    assert render(view) =~ "配置已删除"

    dict_type = "live.type.#{System.unique_integer([:positive])}"

    render_click(view, "show-panel", %{"panel" => "dicts"})

    render_submit(view, "filter-dict-types", %{"dictTypeKeyword" => "no-such-dictionary-type"})
    assert live_socket(view).assigns.selected_dict_type == ""
    assert render(view) =~ "没有匹配的字典类型"
    assert render(view) =~ "选择一个字典类型"
    render_click(view, "reset-dict-type-filter")

    render_submit(view, "save-dict-type", %{
      "dictId" => "",
      "dictName" => "Live 字典",
      "dictType" => dict_type,
      "status" => "1",
      "remark" => ""
    })

    assert render(view) =~ "字典类型已创建"
    assert Dictionary.list_dict_types(%{"dictType" => dict_type, "pageSize" => 10}).total == 1

    render_click(view, "paginate", %{"panel" => "dict-data", "page" => "2"})
    render_click(view, "select-dict-type", %{"dict-type" => dict_type})
    assert live_socket(view).assigns.page_nums["dict-data"] == 1

    render_click(view, "paginate-dict-data", %{"page" => "2"})
    assert live_socket(view).assigns.page_nums["dict-data"] == 2

    render_click(view, "refresh-dicts")
    assert live_socket(view).assigns.page_nums["dict-data"] == 1

    render_submit(view, "save-dict-data", %{
      "dictCode" => "",
      "dictType" => dict_type,
      "dictLabel" => "Live 值",
      "dictValue" => "1",
      "dictSort" => "1",
      "isDefault" => "false",
      "cssClass" => "",
      "listClass" => "",
      "status" => "1",
      "remark" => ""
    })

    assert render(view) =~ "字典数据已创建"
    assert Dictionary.list_dict_data(%{"dictType" => dict_type, "pageSize" => 10}).total == 1
    assert live_socket(view).assigns.dict_data_total == 1

    render_click(view, "paginate-dict-data", %{"page" => "2"})
    assert live_socket(view).assigns.page_nums["dict-data"] == 2

    data_code =
      Dictionary.list_dict_data(%{"dictType" => dict_type, "pageSize" => 10}).rows
      |> List.first()
      |> Map.fetch!("dictCode")

    render_click(view, "delete-dict-data", %{"dict-code" => to_string(data_code)})
    assert render(view) =~ "字典数据已删除"
    assert live_socket(view).assigns.page_nums["dict-data"] == 1
    assert live_socket(view).assigns.dict_data_rows == []

    notice_title = "Live 公告 #{System.unique_integer([:positive])}"

    render_click(view, "show-panel", %{"panel" => "notices"})

    render_submit(view, "filter-notices", %{
      "noticeTitle" => "no-such-live-notice",
      "published" => "all"
    })

    assert render(view) =~ "没有匹配的公告"
    refute render(view) =~ "notices-table-wrap"
    render_click(view, "reset-notice-filter")

    render_submit(view, "save-notice", %{
      "noticeId" => "",
      "noticeTitle" => notice_title,
      "noticeType" => "2",
      "noticeContent" => "LiveView 联调公告",
      "status" => "1",
      "remark" => ""
    })

    assert render(view) =~ "公告已创建"

    notice =
      Notice.list_notices(%{"noticeTitle" => notice_title, "pageSize" => 10}).rows
      |> List.first()

    assert notice["published"] == false

    render_click(view, "publish-notice", %{
      "notice-id" => notice["noticeId"],
      "published" => "true"
    })

    assert render(view) =~ "公告已发布"

    published_notice =
      Notice.list_notices(%{"noticeTitle" => notice_title, "pageSize" => 10}).rows
      |> List.first()

    assert published_notice["published"] == true

    render_click(view, "publish-notice", %{
      "notice-id" => notice["noticeId"],
      "published" => "false"
    })

    assert render(view) =~ "公告已取消发布"

    render_click(view, "toggle-all-notice-selection", %{"selected" => "true"})
    selected_notice_ids = live_socket(view).assigns.selected_notice_ids
    assert notice["noticeId"] in selected_notice_ids
    assert length(selected_notice_ids) == length(live_socket(view).assigns.notice_rows)
    assert has_element?(view, "button[phx-click='delete-notices']")

    render_click(view, "toggle-all-notice-selection", %{"selected" => "false"})
    assert live_socket(view).assigns.selected_notice_ids == []

    render_click(view, "toggle-notice-selection", %{
      "notice-id" => notice["noticeId"],
      "selected" => "true"
    })

    remaining_notice_ids =
      live_socket(view).assigns.notice_rows
      |> Enum.map(&to_string(&1["noticeId"]))
      |> Enum.reject(&(&1 == to_string(notice["noticeId"])))

    render_click(view, "delete-notices", %{"notice-ids" => notice["noticeId"]})
    assert render(view) =~ "公告已删除"
    assert Notice.list_notices(%{"noticeTitle" => notice_title, "pageSize" => 10}).rows == []

    refreshed_notice_ids =
      live_socket(view).assigns.notice_rows
      |> Enum.map(&to_string(&1["noticeId"]))

    refute to_string(notice["noticeId"]) in refreshed_notice_ids
    assert Enum.all?(remaining_notice_ids, &(&1 in refreshed_notice_ids))

    render_click(view, "show-panel", %{"panel" => "logs"})
    assert has_element?(view, "button[phx-click='refresh-operation-logs']")
    render_click(view, "show-panel", %{"panel" => "job-logs"})
    assert has_element?(view, "#jobs-filter")
    render_click(view, "show-panel", %{"panel" => "monitor"})
    assert has_element?(view, "button[phx-click='refresh-monitor']")
  end

  defp live_socket(view), do: find_socket(:sys.get_state(view.pid))

  defp find_socket(%Phoenix.LiveView.Socket{} = socket), do: socket
  defp find_socket(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_socket/1)

  defp find_socket(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&find_socket/1)

  defp find_socket(list) when is_list(list), do: Enum.find_value(list, &find_socket/1)
  defp find_socket(_value), do: nil

  # 为当前 LiveView 会话注册测试 TOTP 因子；注册会使旧令牌失效，调用方随后重新登录。
  defp enroll_liveview_factor(view, admin) do
    token = live_socket(view).assigns.access_token
    {:ok, claims} = Auth.Token.verify(token, Auth.Token.access_type())

    {:ok, enrollment} =
      Mfa.begin_enrollment(admin.user_id, admin.username, claims["client_id"], claims["sid"])

    now = System.system_time(:second)

    {:ok, _verification} =
      Mfa.verify_enrollment(
        admin.user_id,
        enrollment.challenge_id,
        claims["client_id"],
        claims["sid"],
        Totp.code(enrollment.secret, now),
        nil
      )

    enrollment.secret
  end

  # 复现页面上的二次认证流程，并让后续敏感操作使用新的 AAL2 令牌。
  defp complete_liveview_step_up(view, secret) do
    render_click(view, "begin-liveview-step-up")
    challenge = live_socket(view).assigns.mfa_step_up_challenge
    assert is_map(challenge)

    render_submit(view, "verify-liveview-step-up", %{
      "code" => Totp.code(secret, System.system_time(:second) + Totp.step_seconds())
    })

    refute live_socket(view).assigns.mfa_step_up_required
  end
end
