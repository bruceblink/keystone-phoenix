defmodule KeystonePhoenixWeb.AuthControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.AuthSession
  alias KeystonePhoenix.Auth.RefreshToken
  alias KeystonePhoenix.Auth.Session
  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenix.RateLimiter
  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Config.SysConfig
  alias KeystonePhoenix.Log.SysLoginInfo
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.RuntimeStore
  alias KeystonePhoenix.User.SysUser

  setup do
    Config.refresh_cache(
      authorization: %{principal: %{data_scope: "TENANT", permissions: ["config:refresh"]}}
    )

    _captcha_config =
      Repo.get_by(SysConfig, config_key: "sys.account.captchaOnOff") ||
        %SysConfig{}
        |> SysConfig.changeset(%{
          config_name: "验证码开关",
          config_key: "sys.account.captchaOnOff",
          config_value: "false",
          is_allow_change: true
        })
        |> Repo.insert!()

    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        username: "http_auth_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        status: 1
      })
      |> Repo.insert!()

    on_exit(fn ->
      Config.refresh_cache(
        authorization: %{principal: %{data_scope: "TENANT", permissions: ["config:refresh"]}}
      )
    end)

    {:ok, user: user}
  end

  test "returns HTTP 409 and code 10210 for a repeated login", %{conn: conn, user: user} do
    assert {:ok, _tokens} = Auth.login_plaintext(user.username, "Strong!123")

    conn =
      post(conn, "/api/v1/auth/login", %{
        "username" => user.username,
        "password" => encrypted_password("Strong!123")
      })

    assert conn.status == 409
    assert get_in(json_response(conn, 409), ["error", "code"]) == "active_session_conflict"
  end

  test "accepts the plain password format used by admin-web", %{user: user} do
    response =
      build_conn()
      |> post("/api/v1/auth/login", %{
        "username" => user.username,
        "password" => "Strong!123",
        "forceLogin" => true
      })
      |> json_response(200)

    assert is_binary(response["data"]["accessToken"])
    assert is_binary(response["data"]["refreshToken"])
  end

  test "blocks an initial-password account before issuing a session", %{conn: conn, user: user} do
    Repo.update!(Ecto.Changeset.change(user, must_change_password: true))

    assert {:error, :precondition_required} = Auth.login_plaintext(user.username, "Strong!123")

    response =
      conn
      |> post("/api/v1/auth/login", %{
        "username" => user.username,
        "password" => "Strong!123"
      })
      |> json_response(428)

    assert get_in(response, ["error", "code"]) == "precondition_required"
    refute Map.has_key?(response["data"] || %{}, "accessToken")
    assert Repo.get_by(AuthSession, user_id: user.user_id) == nil
  end

  test "rejects initial-password change for a disabled account", %{user: user} do
    user = Repo.update!(Ecto.Changeset.change(user, must_change_password: true, status: 0))

    response =
      build_conn()
      |> post("/api/v1/auth/change-initial-password", %{
        "username" => user.username,
        "currentPassword" => "Strong!123",
        "newPassword" => "Changed!456"
      })
      |> json_response(401)

    assert get_in(response, ["error", "code"]) == "invalid_credential"
    assert Repo.get!(SysUser, user.user_id).must_change_password
  end

  test "limits repeated initial-password attempts and returns Retry-After", %{user: user} do
    Repo.update!(Ecto.Changeset.change(user, must_change_password: true))

    params = %{
      "username" => user.username,
      "currentPassword" => "Wrong!123",
      "newPassword" => "Changed!456"
    }

    for _attempt <- 1..10 do
      conn = build_conn() |> post("/api/v1/auth/change-initial-password", params)
      response = json_response(conn, 401)
      assert get_in(response, ["error", "code"]) == "invalid_credential"
      refute Jason.encode!(response) =~ params["currentPassword"]
      refute Jason.encode!(response) =~ params["newPassword"]
    end

    conn = build_conn() |> post("/api/v1/auth/change-initial-password", params)
    response = json_response(conn, 429)
    assert get_in(response, ["error", "code"]) == "rate_limited"
    assert [retry_after] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry_after) >= 1
    refute Jason.encode!(response) =~ params["currentPassword"]
    refute Jason.encode!(response) =~ params["newPassword"]
    assert Repo.get_by(AuthSession, user_id: user.user_id) == nil
    assert Repo.get!(SysUser, user.user_id).must_change_password
    assert_login_audit_excludes(user.username, [params["currentPassword"], params["newPassword"]])
  end

  test "returns service unavailable when the shared limiter has no capacity", %{user: user} do
    Repo.update!(Ecto.Changeset.change(user, must_change_password: true))
    previous_max = Application.get_env(:keystone_phoenix, :rate_limit_max_entries)
    limiter_key = "test-initial-password-capacity-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      RateLimiter.delete(limiter_key)

      if is_nil(previous_max),
        do: Application.delete_env(:keystone_phoenix, :rate_limit_max_entries),
        else: Application.put_env(:keystone_phoenix, :rate_limit_max_entries, previous_max)
    end)

    Application.put_env(:keystone_phoenix, :rate_limit_max_entries, 1)

    :ets.insert(RuntimeStore.rate_limit_table(), {
      limiter_key,
      1,
      System.monotonic_time(:millisecond) + 60_000
    })

    params = %{
      "username" => user.username,
      "currentPassword" => "Strong!123",
      "newPassword" => "Changed!456"
    }

    response =
      build_conn()
      |> post("/api/v1/auth/change-initial-password", params)
      |> json_response(503)

    assert get_in(response, ["error", "code"]) == "service_unavailable"
    refute Jason.encode!(response) =~ params["currentPassword"]
    refute Jason.encode!(response) =~ params["newPassword"]
    assert Repo.get_by(AuthSession, user_id: user.user_id) == nil
    assert Repo.get!(SysUser, user.user_id).must_change_password
    assert_login_audit_excludes(user.username, [params["currentPassword"], params["newPassword"]])
  end

  test "changes a flagged initial password and revokes the requirement", %{user: user} do
    user = Repo.update!(Ecto.Changeset.change(user, must_change_password: true))
    password_hash = Repo.get!(SysUser, user.user_id).password
    wrong_current_password = "Wrong!123"

    invalid_current_password =
      build_conn()
      |> post("/api/v1/auth/change-initial-password", %{
        "username" => user.username,
        "currentPassword" => wrong_current_password,
        "newPassword" => "Changed!456"
      })
      |> json_response(401)

    assert get_in(invalid_current_password, ["error", "code"]) == "invalid_credential"

    same_password =
      build_conn()
      |> post("/api/v1/auth/change-initial-password", %{
        "username" => user.username,
        "currentPassword" => "Strong!123",
        "newPassword" => "Strong!123"
      })
      |> json_response(422)

    assert get_in(same_password, ["error", "code"]) == "validation_failed"

    unchanged = Repo.get!(SysUser, user.user_id)
    assert unchanged.password == password_hash
    assert unchanged.must_change_password

    params = %{
      "username" => user.username,
      "currentPassword" => "Strong!123",
      "newPassword" => "Changed!456"
    }

    response =
      build_conn()
      |> post("/api/v1/auth/change-initial-password", params)
      |> json_response(200)

    assert response["data"] == %{"updated" => true}
    refute Jason.encode!(response) =~ params["currentPassword"]
    refute Jason.encode!(response) =~ params["newPassword"]

    assert_login_audit_excludes(user.username, [
      wrong_current_password,
      params["currentPassword"],
      params["newPassword"]
    ])

    assert Repo.get!(SysUser, user.user_id).must_change_password == false

    assert {:ok, _tokens} = Auth.login_plaintext(user.username, "Changed!456")
  end

  test "rejects initial password change when the flag is not set", %{conn: conn, user: user} do
    response =
      conn
      |> post("/api/v1/auth/change-initial-password", %{
        "username" => user.username,
        "currentPassword" => "Strong!123",
        "newPassword" => "Changed!456"
      })
      |> json_response(409)

    assert get_in(response, ["error", "code"]) == "resource_conflict"
  end

  test "rotates a live refresh token when its future microsecond is less than now", %{user: user} do
    login =
      build_conn()
      |> post("/api/v1/auth/login", %{
        "username" => user.username,
        "password" => encrypted_password("Strong!123")
      })
      |> json_response(200)

    data = login["data"]
    assert is_binary(data["accessToken"])
    assert is_binary(data["refreshToken"])
    assert data["tokenType"] == "Bearer"
    assert data["username"] == user.username
    assert is_binary(data["sessionId"])
    assert data["clientId"] == "web"
    refute Map.has_key?(data, "token")
    refute Map.has_key?(data, "currentUser")
    assert Session.valid?(data["sessionId"], user.user_id)

    {:ok, claims} = Token.verify(data["refreshToken"], Token.refresh_type())
    now = DateTime.utc_now()

    now =
      if elem(now.microsecond, 0) == 0 do
        Process.sleep(1)
        DateTime.utc_now()
      else
        now
      end

    # 构造实际晚于当前时间、但微秒字段更小的时间，确保按时刻而非结构体字段顺序判断。
    future = DateTime.add(now, 60, :second)
    future = %{future | microsecond: {elem(now.microsecond, 0) - 1, elem(now.microsecond, 1)}}
    assert DateTime.compare(future, now) == :gt

    session = Repo.get_by!(AuthSession, id: data["sessionId"])

    session
    |> Ecto.Changeset.change(
      refresh_expires_at: future,
      idle_expires_at: future,
      expires_at: future
    )
    |> Repo.update!()

    token_record = Repo.get!(RefreshToken, claims["jti"])

    token_record
    |> Ecto.Changeset.change(expires_at: future, idle_expires_at: future)
    |> Repo.update!()

    assert DateTime.compare(future, DateTime.utc_now()) == :gt

    refreshed =
      build_conn()
      |> post("/api/v1/auth/refresh", %{"refreshToken" => data["refreshToken"]})
      |> json_response(200)

    assert is_binary(refreshed["data"]["accessToken"])
    assert is_binary(refreshed["data"]["refreshToken"])
    refute Map.has_key?(refreshed["data"], "token")
  end

  test "uses the same response for an unknown username and a wrong password", %{user: user} do
    wrong_password =
      build_conn()
      |> post("/api/v1/auth/login", %{
        "username" => user.username,
        "password" => encrypted_password("Wrong!123")
      })
      |> json_response(401)

    unknown_username =
      build_conn()
      |> post("/api/v1/auth/login", %{
        "username" => "missing_#{System.unique_integer([:positive])}",
        "password" => encrypted_password("Wrong!123")
      })
      |> json_response(401)

    assert get_in(wrong_password, ["error", "code"]) == "invalid_credential"
    assert get_in(unknown_username, ["error", "code"]) == "invalid_credential"
    assert wrong_password["message"] == unknown_username["message"]
    assert wrong_password["data"] == unknown_username["data"]
  end

  test "limits repeated HTTP login attempts", %{user: user} do
    params = %{
      "username" => user.username,
      "password" => encrypted_password("Wrong!123")
    }

    for _attempt <- 1..10 do
      assert get_in(build_conn() |> post("/api/v1/auth/login", params) |> json_response(401), [
               "error",
               "code"
             ]) ==
               "invalid_credential"
    end

    conn = build_conn() |> post("/api/v1/auth/login", params)
    assert conn.status == 429
    assert get_in(json_response(conn, 429), ["error", "code"]) == "rate_limited"
    assert [retry_after] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry_after) >= 1
  end

  test "enforces enabled one-time captcha for missing, invalid, expired, and reused values", %{
    conn: conn,
    user: user
  } do
    set_captcha(true)

    assert get_in(
             conn
             |> post(
               "/api/v1/auth/login",
               login_params(user, captcha_code: nil, captcha_key: nil)
             )
             |> json_response(422),
             ["error", "code"]
           ) == "validation_failed"

    {expired_key, expired_answer} = store_captcha(-1)

    assert get_in(
             conn
             |> post(
               "/api/v1/auth/login",
               login_params(user, captcha_code: expired_answer, captcha_key: expired_key)
             )
             |> json_response(422),
             ["error", "code"]
           ) == "validation_failed"

    {valid_key, valid_answer} = store_captcha()

    assert get_in(
             conn
             |> post(
               "/api/v1/auth/login",
               login_params(user, captcha_code: "incorrect", captcha_key: valid_key)
             )
             |> json_response(422),
             ["error", "code"]
           ) == "validation_failed"

    assert get_in(
             conn
             |> post(
               "/api/v1/auth/login",
               login_params(user, captcha_code: valid_answer, captcha_key: valid_key)
             )
             |> json_response(422),
             ["error", "code"]
           ) == "validation_failed"

    {one_time_key, one_time_answer} = store_captcha()

    assert get_in(
             conn
             |> post(
               "/api/v1/auth/login",
               login_params(user, captcha_code: one_time_answer, captcha_key: one_time_key)
             )
             |> json_response(200),
             ["success"]
           ) == true

    assert get_in(
             build_conn()
             |> post(
               "/api/v1/auth/login",
               login_params(user, captcha_code: one_time_answer, captcha_key: one_time_key)
             )
             |> json_response(422),
             ["error", "code"]
           ) == "validation_failed"
  end

  defp login_params(user, opts) do
    %{
      "username" => user.username,
      "password" => encrypted_password("Strong!123"),
      "captchaCode" => Keyword.get(opts, :captcha_code),
      "captchaCodeKey" => Keyword.get(opts, :captcha_key)
    }
  end

  defp set_captcha(enabled?) do
    config = Repo.get_by!(SysConfig, config_key: "sys.account.captchaOnOff")

    {:ok, _config} =
      config
      |> Ecto.Changeset.change(config_value: if(enabled?, do: "true", else: "false"))
      |> Repo.update()

    Config.refresh_cache(
      authorization: %{principal: %{data_scope: "TENANT", permissions: ["config:refresh"]}}
    )
  end

  defp store_captcha(ttl \\ 120) do
    key = "auth-test-#{System.unique_integer([:positive])}"
    answer = "captcha-answer"
    expires_at = System.monotonic_time(:millisecond) + ttl * 1_000

    :ets.insert(KeystonePhoenix.RuntimeStore.captcha_table(), {
      "keystone:auth:captcha:" <> key,
      answer,
      expires_at
    })

    if ttl > 0, do: Process.sleep(2)
    {key, answer}
  end

  # 确认 HTTP 改密审计记录只保存稳定消息，不保存密码内容。
  defp assert_login_audit_excludes(username, secrets) do
    messages =
      from(log in SysLoginInfo,
        where: log.username == ^username,
        select: log.msg
      )
      |> Repo.all()

    Enum.each(secrets, fn secret ->
      refute Enum.any?(messages, &String.contains?(&1, secret))
    end)
  end

  defp encrypted_password(password) do
    [entry] = :public_key.pem_decode(Token.public_key_pem())
    public_key = :public_key.pem_entry_decode(entry)
    password |> :public_key.encrypt_public(public_key) |> Base.encode64()
  end
end
