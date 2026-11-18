defmodule KeystonePhoenixWeb.AdminJobDeepLinkTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import KeystonePhoenixWeb.LiveAuthenticationTestSupport, only: [live_socket: 1]

  alias KeystonePhoenixWeb.LiveAuthenticationTestSupport, as: LiveSupport

  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Job.SysJob
  alias KeystonePhoenix.Job.SysJobLog
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  setup do
    username = "job_url_admin_#{System.unique_integer([:positive])}"
    admin_role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    {:ok, user} =
      %SysUser{}
      |> SysUser.create_changeset(%{
        "username" => username,
        "nickname" => "任务 URL 管理员",
        "password" => "Strong!123",
        "role_id" => admin_role.role_id,
        "status" => 1
      })
      |> Repo.insert()

    {:ok, admin: user}
  end

  @tag :integration
  test "任务筛选、分页和选中任务写入命名深链接", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(conn, "/")

    render_submit(view, "login", %{
      "username" => admin.username,
      "password" => "Strong!123"
    })

    render_click(view, "show-panel", %{"panel" => "jobs"})
    job_name = "URL 任务 #{System.unique_integer([:positive])}"

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

    render_submit(view, "filter-jobs", %{"jobKeyword" => job_name})

    assert URI.decode_query(URI.parse(live_socket(view).assigns.current_uri).query || "") == %{
             "jobs_keyword" => job_name
           }

    render_click(view, "paginate", %{"panel" => "jobs", "page" => "2"})
    assert URI.parse(live_socket(view).assigns.current_uri).query =~ "jobs_jobPage=2"
    render_click(view, "paginate", %{"panel" => "jobs", "page" => "1"})

    job = Job.list_jobs(%{"jobName" => job_name, "pageSize" => 10}).rows |> List.first()
    render_click(view, "select-job", %{"job-id" => to_string(job["jobId"])})
    assert URI.parse(live_socket(view).assigns.current_uri).query =~ "jobs_selectedJobId="

    render_click(view, "reset-job-filter")
    assert URI.parse(live_socket(view).assigns.current_uri).path == "/jobs"
    refute (URI.parse(live_socket(view).assigns.current_uri).query || "") =~ "jobs_selectedJobId"
  end

  @tag :integration
  test "任务成功翻页后清除批量选择", %{conn: conn, admin: admin} do
    suffix = System.unique_integer([:positive])
    keyword = "分页选择任务 #{suffix}"

    for index <- 1..21 do
      insert_job(KeystonePhoenix.Identity.v7(), "#{keyword} #{index}")
    end

    {:ok, view, _html} = live(conn, "/")
    login(view, admin)
    render_click(view, "show-panel", %{"panel" => "jobs"})
    render_submit(view, "filter-jobs", %{"jobKeyword" => keyword})
    render_click(view, "toggle-all-job-selection", %{"selected" => "true"})

    selected_ids = live_socket(view).assigns.selected_job_ids
    assert length(selected_ids) == 20

    render_click(view, "paginate", %{"panel" => "jobs", "page" => "2"})

    assert live_socket(view).assigns.page_nums["jobs"] == 2
    assert live_socket(view).assigns.selected_job_ids == []
  end

  @tag :integration
  test "任务翻页读取失败时保留当前页、行和批量选择", %{conn: conn, admin: admin} do
    suffix = System.unique_integer([:positive])
    keyword = "分页失败任务 #{suffix}"

    for index <- 1..21 do
      insert_job(KeystonePhoenix.Identity.v7(), "#{keyword} #{index}")
    end

    {:ok, view, _html} = live(conn, "/")
    login(view, admin)
    render_click(view, "show-panel", %{"panel" => "jobs"})
    render_submit(view, "filter-jobs", %{"jobKeyword" => keyword})
    render_click(view, "toggle-all-job-selection", %{"selected" => "true"})

    old_rows = live_socket(view).assigns.job_rows
    old_selected_ids = live_socket(view).assigns.selected_job_ids
    old_uri = live_socket(view).assigns.current_uri
    assert length(old_rows) == 20
    assert length(old_selected_ids) == 20

    # 临时隐藏查询表，触发真实 PostgreSQL 读取失败，再在测试事务内恢复。
    Repo.query!("ALTER TABLE sys_job RENAME TO sys_job_unavailable")

    try do
      html = render_click(view, "paginate", %{"panel" => "jobs", "page" => "2"})

      assert html =~ "任务列表读取失败，请重试"
      assert live_socket(view).assigns.page_nums["jobs"] == 1
      assert live_socket(view).assigns.job_rows == old_rows
      assert live_socket(view).assigns.selected_job_ids == old_selected_ids
      assert live_socket(view).assigns.current_uri == old_uri
    after
      Repo.query!("ALTER TABLE sys_job_unavailable RENAME TO sys_job")
    end
  end

  @tag :integration
  test "首次深链接读取失败时显示重试入口，任务出现后可以重新读取", %{
    conn: conn,
    admin: admin
  } do
    {:ok, view, _html} = live(conn, "/")
    login(view, admin)
    job_id = KeystonePhoenix.Identity.v7()

    html = render_patch(view, "/jobs?jobs_selectedJobId=#{job_id}")

    assert html =~ "无法读取所选任务或执行日志，请重试"
    assert html =~ "重试读取任务详情"
    assert live_socket(view).assigns.selected_job_id == job_id
    assert is_nil(live_socket(view).assigns.selected_job)
    refute has_element?(view, "#selected-job-logs-title")

    job = insert_job(job_id, "深链接重试任务")
    html = render_click(view, "select-job", %{"job-id" => job_id})

    assert html =~ "#{job.job_name} · 执行日志"
    refute html =~ "无法读取所选任务或执行日志，请重试"
  end

  @tag :integration
  test "任务日志深链接恢复页码并将过期页码校正到末页", %{conn: conn, admin: admin} do
    job = insert_job(KeystonePhoenix.Identity.v7(), "日志分页深链接任务")
    for index <- 1..21, do: insert_job_log(job, "深链接分页日志 #{index}")

    {:ok, view, _html} = live(conn, "/")
    login(view, admin)

    html =
      render_patch(
        view,
        "/jobs?jobs_selectedJobId=#{job.job_id}&jobs_logPage=2"
      )

    assert html =~ "第 2 / 2 页"

    assert Enum.map(live_socket(view).assigns.job_log_rows, & &1["jobMessage"]) == [
             "深链接分页日志 1"
           ]

    html =
      render_patch(
        view,
        "/jobs?jobs_selectedJobId=#{job.job_id}&jobs_logPage=99"
      )

    assert html =~ "第 2 / 2 页"
    assert live_socket(view).assigns.page_nums["job-logs"] == 2
    assert URI.parse(live_socket(view).assigns.current_uri).query =~ "jobs_logPage=2"
  end

  @tag :integration
  test "从任务日志深链接登录后恢复选中任务和日志页码", %{conn: conn, admin: admin} do
    keyword = "login-route-target"

    jobs =
      for index <- 1..21, do: insert_job(KeystonePhoenix.Identity.v7(), "#{keyword} #{index}")

    insert_job(KeystonePhoenix.Identity.v7(), "login-route-unmatched")
    page_two = Job.list_jobs(%{"keyword" => keyword, "pageNum" => 2, "pageSize" => 20})
    assert page_two.total == 21
    assert length(page_two.rows) == 1

    job = Enum.find(jobs, &(to_string(&1.job_id) == to_string(hd(page_two.rows)["jobId"])))

    for index <- 1..21, do: insert_job_log(job, "登录深链接日志 #{index}")

    path =
      "/jobs?jobs_keyword=#{keyword}&jobs_jobPage=2&jobs_selectedJobId=#{job.job_id}&jobs_logPage=2"

    {:ok, view, html} = live(conn, path)
    assert html =~ "进入管理台"

    html = login(view, admin)

    assert html =~ "#{job.job_name} · 执行日志"
    assert html =~ "第 2 / 2 页"
    assert live_socket(view).assigns.active_panel == "jobs"
    assert live_socket(view).assigns.selected_job_id == job.job_id
    assert live_socket(view).assigns.job_log_loaded_page == 2
    assert live_socket(view).assigns.job_filter["keyword"] == keyword
    assert live_socket(view).assigns.job_total == 21
    assert live_socket(view).assigns.page_nums["jobs"] == 2
    assert Enum.map(live_socket(view).assigns.job_rows, & &1["jobName"]) == [job.job_name]

    assert Enum.map(live_socket(view).assigns.job_log_rows, & &1["jobMessage"]) == [
             "登录深链接日志 1"
           ]
  end

  @tag :integration
  test "没有 job:read 权限时从任务深链接登录不会打开任务详情", %{conn: conn} do
    {user, _role} = LiveSupport.create_scoped_user()
    job = insert_job(KeystonePhoenix.Identity.v7(), "受限任务不得显示")
    insert_job_log(job, "受限日志不得显示")
    path = "/jobs?jobs_selectedJobId=#{job.job_id}&jobs_logPage=2"

    {:ok, view, _html} = live(conn, path)
    html = login(view, user)

    assert html =~ "运行监控"
    assert live_socket(view).assigns.active_panel == "monitor"
    assert live_socket(view).assigns.panel_access["jobs"] == false
    assert is_nil(live_socket(view).assigns.selected_job_id)
    assert is_nil(live_socket(view).assigns.selected_job)
    assert live_socket(view).assigns.job_log_rows == []
    refute html =~ job.job_name
    refute html =~ "受限日志不得显示"
    assert URI.parse(live_socket(view).assigns.current_uri).path == "/monitor"
  end

  @tag :integration
  test "切换任务读取失败会清除旧详情，创建目标后重试显示新任务", %{
    conn: conn,
    admin: admin
  } do
    job_a = insert_job(KeystonePhoenix.Identity.v7(), "任务 A")
    insert_job_log(job_a, "任务 A 的验收日志")
    job_b_id = KeystonePhoenix.Identity.v7()
    {:ok, view, _html} = live(conn, "/")
    login(view, admin)
    render_click(view, "show-panel", %{"panel" => "jobs"})
    render_click(view, "select-job", %{"job-id" => to_string(job_a.job_id)})

    assert has_element?(view, "#selected-job-logs-title", "任务 A · 执行日志")
    assert render(view) =~ "任务 A 的验收日志"

    html = render_click(view, "select-job", %{"job-id" => job_b_id})

    assert html =~ "无法读取所选任务或执行日志，请重试"
    assert has_element?(view, "#job-log-feedback")
    assert has_element?(view, "button[phx-click='select-job'][phx-value-job-id='#{job_b_id}']")
    assert is_nil(live_socket(view).assigns.selected_job)
    assert live_socket(view).assigns.job_log_rows == []
    refute has_element?(view, "#selected-job-logs-title", "任务 A · 执行日志")
    refute render(view) =~ "任务 A 的验收日志"
    assert URI.parse(live_socket(view).assigns.current_uri).query =~ job_b_id

    job_b = insert_job(job_b_id, "任务 B")
    html = render_click(view, "select-job", %{"job-id" => job_b_id})

    assert html =~ "#{job_b.job_name} · 执行日志"
    refute html =~ "无法读取所选任务或执行日志，请重试"
    assert live_socket(view).assigns.selected_job["jobName"] == job_b.job_name
  end

  @tag :integration
  test "同一任务刷新失败时保留旧日志并明确标记", %{conn: conn, admin: admin} do
    job = insert_job(KeystonePhoenix.Identity.v7(), "刷新失败任务")
    insert_job_log(job, "保留的旧日志")
    {:ok, view, _html} = live(conn, "/")
    login(view, admin)
    render_click(view, "show-panel", %{"panel" => "jobs"})
    render_click(view, "select-job", %{"job-id" => to_string(job.job_id)})

    assert render(view) =~ "保留的旧日志"
    Repo.query!("ALTER TABLE sys_job_log RENAME TO sys_job_log_unavailable")

    try do
      html = render_click(view, "refresh-job-logs")

      assert html =~ "任务日志刷新失败，当前仍显示上一次成功读取的数据。请重试。"
      assert html =~ "保留的旧日志"
      assert has_element?(view, "#job-log-feedback")
      assert has_element?(view, "#selected-job-logs-title", "刷新失败任务 · 执行日志")
    after
      Repo.query!("ALTER TABLE sys_job_log_unavailable RENAME TO sys_job_log")
    end
  end

  defp login(view, admin) do
    render_submit(view, "login", %{
      "username" => admin.username,
      "password" => "Strong!123"
    })
  end

  defp insert_job(job_id, name) do
    %SysJob{job_id: job_id}
    |> SysJob.changeset(%{
      job_name: name,
      job_group: "DEFAULT",
      invoke_target: "demoJobTask.printHeartbeat()",
      cron_expression: "0 * * * * *",
      concurrent: 0,
      status: 1
    })
    |> Repo.insert!()
  end

  defp insert_job_log(job, message) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %SysJobLog{}
    |> SysJobLog.changeset(%{
      job_id: job.job_id,
      job_name: job.job_name,
      job_group: job.job_group,
      invoke_target: job.invoke_target,
      cron_expression: job.cron_expression,
      trigger_type: 2,
      status: 1,
      job_message: message,
      start_time: now,
      end_time: now,
      duration_ms: 1
    })
    |> Repo.insert!()
  end
end
