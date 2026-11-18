defmodule KeystonePhoenixWeb.AdminSupportedDeepLinksTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Log.SysLoginInfo
  alias KeystonePhoenix.Log.SysOperationLog
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Live.LoginEvents
  alias KeystonePhoenixWeb.Live.AdminPages.OrganizationFilters
  alias KeystonePhoenixWeb.LiveAuthenticationTestSupport, as: LiveSupport

  @password "Strong!123"

  @tag :integration
  test "login audit deep link restores filters and page when the other audit table is unavailable",
       %{
         conn: conn
       } do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    admin = create_user(role, "deep_link_login_admin")
    suffix = System.unique_integer([:positive])
    username_prefix = "deep_link_login_actor_#{suffix}_"
    insert_login_logs(username_prefix)

    url =
      audit_url("/audit/login", "login_logs", %{
        "username" => username_prefix,
        "status" => "SUCCESS",
        "page" => 2
      })

    Repo.query!("ALTER TABLE sys_operation_log RENAME TO sys_operation_log_unavailable")

    try do
      {:ok, view, _html} = live(conn, url)
      login(view, admin)

      socket = LiveSupport.live_socket(view)
      assert socket.assigns.active_panel == "login-logs"

      assert socket.assigns.login_log_filter == %{
               "username" => username_prefix,
               "status" => "SUCCESS"
             }

      assert socket.assigns.page_nums["login-logs"] == 2
      assert socket.assigns.login_log_total == 21
      assert length(socket.assigns.login_log_rows) == 1
      assert List.first(socket.assigns.login_log_rows)["username"] =~ username_prefix
      assert socket.assigns.log_feedback == nil
    after
      Repo.query!("ALTER TABLE sys_operation_log_unavailable RENAME TO sys_operation_log")
    end
  end

  @tag :integration
  test "operation audit clamps an out-of-range deep link and reads without login log storage", %{
    conn: conn
  } do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    admin = create_user(role, "deep_link_operation_admin")
    suffix = System.unique_integer([:positive])
    actor = "deep_link_operation_actor_#{suffix}"
    resource = "deep_link_operation_resource_#{suffix}"
    insert_operation_logs(actor, resource)

    url =
      audit_url("/audit/operations", "operations_audit", %{
        "actor" => actor,
        "action" => "UPDATE",
        "resource" => resource,
        "page" => 99
      })

    Repo.query!("ALTER TABLE sys_login_info RENAME TO sys_login_info_unavailable")

    try do
      {:ok, view, _html} = live(conn, url)
      login(view, admin)

      socket = LiveSupport.live_socket(view)
      assert socket.assigns.active_panel == "operation-logs"

      assert socket.assigns.operation_log_filter == %{
               "actor" => actor,
               "action" => "UPDATE",
               "resource" => resource
             }

      assert socket.assigns.page_nums["operation-logs"] == 2
      assert socket.assigns.operation_log_total == 21
      assert length(socket.assigns.operation_log_rows) == 1

      assert URI.decode_query(URI.parse(socket.assigns.current_uri).query) == %{
               "operations_audit_action" => "UPDATE",
               "operations_audit_actor" => actor,
               "operations_audit_page" => "2",
               "operations_audit_resource" => resource
             }

      assert socket.assigns.log_feedback == nil
    after
      Repo.query!("ALTER TABLE sys_login_info_unavailable RENAME TO sys_login_info")
    end
  end

  @tag :integration
  test "audit read failure displays feedback and preserves the requested URL", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    admin = create_user(role, "deep_link_failure_admin")
    insert_operation_logs("failed_actor", "failed_resource")

    url =
      audit_url("/audit/operations", "operations_audit", %{"actor" => "failed_actor", "page" => 2})

    {:ok, view, _html} = live(conn, url)
    original_uri = LiveSupport.live_socket(view).assigns.current_uri
    Repo.query!("ALTER TABLE sys_operation_log RENAME TO sys_operation_log_unavailable")

    try do
      login(view, admin)

      failed_socket = LiveSupport.live_socket(view)
      assert failed_socket.assigns.active_panel == "operation-logs"
      assert failed_socket.assigns.operation_log_rows == []
      assert failed_socket.assigns.operation_log_total == 0
      assert failed_socket.assigns.log_feedback
      assert failed_socket.assigns.current_uri == original_uri
      assert failed_socket.assigns.page_nums["operation-logs"] == 2
      assert render(view) =~ "操作审计读取失败，请重试"
    after
      Repo.query!("ALTER TABLE sys_operation_log_unavailable RENAME TO sys_operation_log")
    end

    render_click(view, "refresh-operation-logs")

    recovered_socket = LiveSupport.live_socket(view)
    assert length(recovered_socket.assigns.operation_log_rows) == 1
    assert recovered_socket.assigns.operation_log_total == 21
    assert recovered_socket.assigns.log_feedback == nil
    assert recovered_socket.assigns.current_uri == original_uri
    assert recovered_socket.assigns.page_nums["operation-logs"] == 2
  end

  @tag :integration
  test "menu and department deep links restore filters and tree data", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    Repo.insert!(
      SysDept.changeset(%SysDept{}, %{
        "dept_name" => "研发部门",
        "ancestors" => "",
        "status" => 1
      })
    )

    menu_admin = create_user(role, "deep_link_menu_admin")
    {:ok, menu_view, _html} = live(conn, "/menus?menus_keyword=%E7%94%A8%E6%88%B7")
    login(menu_view, menu_admin)

    menu_socket = LiveSupport.live_socket(menu_view)
    assert menu_socket.assigns.active_panel == "menus"
    assert menu_socket.assigns.menu_filter == "用户"
    assert menu_socket.assigns.menu_rows != []
    assert OrganizationFilters.filtered_menus(menu_socket.assigns.menu_rows, "用户") != []

    original_uri = menu_socket.assigns.current_uri
    previous_socket = anonymous_previous_socket(menu_socket)
    Repo.query!("ALTER TABLE sys_menu RENAME TO sys_menu_unavailable")

    try do
      assert {:noreply, failed_socket} =
               LoginEvents.restore_route_after_login({:noreply, menu_socket}, previous_socket)

      assert failed_socket.assigns.menu_rows == []
      assert failed_socket.assigns.menu_feedback
      assert failed_socket.assigns.current_uri == original_uri
    after
      Repo.query!("ALTER TABLE sys_menu_unavailable RENAME TO sys_menu")
    end

    dept_admin = create_user(role, "deep_link_dept_admin")

    {:ok, dept_view, _html} =
      live(conn, "/departments?departments_keyword=%E7%A0%94%E5%8F%91%E9%83%A8%E9%97%A8")

    login(dept_view, dept_admin)

    dept_socket = LiveSupport.live_socket(dept_view)
    assert dept_socket.assigns.active_panel == "depts"
    assert dept_socket.assigns.dept_filter["keyword"] == "研发部门"

    assert OrganizationFilters.filtered_depts(
             dept_socket.assigns.dept_rows,
             dept_socket.assigns.dept_filter
           ) != []

    assert dept_socket.assigns.dept_feedback == nil
  end

  @tag :integration
  test "login with no audit permission returns to profile without audit rows", %{conn: conn} do
    user = create_user(nil, "deep_link_no_audit_access")
    {:ok, view, _html} = live(conn, "/audit/operations?operations_audit_actor=private_actor")
    login(view, user)

    socket = LiveSupport.live_socket(view)
    assert socket.assigns.active_panel == "profile"
    assert URI.parse(socket.assigns.current_uri).path == "/profile"
    assert socket.assigns.operation_log_rows == []
    assert socket.assigns.operation_log_total == 0
    refute has_element?(view, ".monitor-page")
  end

  @tag :integration
  test "session expiry preserves the audit deep link for the next login", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    admin = create_user(role, "deep_link_expired_session_admin")
    actor = "deep_link_expired_session_actor"
    resource = "deep_link_expired_session_resource"
    insert_operation_logs(actor, resource)

    url =
      audit_url("/audit/operations", "operations_audit", %{
        "actor" => actor,
        "action" => "UPDATE",
        "resource" => resource,
        "page" => 2
      })

    {:ok, view, _html} = live(conn, url)
    login(view, admin)

    original_uri = LiveSupport.live_socket(view).assigns.current_uri
    assert URI.parse(original_uri).path == "/audit/operations"
    assert LiveSupport.live_socket(view).assigns.active_panel == "operation-logs"
    assert LiveSupport.live_socket(view).assigns.page_nums["operation-logs"] == 2

    assert :ok = Auth.logout_access(LiveSupport.live_socket(view).assigns.access_token)

    expired_html = render_click(view, "show-panel", %{"panel" => "monitor"})
    expired_socket = LiveSupport.live_socket(view)
    assert expired_html =~ "登录状态已失效，请重新登录"
    assert expired_socket.assigns.current_user == nil
    assert expired_socket.assigns.current_uri == original_uri

    login(view, admin)

    restored_socket = LiveSupport.live_socket(view)
    assert restored_socket.assigns.active_panel == "operation-logs"
    assert restored_socket.assigns.operation_log_filter["actor"] == actor
    assert restored_socket.assigns.operation_log_filter["resource"] == resource
    assert restored_socket.assigns.page_nums["operation-logs"] == 2
    assert restored_socket.assigns.operation_log_total == 21
    assert length(restored_socket.assigns.operation_log_rows) == 1
    assert restored_socket.assigns.current_uri == original_uri
  end

  @tag :integration
  test "login status filters survive refresh and retain page size and URL", %{conn: conn} do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    admin = create_user(role, "deep_link_status_refresh_admin")
    prefix = "deep_link_status_refresh_#{System.unique_integer([:positive])}_"
    insert_login_logs(prefix, 1, 45)
    insert_login_logs(prefix, 0, 3)
    insert_login_logs(prefix, 2, 2)
    insert_login_logs(prefix, 3, 1)

    {:ok, view, _html} = live(conn, "/audit/login")
    login(view, admin)

    html =
      render_submit(view, "filter-login-logs", %{
        "loginUsername" => prefix,
        "loginStatus" => "SUCCESS"
      })

    success_socket = LiveSupport.live_socket(view)
    assert html =~ "共 45 条记录"
    assert success_socket.assigns.login_log_filter["status"] == "SUCCESS"
    assert success_socket.assigns.login_log_total == 45
    assert Enum.all?(success_socket.assigns.login_log_rows, &(&1["status"] == 1))

    first_page_uri = success_socket.assigns.current_uri
    render_click(view, "refresh-login-logs")

    refreshed_first_page = LiveSupport.live_socket(view)
    assert refreshed_first_page.assigns.login_log_total == 45
    assert Enum.all?(refreshed_first_page.assigns.login_log_rows, &(&1["status"] == 1))
    assert refreshed_first_page.assigns.current_uri == first_page_uri
    assert refreshed_first_page.assigns.page_sizes["login-logs"] == 20

    render_click(view, "paginate-login-logs", %{"page" => "2"})
    second_page_uri = LiveSupport.live_socket(view).assigns.current_uri
    render_click(view, "refresh-login-logs")

    refreshed_second_page = LiveSupport.live_socket(view)
    assert refreshed_second_page.assigns.login_log_total == 45
    assert length(refreshed_second_page.assigns.login_log_rows) == 20
    assert Enum.all?(refreshed_second_page.assigns.login_log_rows, &(&1["status"] == 1))
    assert refreshed_second_page.assigns.page_nums["login-logs"] == 2
    assert refreshed_second_page.assigns.current_uri == second_page_uri

    assert URI.decode_query(URI.parse(second_page_uri).query) == %{
             "login_logs_page" => "2",
             "login_logs_status" => "SUCCESS",
             "login_logs_username" => prefix
           }

    for {label, status, expected_total} <- [
          {"FAILURE", 0, 3},
          {"LOGOUT", 2, 2},
          {"REGISTER", 3, 1}
        ] do
      render_submit(view, "filter-login-logs", %{
        "loginUsername" => prefix,
        "loginStatus" => label
      })

      before_refresh = LiveSupport.live_socket(view)
      assert before_refresh.assigns.login_log_total == expected_total
      assert Enum.all?(before_refresh.assigns.login_log_rows, &(&1["status"] == status))

      render_click(view, "refresh-login-logs")

      after_refresh = LiveSupport.live_socket(view)
      assert after_refresh.assigns.login_log_total == expected_total
      assert Enum.all?(after_refresh.assigns.login_log_rows, &(&1["status"] == status))
      assert after_refresh.assigns.login_log_filter["status"] == label
    end
  end

  defp insert_login_logs(username_prefix) do
    insert_login_logs(username_prefix, 1, 21)
  end

  # 写入不同登录状态的分页数据，验证筛选和刷新使用真实数据库查询。
  defp insert_login_logs(username_prefix, status, count) do
    base_time = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    rows =
      Enum.map(1..count, fn index ->
        %{
          info_id: Identity.v7(),
          username: "#{username_prefix}#{status}_#{index}",
          status: status,
          login_time: DateTime.add(base_time, index, :second),
          deleted: false
        }
      end)

    Repo.insert_all(SysLoginInfo, rows)
  end

  defp insert_operation_logs(actor, resource) do
    base_time = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    rows =
      Enum.map(1..21, fn index ->
        %{
          operation_id: Identity.v7(),
          business_type: 2,
          request_method: 2,
          request_module: resource,
          request_url: "/#{resource}",
          called_method: "UPDATE",
          operator_type: 1,
          username: actor,
          operator_ip: "127.0.0.1",
          operation_param: "{}",
          operation_result: "ok",
          status: 1,
          error_stack: "",
          operation_time: DateTime.add(base_time, index, :second),
          deleted: false
        }
      end)

    Repo.insert_all(SysOperationLog, rows)
  end

  # 用匿名态快照触发同一深链接恢复入口，不重复模拟页面查询逻辑。
  defp anonymous_previous_socket(socket),
    do: %{socket | assigns: Map.put(socket.assigns, :current_user, nil)}

  defp audit_url(path, namespace, filter) do
    query =
      Map.new(filter, fn {key, value} -> {"#{namespace}_#{key}", value} end)
      |> URI.encode_query()

    "#{path}?#{query}"
  end

  defp create_user(role, suffix) do
    %SysUser{}
    |> SysUser.create_changeset(%{
      "username" => suffix,
      "nickname" => "深链接管理员",
      "password" => @password,
      "role_id" => role && role.role_id,
      "status" => 1
    })
    |> Repo.insert!()
  end

  defp login(view, user) do
    render_submit(view, "login", %{"username" => user.username, "password" => @password})
    refute has_element?(view, "#login-form")
  end
end
