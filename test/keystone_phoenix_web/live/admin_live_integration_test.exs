defmodule KeystonePhoenixWeb.AdminLiveIntegrationTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.SysUser

  setup do
    username = "live_admin_#{System.unique_integer([:positive])}"

    {:ok, user} =
      %SysUser{}
      |> SysUser.create_changeset(%{
        "username" => username,
        "nickname" => "Live 管理员",
        "password" => "Strong!123",
        "status" => 1
      })
      |> Repo.insert()

    {:ok, user} = Repo.update(Ecto.Changeset.change(user, is_admin: true))

    {:ok, admin: user}
  end

  @tag :integration
  test "admin login and user management persist through LiveView", %{conn: conn, admin: admin} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ "管理后台正在迁移到 LiveView"

    render_submit(view, "login", %{
      "username" => admin.username,
      "password" => "Strong!123"
    })

    assert has_element?(view, "nav[aria-label='管理模块']")

    render_click(view, "show-panel", %{"panel" => "profile"})
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
    assert has_element?(view, "form[phx-submit='save-user']")

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
      "dataScope" => "1",
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

    render_click(view, "unassign-role-user", %{"user-id" => to_string(created.user_id)})
    assert {:ok, unassigned} = User.get_user(created.user_id)
    assert is_nil(unassigned.role_id)
  end
end
