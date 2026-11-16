defmodule KeystonePhoenixWeb.AdminJobDeepLinkTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import KeystonePhoenixWeb.LiveAuthenticationTestSupport, only: [live_socket: 1]

  alias KeystonePhoenix.Job
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
end
