defmodule KeystonePhoenixWeb.AdminLiveIntegrationTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Job
  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Dictionary
  alias KeystonePhoenix.Log
  alias KeystonePhoenix.Notice
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
  test "admin login and user management persist through LiveView", %{conn: conn, admin: admin} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ "企业运营管理平台"

    render_submit(view, "login", %{
      "username" => admin.username,
      "password" => "Strong!123"
    })

    assert has_element?(view, "nav[aria-label='管理模块']")
    assert Log.list_login_logs(%{"username" => admin.username, "pageSize" => 10}).total >= 1

    render_click(view, "show-panel", %{"panel" => "profile"})
    render_submit(view, "save-profile-avatar-upload", %{})
    assert has_element?(view, "#profile-feedback[role='alert']")
    assert render(view) =~ "请选择头像文件"

    avatar_content = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0>>

    avatar =
      file_input(view, "#profile-avatar-upload-form", :avatar, [
        %{
          last_modified: 1_700_000_000_000,
          name: "avatar.png",
          content: avatar_content,
          size: byte_size(avatar_content),
          type: "image/png"
        }
      ])

    render_upload(avatar, "avatar.png")
    render_submit(view, "save-profile-avatar-upload", %{})
    assert render(view) =~ "头像已上传"
    assert {:ok, uploaded_admin} = User.get_user(admin.user_id)
    assert String.starts_with?(uploaded_admin.avatar, "/profile/avatar/")

    render_click(view, "show-panel", %{"panel" => "users"})
    render_click(view, "new-user")
    assert has_element?(view, "form[phx-submit='save-user']")
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

    assert render(view) =~ "用户已创建"
    assert {:ok, created} = User.get_user_by_username(created_username)
    assert created.nickname == "Live 用户"

    render_click(view, "edit-user", %{"user-id" => to_string(created.user_id)})
    assert has_element?(view, "#user-reset-password-form")

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
    assert live_socket(view).assigns.selected_role_id == ""
    assert live_socket(view).assigns.allocated_role_user_rows == []
    assert live_socket(view).assigns.unallocated_role_user_rows == []

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

    dict_type = "live.type.#{System.unique_integer([:positive])}"

    render_click(view, "show-panel", %{"panel" => "dicts"})

    render_submit(view, "save-dict-type", %{
      "dictId" => "",
      "dictName" => "Live 字典",
      "dictType" => dict_type,
      "status" => "1",
      "remark" => ""
    })

    assert render(view) =~ "字典类型已创建"
    assert Dictionary.list_dict_types(%{"dictType" => dict_type, "pageSize" => 10}).total == 1

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

    notice_title = "Live 公告 #{System.unique_integer([:positive])}"

    render_click(view, "show-panel", %{"panel" => "notices"})

    render_submit(view, "save-notice", %{
      "noticeId" => "",
      "noticeTitle" => notice_title,
      "noticeType" => "2",
      "noticeContent" => "LiveView 联调公告",
      "status" => "1",
      "remark" => ""
    })

    assert render(view) =~ "公告已创建"
    assert Notice.list_notices(%{"noticeTitle" => notice_title, "pageSize" => 10}).total == 1

    render_click(view, "show-panel", %{"panel" => "logs"})
    assert has_element?(view, "button[phx-click='refresh-logs']")
    render_click(view, "show-panel", %{"panel" => "job-logs"})
    assert has_element?(view, "button[phx-click='refresh-job-logs']")
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
end
