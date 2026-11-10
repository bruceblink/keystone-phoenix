defmodule KeystonePhoenixWeb.AuthControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenix.Config
  alias KeystonePhoenix.Config.SysConfig
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  setup do
    Config.refresh_cache()

    _captcha_config =
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
      |> Ecto.Changeset.put_change(:is_admin, true)
      |> Repo.insert!()

    on_exit(&Config.refresh_cache/0)

    {:ok, user: user}
  end

  test "returns HTTP 409 and code 10210 for a repeated login", %{conn: conn, user: user} do
    assert {:ok, _tokens} = Auth.login_plaintext(user.username, "Strong!123")

    conn =
      post(conn, "/login", %{
        "username" => user.username,
        "password" => encrypted_password("Strong!123")
      })

    assert conn.status == 409
    assert %{"code" => 10210} = json_response(conn, 409)
  end

  test "limits repeated HTTP login attempts", %{user: user} do
    params = %{
      "username" => user.username,
      "password" => encrypted_password("Wrong!123")
    }

    for _attempt <- 1..10 do
      assert %{"code" => 10002} = build_conn() |> post("/login", params) |> json_response(401)
    end

    conn = build_conn() |> post("/login", params)
    assert conn.status == 429
    assert %{"code" => 42903} = json_response(conn, 429)
    assert [retry_after] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry_after) >= 1
  end

  test "enforces enabled one-time captcha for missing, invalid, expired, and reused values", %{
    conn: conn,
    user: user
  } do
    set_captcha(true)

    assert %{"code" => 10205} =
             conn
             |> post("/login", login_params(user, captcha_code: nil, captcha_key: nil))
             |> json_response(422)

    {expired_key, expired_answer} = store_captcha(-1)

    assert %{"code" => 10204} =
             conn
             |> post(
               "/login",
               login_params(user, captcha_code: expired_answer, captcha_key: expired_key)
             )
             |> json_response(422)

    {valid_key, valid_answer} = store_captcha()

    assert %{"code" => 10203} =
             conn
             |> post(
               "/login",
               login_params(user, captcha_code: "incorrect", captcha_key: valid_key)
             )
             |> json_response(422)

    assert %{"code" => 10204} =
             conn
             |> post(
               "/login",
               login_params(user, captcha_code: valid_answer, captcha_key: valid_key)
             )
             |> json_response(422)

    {one_time_key, one_time_answer} = store_captcha()

    assert %{"code" => 0} =
             conn
             |> post(
               "/login",
               login_params(user, captcha_code: one_time_answer, captcha_key: one_time_key)
             )
             |> json_response(200)

    assert %{"code" => 10204} =
             build_conn()
             |> post(
               "/login",
               login_params(user, captcha_code: one_time_answer, captcha_key: one_time_key)
             )
             |> json_response(422)
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

    Config.refresh_cache()
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
