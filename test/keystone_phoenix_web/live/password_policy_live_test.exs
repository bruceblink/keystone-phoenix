defmodule KeystonePhoenixWeb.PasswordPolicyLiveTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import KeystonePhoenixWeb.LiveAuthenticationTestSupport,
    only: [create_user: 1, disable_captcha: 0, ensure_captcha_config: 0]

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Mfa.Totp
  alias KeystonePhoenix.Authz.PolicyCache
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.SysUser

  setup do
    ensure_captcha_config()
    disable_captcha()
    PolicyCache.invalidate()
    on_exit(&PolicyCache.invalidate/0)

    admin_role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)
    suffix = System.unique_integer([:positive])

    {:ok, admin} =
      create_user(%{
        "username" => "password_policy_live_admin_#{suffix}"
      })

    {:ok, target} =
      create_user(%{
        "username" => "password_policy_live_target_#{suffix}"
      })

    admin = Repo.update!(Ecto.Changeset.change(admin, role_id: admin_role.role_id))

    {:ok, admin: admin, target: target}
  end

  @tag :integration
  test "LiveView create and reset use the same password policy", %{
    conn: conn,
    admin: admin,
    target: target
  } do
    {:ok, view, _html} = live(conn, "/")

    login_params = %{
      "username" => admin.username,
      "password" => "Strong!123"
    }

    render_submit(view, "login", login_params)
    secret = enroll_liveview_factor(view, admin)
    render_click(view, "logout")
    render_submit(view, "login", login_params)
    complete_liveview_step_up(view, secret)

    render_click(view, "show-panel", %{"panel" => "users"})
    render_click(view, "new-user")

    rejected_username = "password_policy_rejected_#{System.unique_integer([:positive])}"

    render_submit(view, "save-user", %{
      "userId" => "",
      "username" => rejected_username,
      "nickname" => "策略拒绝",
      "password" => "test-only-disallowed",
      "email" => "",
      "phoneNumber" => "",
      "sex" => "2",
      "deptId" => "",
      "postId" => "",
      "roleId" => "",
      "status" => "1",
      "remark" => ""
    })

    assert render(view) =~ "密码不符合安全策略"
    assert {:error, :not_found} = User.get_user_by_username(rejected_username)

    original_hash = Repo.get!(SysUser, target.user_id).password
    render_click(view, "edit-user", %{"user-id" => to_string(target.user_id)})

    render_submit(view, "reset-user-password", %{
      "userId" => to_string(target.user_id),
      "password" => "test-only-disallowed"
    })

    assert render(view) =~ "密码不符合安全策略"
    assert Repo.get!(SysUser, target.user_id).password == original_hash
  end

  # 当前 LiveView 对用户管理写操作要求 AAL2；先完成会话 MFA，再核验密码策略结果。
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

  defp complete_liveview_step_up(view, secret) do
    render_click(view, "begin-liveview-step-up")

    render_submit(view, "verify-liveview-step-up", %{
      "code" => Totp.code(secret, System.system_time(:second) + Totp.step_seconds())
    })

    refute live_socket(view).assigns.mfa_step_up_required
  end

  defp live_socket(view), do: find_socket(:sys.get_state(view.pid))

  defp find_socket(%Phoenix.LiveView.Socket{} = socket), do: socket
  defp find_socket(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_socket/1)

  defp find_socket(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&find_socket/1)

  defp find_socket(list) when is_list(list), do: Enum.find_value(list, &find_socket/1)
  defp find_socket(_value), do: nil
end
