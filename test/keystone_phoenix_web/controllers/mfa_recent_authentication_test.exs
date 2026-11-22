defmodule KeystonePhoenixWeb.MfaRecentAuthenticationTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.AuthSession
  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Mfa.Factor
  alias KeystonePhoenix.Auth.Mfa.RecentAuthentication
  alias KeystonePhoenix.Auth.Mfa.Totp
  alias KeystonePhoenix.Auth.SessionAccess
  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.User.SysUserRole

  @password "Strong!123"

  @tag :integration
  test "REST honors disabled policy and requires a recent OTP or recovery login", _context do
    user = create_user(["api-key:create", "api-key:read", "mfa:manage"])
    {:ok, initial} = Auth.login_plaintext(user.username, @password, true)

    assert {:ok, initial_claims} = Token.verify(initial.token, Token.access_type())
    assert initial_claims["aal"] == "AAL1"

    assert post(authorized(initial.token), "/api/v1/api-keys", %{
             "name" => "policy-disabled",
             "scopes" => ["api-key:read"]
           }).status == 201

    {_secret, recovery_codes} = enroll_factor(user, initial_claims)
    Auth.logout(initial.refresh_token)
    assert {:ok, :ok} = Mfa.set_required(user.user_id, true)

    assert {:mfa_required, %{challenge: login_challenge}} =
             Auth.login_plaintext(user.username, @password, true)

    client_id = login_challenge.client_id

    assert {:ok, %{tokens: tokens, verification: %{amr: "recovery"}}} =
             Auth.complete_mfa_login(
               user.username,
               login_challenge.id,
               client_id,
               hd(recovery_codes),
               true,
               nil
             )

    assert {:ok, claims} = Token.verify(tokens.token, Token.access_type())
    assert claims["amr"] == ["recovery"]
    assert RecentAuthentication.check(claims, true, false) == :allowed

    assert post(authorized(tokens.token), "/api/v1/api-keys", %{
             "name" => "recent-recovery",
             "scopes" => ["api-key:read"]
           }).status == 201

    session = Repo.get!(AuthSession, claims["sid"])

    Repo.update!(
      Ecto.Changeset.change(session,
        mfa_verified_at: DateTime.add(DateTime.utc_now(), -601, :second)
      )
    )

    expired =
      post(authorized(tokens.token), "/api/v1/api-keys", %{
        "name" => "expired-recovery",
        "scopes" => ["api-key:read"]
      })

    assert expired.status == 403
    assert get_in(json_response(expired, 403), ["error", "code"]) == "mfa_step_up_required"

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(AuthSession, claims["sid"]),
        mfa_verified_at: DateTime.utc_now()
      )
    )

    assert {:ok, refreshed} = Auth.refresh(tokens.refresh_token)
    assert {:ok, refreshed_claims} = Token.verify(refreshed.token, Token.access_type())
    assert refreshed_claims["aal"] == "AAL1"
    assert RecentAuthentication.check(refreshed_claims, true, false) == :required

    after_refresh =
      post(authorized(refreshed.token), "/api/v1/api-keys", %{
        "name" => "refreshed-aal1",
        "scopes" => ["api-key:read"]
      })

    assert after_refresh.status == 403
  end

  @tag :integration
  test "step-up is bound to current user, session, client and token; Passkey does not satisfy it" do
    user = create_user(["api-key:create", "api-key:read"])
    access_token = enroll_and_step_up(user)
    assert {:ok, claims} = Token.verify(access_token, Token.access_type())
    assert claims["amr"] == ["otp"]
    assert RecentAuthentication.check(claims, true, false) == :allowed

    assert RecentAuthentication.check(Map.put(claims, "amr", ["webauthn"]), true, false) ==
             :required

    assert RecentAuthentication.check(
             Map.put(claims, "client_id", "different-client"),
             true,
             false
           ) ==
             :required

    factor = Repo.get_by!(Factor, user_id: user.user_id)
    Repo.update!(Ecto.Changeset.change(factor, enabled: false))
    assert RecentAuthentication.check(claims, true, false) == :required
    Repo.update!(Ecto.Changeset.change(Repo.get!(Factor, factor.id), enabled: true))

    assert {:ok, false} =
             SessionAccess.recent_mfa_authentication?(
               Identity.v7(),
               claims["sid"],
               claims["client_id"],
               claims["jti"]
             )

    assert {:ok, false} =
             SessionAccess.recent_mfa_authentication?(
               user.user_id,
               Identity.v7(),
               claims["client_id"],
               claims["jti"]
             )

    assert {:ok, false} =
             SessionAccess.recent_mfa_authentication?(
               user.user_id,
               claims["sid"],
               claims["client_id"],
               Identity.v7()
             )

    {:ok, replacement} = Auth.login_plaintext(user.username, @password, true)
    assert RecentAuthentication.check(claims, true, false) == :required
    assert {:ok, replacement_claims} = Token.verify(replacement.token, Token.access_type())

    Auth.logout_access(replacement.token)
    assert {:ok, :ok} = Mfa.set_required(user.user_id, true)
    assert {:ok, passkey_tokens} = Auth.login_passkey_user(user.user_id, "passkey")
    assert {:ok, passkey_claims} = Token.verify(passkey_tokens.token, Token.access_type())
    assert passkey_claims["aal"] == "AAL2"
    assert passkey_claims["amr"] == ["webauthn"]
    assert RecentAuthentication.check(passkey_claims, true, false) == :required

    denied =
      post(authorized(passkey_tokens.token), "/api/v1/api-keys", %{
        "name" => "passkey-only",
        "scopes" => ["api-key:read"]
      })

    assert denied.status == 403
    assert get_in(json_response(denied, 403), ["error", "code"]) == "mfa_step_up_required"

    Repo.update!(Ecto.Changeset.change(factor, enabled: false))
    assert RecentAuthentication.check(passkey_claims, true, false) == :required
    refute replacement_claims["sid"] == claims["sid"]
  end

  @tag :integration
  test "step-up token replacement and verification timestamp roll back together" do
    user = create_user([])
    access_token = enroll_and_step_up(user)
    assert {:ok, claims} = Token.verify(access_token, Token.access_type())
    before = Repo.get!(AuthSession, claims["sid"])

    competing_user = create_user([])
    {:ok, competing_tokens} = Auth.login_plaintext(competing_user.username, @password, true)
    assert {:ok, competing_claims} = Token.verify(competing_tokens.token, Token.access_type())

    assert {:error, :unavailable} =
             SessionAccess.replace_access_token(
               user.user_id,
               claims["sid"],
               claims["jti"],
               competing_claims["jti"],
               %{
                 assurance: "AAL2",
                 amr: "recovery",
                 verified_at: DateTime.add(DateTime.utc_now(), 1, :second)
               },
               claims["client_id"]
             )

    after_failure = Repo.get!(AuthSession, claims["sid"])
    assert after_failure.access_token_id == before.access_token_id
    assert after_failure.mfa_verified_at == before.mfa_verified_at
    assert after_failure.mfa_amr == before.mfa_amr
  end

  @tag :integration
  test "step-up token replacement rejects sessions expired during the locked check" do
    user = create_user([])
    access_token = enroll_and_step_up(user)
    assert {:ok, claims} = Token.verify(access_token, Token.access_type())
    session = Repo.get!(AuthSession, claims["sid"])
    now = DateTime.utc_now()

    for expired_attrs <- [
          [refresh_expires_at: DateTime.add(now, -1, :second)],
          [idle_expires_at: DateTime.add(now, -1, :second)]
        ] do
      Repo.update!(Ecto.Changeset.change(session, expired_attrs))

      assert {:error, :invalid_token} =
               SessionAccess.replace_access_token(
                 user.user_id,
                 session.id,
                 claims["jti"],
                 Identity.v7()
               )

      assert Repo.get!(AuthSession, session.id).access_token_id == claims["jti"]

      Repo.update!(
        Ecto.Changeset.change(session,
          refresh_expires_at: DateTime.add(now, 600, :second),
          idle_expires_at: DateTime.add(now, 600, :second)
        )
      )
    end
  end

  @tag :integration
  test "MFA administration and Passkey registration follow account policy when disabled",
       _context do
    original_passkey = Application.get_env(:keystone_phoenix, :passkey)

    Application.put_env(:keystone_phoenix, :passkey,
      enabled: true,
      rp_id: "localhost",
      origin: "http://localhost",
      rp_name: "Keystone Test",
      user_verification: "required",
      challenge_ttl_seconds: 120
    )

    on_exit(fn -> Application.put_env(:keystone_phoenix, :passkey, original_passkey) end)

    user = create_user(["mfa:manage"])
    {:ok, tokens} = Auth.login_plaintext(user.username, @password, true)

    enrollment =
      tokens.token
      |> authorized()
      |> post("/api/v1/auth/mfa/enroll", %{})
      |> json_response(201)

    code = Totp.code(enrollment["data"]["secret"], System.system_time(:second))

    verification =
      tokens.token
      |> authorized()
      |> post("/api/v1/auth/mfa/enroll/verify", %{
        "challengeId" => enrollment["data"]["challengeId"],
        "code" => code
      })

    assert verification.status == 200

    {:ok, fresh} = Auth.login_plaintext(user.username, @password, true)

    assert fresh.token
           |> authorized()
           |> post("/api/v1/auth/mfa/recovery-codes/rotate", %{
             "currentPassword" => @password
           })
           |> json_response(200)
           |> get_in(["data", "recoveryCodes"])
           |> is_list()

    passkey_user = create_user([])
    {:ok, passkey_login} = Auth.login_plaintext(passkey_user.username, @password, true)

    registration_options =
      passkey_login.token
      |> authorized()
      |> get("/api/v1/auth/webauthn/register/options")

    assert registration_options.status == 200
  end

  # 为权限测试建立只有必要业务权限的本地用户。
  defp create_user(permissions) do
    role_id = Identity.v7()

    role =
      Repo.insert!(%SysRole{
        role_id: role_id,
        role_name: "MFA recent authentication",
        role_key: "mfa_recent_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: "ALL",
        status: 1,
        deleted: false
      })

    Enum.each(permissions, fn code ->
      permission =
        Repo.get_by(SysPermission, permission: code) ||
          Repo.insert!(%SysPermission{
            permission_id: Identity.permission_id(code),
            permission: code,
            resource: code |> String.split(":") |> hd(),
            domain: "default",
            action: code |> String.split(":") |> List.last(),
            status: 1,
            deprecated: false
          })

      Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: permission.permission_id})
    end)

    PolicyCache.invalidate()

    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        user_id: Identity.v7(),
        username: "mfa_recent_#{System.unique_integer([:positive])}",
        password: @password,
        role_id: role.role_id,
        status: 1
      })
      |> Repo.insert!()

    Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: role.role_id})
    user
  end

  # 在真实会话中登记 TOTP 并返回一次性恢复码，供真实 REST 登录核验复用。
  defp enroll_factor(user, claims) do
    {:ok, enrollment} =
      Mfa.begin_enrollment(user.user_id, user.username, claims["client_id"], claims["sid"])

    verification =
      Mfa.verify_enrollment(
        user.user_id,
        enrollment.challenge_id,
        claims["client_id"],
        claims["sid"],
        Totp.code(enrollment.secret, System.system_time(:second)),
        nil
      )

    {:ok, %{recovery_codes: codes}} = verification
    {enrollment.secret, codes}
  end

  # 按真实 HTTP 认证结果完成 OTP step-up，返回新 access token。
  defp enroll_and_step_up(user) do
    {:ok, initial} = Auth.login_plaintext(user.username, @password, true)
    {:ok, claims} = Token.verify(initial.token, Token.access_type())
    {secret, _recovery_codes} = enroll_factor(user, claims)
    Auth.logout(initial.refresh_token)

    {:ok, current} = Auth.login_plaintext(user.username, @password, true)
    {:ok, challenge} = Mfa.begin_step_up(user.user_id, current.client_id, current.session_id)
    code = Totp.code(secret, System.system_time(:second) + Totp.step_seconds())

    {:ok, step_up} =
      Auth.complete_mfa_step_up(current.token, challenge.id, code, nil)

    step_up.token
  end

  defp authorized(token),
    do: Plug.Conn.put_req_header(build_conn(), "authorization", "Bearer #{token}")
end
