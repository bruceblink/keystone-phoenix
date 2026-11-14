defmodule KeystonePhoenixWeb.MfaContractTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Mfa.Totp
  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

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

  test "old unversioned MFA and login paths are not available" do
    assert post(build_conn(), "/mfa/verify", %{}).status == 404
    assert post(build_conn(), "/api/v1/mfa/verify", %{}).status == 404
    assert get(build_conn(), "/login").status == 404
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

    assert login["error"]["code"] == "invalid_credential"
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

  defp encrypted_password(password) do
    [entry] = :public_key.pem_decode(Token.public_key_pem())
    public_key = :public_key.pem_entry_decode(entry)
    password |> :public_key.encrypt_public(public_key) |> Base.encode64()
  end
end
