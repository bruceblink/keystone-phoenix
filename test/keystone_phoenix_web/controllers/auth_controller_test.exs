defmodule KeystonePhoenixWeb.AuthControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Config.SysConfig
  alias KeystonePhoenix.Repo
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
    assert get_in(json_response(conn, 409), ["error", "code"]) == "validation_failed"
  end

  test "changes a flagged initial password and revokes the requirement", %{user: user} do
    user = Repo.update!(Ecto.Changeset.change(user, must_change_password: true))

    response =
      build_conn()
      |> post("/api/v1/auth/change-initial-password", %{
        "username" => user.username,
        "currentPassword" => "Strong!123",
        "newPassword" => "Changed!456"
      })
      |> json_response(200)

    assert response["data"] == %{"updated" => true}

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

    assert get_in(response, ["error", "code"]) == "validation_failed"
  end

  test "uses the shared token response schema for login and refresh", %{user: user} do
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
    assert get_in(json_response(conn, 429), ["error", "code"]) == "validation_failed"
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

  defp encrypted_password(password) do
    [entry] = :public_key.pem_decode(Token.public_key_pem())
    public_key = :public_key.pem_entry_decode(entry)
    password |> :public_key.encrypt_public(public_key) |> Base.encode64()
  end
end
