defmodule KeystonePhoenixWeb.UserImportLiveTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Mfa.Totp
  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.SysUser

  @password "Strong!123"

  # 创建具有完整用户管理权限的测试账号，供真实登录和导入流程使用。
  setup do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    username = "import_live_admin_#{System.unique_integer([:positive])}"

    admin =
      %SysUser{}
      |> SysUser.create_changeset(%{
        "username" => username,
        "nickname" => "导入验收管理员",
        "password" => @password,
        "role_id" => role.role_id,
        "status" => 1
      })
      |> Repo.insert!()

    {:ok, admin: admin}
  end

  @tag :integration
  # 验证导入只跳过失败行，并在页面展示完整明细且转义不可信用户名。
  test "partial import shows row, username, readable reason, and escaped values", %{
    conn: conn,
    admin: admin
  } do
    {:ok, view, _html} = live(conn, "/")
    render_submit(view, "login", %{"username" => admin.username, "password" => @password})

    secret = enroll_liveview_factor(view, admin)
    render_click(view, "logout")
    render_submit(view, "login", %{"username" => admin.username, "password" => @password})
    complete_liveview_step_up(view, secret)

    duplicate_username = admin.username
    unsafe_username = "<script>alert(1)</script>"
    imported_username = "import_success_#{System.unique_integer([:positive])}"
    invalid_nickname_username = "import_nickname_#{System.unique_integer([:positive])}"

    {:ok, workbook} =
      Excel.export(
        ["部门ID", "用户名", "密码", "状态", "角色ID", "昵称"],
        [
          [admin.dept_id, duplicate_username, @password, 1, nil, "重复用户"],
          [admin.dept_id, unsafe_username, @password, 1, nil, "格式错误用户"],
          [admin.dept_id, imported_username, @password, 1, nil, "导入成功"],
          [admin.dept_id, invalid_nickname_username, @password, 1, nil, String.duplicate("x", 33)]
        ],
        "users.xlsx"
      )

    render_click(view, "show-panel", %{"panel" => "users"})
    render_click(view, "new-user-import")

    upload =
      file_input(view, "#user-import-form", :user_import, [
        %{
          last_modified: 1_700_000_000_000,
          name: "users.xlsx",
          content: workbook,
          size: byte_size(workbook),
          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        }
      ])

    render_upload(upload, "users.xlsx")
    render_submit(view, "import-users", %{})

    assert live_socket(view).assigns.user_import_result == %{
             "total" => 4,
             "success" => 1,
             "failed" => [
               %{
                 "row" => 2,
                 "username" => duplicate_username,
                 "reason" => "username already exists",
                 "code" => "username_already_exists"
               },
               %{
                 "row" => 3,
                 "username" => unsafe_username,
                 "reason" => "用户名：用户名只允许字母、数字和下划线，且首字符不能为数字",
                 "code" => "username_invalid_format"
               },
               %{
                 "row" => 5,
                 "username" => invalid_nickname_username,
                 "reason" => "昵称：should be at most 32 character(s)",
                 "code" => "validation_failed"
               }
             ]
           }

    html = render(view)
    assert html =~ "失败行"
    assert html =~ "username already exists"
    assert html =~ "用户名只允许字母、数字和下划线"
    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute html =~ unsafe_username
    assert {:ok, imported} = User.get_user_by_username(imported_username)
    assert imported.username == imported_username
  end

  # 注册 TOTP 后重新登录；因注册会递增权限版本，旧令牌不能继续使用。
  defp enroll_liveview_factor(view, admin) do
    token = live_socket(view).assigns.access_token
    {:ok, claims} = Auth.Token.verify(token, Auth.Token.access_type())

    {:ok, enrollment} =
      Mfa.begin_enrollment(admin.user_id, admin.username, claims["client_id"], claims["sid"])

    {:ok, _verification} =
      Mfa.verify_enrollment(
        admin.user_id,
        enrollment.challenge_id,
        claims["client_id"],
        claims["sid"],
        Totp.code(enrollment.secret, System.system_time(:second)),
        nil
      )

    enrollment.secret
  end

  # 通过页面事件完成 AAL2 验证，确保导入经过真实敏感操作流程。
  defp complete_liveview_step_up(view, secret) do
    render_click(view, "begin-liveview-step-up")

    render_submit(view, "verify-liveview-step-up", %{
      "code" => Totp.code(secret, System.system_time(:second) + Totp.step_seconds())
    })

    refute live_socket(view).assigns.mfa_step_up_required
  end

  # 读取 LiveView 进程中的 socket 状态，用于核对导入结果和认证状态。
  defp live_socket(view), do: find_socket(:sys.get_state(view.pid))

  defp find_socket(%Phoenix.LiveView.Socket{} = socket), do: socket
  defp find_socket(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_socket/1)

  defp find_socket(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&find_socket/1)

  defp find_socket(list) when is_list(list), do: Enum.find_value(list, &find_socket/1)
  defp find_socket(_value), do: nil
end
