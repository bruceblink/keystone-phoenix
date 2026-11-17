defmodule KeystonePhoenixWeb.MfaContractTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Mfa.Totp
  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenix.Authz.{PolicyCache, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.User.SysUserRole

  test "MFA verification uses the versioned auth path and validates its body", %{conn: conn} do
    response = post(conn, "/api/v1/auth/mfa/verify", %{})

    assert response.status == 422
    assert get_in(json_response(response, 422), ["error", "code"]) == "validation_failed"
  end

  test "protected MFA management routes require a current access token", %{conn: conn} do
    response = post(conn, "/api/v1/auth/mfa/enroll", %{})

    assert response.status == 401
    assert get_in(json_response(response, 401), ["error", "code"]) == "session_revoked"
  end

  test "old unversioned MFA paths stay unavailable while LiveView login is available" do
    assert post(build_conn(), "/mfa/verify", %{}).status == 404
    assert post(build_conn(), "/api/v1/mfa/verify", %{}).status == 404
    assert html_response(get(build_conn(), "/login"), 200) =~ "login-form"
  end

  @tag :integration
  test "admin can enroll a TOTP factor and complete MFA login", %{conn: conn} do
    previous_key = Application.get_env(:keystone_phoenix, :mfa_master_key)
    previous_pepper = Application.get_env(:keystone_phoenix, :mfa_recovery_pepper)

    Application.put_env(
      :keystone_phoenix,
      :mfa_master_key,
      Base.encode64(:crypto.strong_rand_bytes(32))
    )

    Application.put_env(:keystone_phoenix, :mfa_recovery_pepper, "mfa-contract-test-pepper")

    on_exit(fn ->
      Application.put_env(:keystone_phoenix, :mfa_master_key, previous_key)
      Application.put_env(:keystone_phoenix, :mfa_recovery_pepper, previous_pepper)
    end)

    admin_role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        username: "mfa_http_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        role_id: admin_role.role_id,
        status: 1
      })
      |> Repo.insert!()

    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    authorized = put_req_header(conn, "authorization", "Bearer #{tokens.token}")
    enrollment = authorized |> post("/api/v1/auth/mfa/enroll", %{}) |> json_response(201)
    enrollment_data = enrollment["data"]
    code = Totp.code(enrollment_data["secret"], System.system_time(:second))

    verified =
      build_conn()
      |> put_req_header("authorization", "Bearer #{tokens.token}")
      |> post("/api/v1/auth/mfa/enroll/verify", %{
        "challengeId" => enrollment_data["challengeId"],
        "code" => code
      })
      |> json_response(200)

    assert verified["success"] == true
    assert length(verified["data"]["recoveryCodes"]) > 0

    {:ok, post_enrollment_tokens} = Auth.login_plaintext(user.username, "Strong!123", true)

    step_up_challenge =
      build_conn()
      |> put_req_header("authorization", "Bearer #{post_enrollment_tokens.token}")
      |> post("/api/v1/auth/mfa/step-up", %{})
      |> json_response(201)

    step_up =
      build_conn()
      |> put_req_header("authorization", "Bearer #{post_enrollment_tokens.token}")
      |> post("/api/v1/auth/mfa/step-up/verify", %{
        "challengeId" => step_up_challenge["data"]["challengeId"],
        "code" => Totp.code(enrollment_data["secret"], System.system_time(:second) + 30)
      })
      |> json_response(200)

    assert MapSet.new(Map.keys(step_up_challenge["data"])) ==
             MapSet.new(["challengeId", "clientId", "expiresAt"])

    assert step_up["data"]["authenticationLevel"] == "AAL2"

    assert {:ok, step_up_claims} =
             Token.verify(step_up["data"]["accessToken"], Token.access_type())

    assert step_up_claims["aal"] == "AAL2"
    assert step_up_claims["amr"] == ["otp"]

    old_access_response =
      build_conn()
      |> put_req_header("authorization", "Bearer #{post_enrollment_tokens.token}")
      |> get("/api/v1/profile")

    assert old_access_response.status == 401

    refresh_response =
      build_conn()
      |> post("/api/v1/auth/refresh", %{
        "refreshToken" => post_enrollment_tokens.refresh_token
      })

    assert refresh_response.status == 200
    refresh_data = json_response(refresh_response, 200)["data"]

    refreshed_challenge =
      build_conn()
      |> put_req_header("authorization", "Bearer #{refresh_data["accessToken"]}")
      |> post("/api/v1/auth/mfa/step-up", %{})
      |> json_response(201)

    refreshed_step_up =
      build_conn()
      |> put_req_header("authorization", "Bearer #{refresh_data["accessToken"]}")
      |> post("/api/v1/auth/mfa/step-up/verify", %{
        "challengeId" => refreshed_challenge["data"]["challengeId"],
        "code" => List.last(verified["data"]["recoveryCodes"])
      })
      |> json_response(200)

    policy =
      build_conn()
      |> put_req_header("authorization", "Bearer #{refreshed_step_up["data"]["accessToken"]}")
      |> put("/api/v1/auth/mfa/policy/#{user.user_id}", %{"required" => true})
      |> json_response(200)

    assert policy["data"] == %{"required" => true, "userId" => user.user_id}

    login =
      build_conn()
      |> post("/api/v1/auth/login", %{
        "username" => user.username,
        "password" => encrypted_password("Strong!123")
      })
      |> json_response(401)

    assert login["error"]["code"] == "mfa_required"
    [challenge_code | _] = verified["data"]["recoveryCodes"]

    completed =
      build_conn()
      |> post("/api/v1/auth/mfa/verify", %{
        "username" => user.username,
        "challengeId" => login["data"]["challengeId"],
        "code" => challenge_code
      })
      |> json_response(200)

    assert completed["success"] == true
    assert completed["data"]["authenticationLevel"] == "AAL2"
  end

  @tag :integration
  # 使用数据库中的普通角色验证真实 REST step-up 和身份绑定边界。
  test "business-only user completes REST step-up within the enrolled session" do
    previous_key = Application.get_env(:keystone_phoenix, :mfa_master_key)
    previous_pepper = Application.get_env(:keystone_phoenix, :mfa_recovery_pepper)

    Application.put_env(
      :keystone_phoenix,
      :mfa_master_key,
      Base.encode64(:crypto.strong_rand_bytes(32))
    )

    Application.put_env(:keystone_phoenix, :mfa_recovery_pepper, "mfa-step-up-http-pepper")

    on_exit(fn ->
      Application.put_env(:keystone_phoenix, :mfa_master_key, previous_key)
      Application.put_env(:keystone_phoenix, :mfa_recovery_pepper, previous_pepper)
    end)

    actor_role = create_role()
    grant_permission(actor_role.role_id, "role:delete")
    grant_permission(actor_role.role_id, "role:read")
    actor = create_user(actor_role.role_id)

    assert Repo.all(
             from binding in SysRolePermission,
               join: permission in SysPermission,
               on: permission.permission_id == binding.permission_id,
               where: binding.role_id == ^actor_role.role_id,
               select: permission.permission,
               order_by: permission.permission
           ) == ["role:delete", "role:read"]

    assert post(build_conn(), "/api/v1/auth/mfa/step-up", %{}).status == 401

    unauthenticated_verify =
      build_conn()
      |> post("/api/v1/auth/mfa/step-up/verify", %{
        "challengeId" => Identity.v7(),
        "code" => "000000"
      })

    assert unauthenticated_verify.status == 401

    assert get_in(json_response(unauthenticated_verify, 401), ["error", "code"]) ==
             "session_revoked"

    {:ok, initial_tokens} = Auth.login_plaintext(actor.username, "Strong!123", true)
    initial_auth = authorized(initial_tokens.token)

    assert post(initial_auth, "/api/v1/auth/mfa/enroll", %{}).status == 403

    assert put(initial_auth, "/api/v1/auth/mfa/policy/#{actor.user_id}", %{
             "required" => false
           }).status == 403

    assert {:ok, claims} = Token.verify(initial_tokens.token, Token.access_type())

    {:ok, enrollment} =
      Mfa.begin_enrollment(actor.user_id, actor.username, claims["client_id"], claims["sid"])

    enrollment_time = System.system_time(:second)

    assert {:ok, _verification} =
             Mfa.verify_enrollment(
               actor.user_id,
               enrollment.challenge_id,
               claims["client_id"],
               claims["sid"],
               Totp.code(enrollment.secret, enrollment_time),
               nil
             )

    {:ok, actor_tokens} = Auth.login_plaintext(actor.username, "Strong!123", true)
    assert {:ok, actor_claims} = Token.verify(actor_tokens.token, Token.access_type())
    assert actor_claims["aal"] == "AAL1"

    assert {:ok, issued_key} = ApiKey.issue(actor.user_id, "step-up boundary", ["role:delete"])

    api_key_conn =
      Plug.Conn.put_req_header(build_conn(), "authorization", "ApiKey #{issued_key.api_key}")

    for response <- [
          post(api_key_conn, "/api/v1/auth/mfa/step-up", %{}),
          post(api_key_conn, "/api/v1/auth/mfa/step-up/verify", %{
            "challengeId" => Identity.v7(),
            "code" => "000000"
          })
        ] do
      assert response.status == 403
      assert get_in(json_response(response, 403), ["error", "code"]) == "permission_denied"
    end

    step_up_challenge =
      actor_tokens.token
      |> authorized()
      |> post("/api/v1/auth/mfa/step-up", %{})
      |> json_response(201)

    assert MapSet.new(Map.keys(step_up_challenge["data"])) ==
             MapSet.new(["challengeId", "clientId", "expiresAt"])

    # 使用比 enrollment 更新的 TOTP 时间步，避免重复消费同一个验证码。
    current_time = System.system_time(:second)
    totp_step = Totp.step_seconds()

    step_up_time =
      if div(current_time, totp_step) > div(enrollment_time, totp_step),
        do: current_time,
        else: enrollment_time + totp_step

    step_up_code = Totp.code(enrollment.secret, step_up_time)

    invalid_challenge =
      actor_tokens.token
      |> authorized()
      |> post("/api/v1/auth/mfa/step-up/verify", %{
        "challengeId" => Identity.v7(),
        "code" => "000000"
      })

    assert invalid_challenge.status == 401

    assert get_in(json_response(invalid_challenge, 401), ["error", "code"]) ==
             "mfa_challenge_invalid"

    other_user = create_user(actor_role.role_id)
    {:ok, other_tokens} = Auth.login_plaintext(other_user.username, "Strong!123", true)

    cross_user_attempt =
      other_tokens.token
      |> authorized()
      |> post("/api/v1/auth/mfa/step-up/verify", %{
        "challengeId" => step_up_challenge["data"]["challengeId"],
        "code" => step_up_code
      })

    assert cross_user_attempt.status == 401

    assert get_in(json_response(cross_user_attempt, 401), ["error", "code"]) ==
             "mfa_challenge_invalid"

    stepped_up =
      actor_tokens.token
      |> authorized()
      |> post("/api/v1/auth/mfa/step-up/verify", %{
        "challengeId" => step_up_challenge["data"]["challengeId"],
        "code" => step_up_code
      })
      |> json_response(200)

    assert stepped_up["data"]["authenticationLevel"] == "AAL2"

    target_role = create_role()

    assert %{"success" => true} =
             stepped_up["data"]["accessToken"]
             |> authorized()
             |> delete("/api/v1/roles/#{target_role.role_id}")
             |> json_response(200)

    assert Repo.get!(SysRole, target_role.role_id).deleted

    {:ok, first_session} = Auth.login_plaintext(actor.username, "Strong!123", true)

    session_challenge =
      first_session.token
      |> authorized()
      |> post("/api/v1/auth/mfa/step-up", %{})
      |> json_response(201)

    {:ok, replacement_session} = Auth.login_plaintext(actor.username, "Strong!123", true)

    cross_session_attempt =
      replacement_session.token
      |> authorized()
      |> post("/api/v1/auth/mfa/step-up/verify", %{
        "challengeId" => session_challenge["data"]["challengeId"],
        "code" => step_up_code
      })

    assert cross_session_attempt.status == 401

    assert get_in(json_response(cross_session_attempt, 401), ["error", "code"]) ==
             "mfa_challenge_invalid"
  end

  # 测试角色只绑定显式业务权限，不继承管理员角色。
  defp create_role do
    %SysRole{}
    |> SysRole.changeset(%{
      role_name: "MFA step-up HTTP 测试",
      role_key: "mfa_step_up_http_#{System.unique_integer([:positive])}",
      role_sort: 1,
      data_scope: "ALL",
      status: 1
    })
    |> Repo.insert!()
  end

  # 为真实 HTTP 授权测试写入指定权限，并清除缓存中的旧判定。
  defp grant_permission(role_id, permission) do
    permission = Repo.get_by!(SysPermission, permission: permission)
    Repo.insert!(%SysRolePermission{role_id: role_id, permission_id: permission.permission_id})
    PolicyCache.invalidate()
  end

  # 创建测试用户和规范角色关联，供 Bearer 与 API Key 认证共用。
  defp create_user(role_id) do
    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        user_id: Identity.v7(),
        username: "mfa_step_up_http_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        role_id: role_id,
        status: 1
      })
      |> Repo.insert!()

    Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: role_id})
    user
  end

  # 每个请求使用独立连接，避免复用已发送的响应状态。
  defp authorized(token),
    do: Plug.Conn.put_req_header(build_conn(), "authorization", "Bearer #{token}")

  defp encrypted_password(password) do
    [entry] = :public_key.pem_decode(Token.public_key_pem())
    public_key = :public_key.pem_entry_decode(entry)
    password |> :public_key.encrypt_public(public_key) |> Base.encode64()
  end
end
