defmodule KeystonePhoenixWeb.MfaChallengeRateLimitTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Mfa.Challenge
  alias KeystonePhoenix.Auth.Mfa.ChallengeCleanup
  alias KeystonePhoenix.Auth.Mfa.Totp
  alias KeystonePhoenix.Auth.Token
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.User.SysUserRole

  @tag :integration
  test "limits HTTP step-up requests per session and releases the quota after the window" do
    user = create_mfa_user()
    {token, session_id, _secret} = enroll_and_login(user)

    challenge_ids =
      for _request <- 1..10 do
        response = begin_step_up(token)
        assert response.status == 201
        json_response(response, 201)["data"]["challengeId"]
      end

    [first_challenge_id | _] = challenge_ids
    now = DateTime.utc_now()

    Repo.update_all(
      from(challenge in Challenge, where: challenge.id == ^first_challenge_id),
      set: [
        consumed_at: now,
        expires_at: DateTime.add(now, -5, :second),
        inserted_at: DateTime.add(now, -30, :second)
      ]
    )

    limited = begin_step_up(token)
    assert limited.status == 429
    assert get_in(json_response(limited, 429), ["error", "code"]) == "rate_limited"

    {:ok, replacement_tokens} = Auth.login_plaintext(user.username, "Strong!123", true)
    assert {:ok, replacement_claims} = Token.verify(replacement_tokens.token, Token.access_type())
    refute replacement_claims["sid"] == session_id
    replacement_session_id = replacement_claims["sid"]

    replacement_token = replacement_tokens.token
    assert begin_step_up(replacement_token).status == 201

    for _request <- 1..9 do
      assert begin_step_up(replacement_token).status == 201
    end

    assert begin_step_up(replacement_token).status == 429

    cutoff = DateTime.add(DateTime.utc_now(), -61, :second)

    Repo.update_all(
      from(challenge in Challenge,
        where:
          challenge.user_id == ^user.user_id and challenge.session_id == ^replacement_session_id and
            challenge.purpose == "STEP_UP"
      ),
      set: [inserted_at: cutoff]
    )

    assert begin_step_up(replacement_token).status == 201
  end

  @tag :integration
  test "cleans expired challenges in bounded batches and retains step-up rows in the issue window" do
    user = create_mfa_user()
    {token, session_id, _secret} = enroll_and_login(user)
    now = DateTime.utc_now()

    {:ok, old_step_up} = Mfa.begin_step_up(user.user_id, "web", session_id)

    Repo.update_all(
      from(challenge in Challenge, where: challenge.id == ^old_step_up.id),
      set: [
        expires_at: DateTime.add(now, -60, :second),
        inserted_at: DateTime.add(now, -120, :second)
      ]
    )

    recent_step_ups =
      for _request <- 1..10 do
        {:ok, challenge} = Mfa.begin_step_up(user.user_id, "web", session_id)
        challenge
      end

    [recent_expired | active_step_ups] = recent_step_ups

    Repo.update_all(
      from(challenge in Challenge, where: challenge.id == ^recent_expired.id),
      set: [
        consumed_at: now,
        expires_at: DateTime.add(now, -5, :second),
        inserted_at: DateTime.add(now, -30, :second)
      ]
    )

    login_challenge =
      %Challenge{}
      |> Challenge.changeset(%{
        id: Identity.v7(),
        user_id: user.user_id,
        purpose: "LOGIN",
        client_id: "web",
        expires_at: DateTime.add(now, 300, :second)
      })
      |> Repo.insert!()

    Repo.update_all(
      from(challenge in Challenge, where: challenge.id == ^login_challenge.id),
      set: [
        expires_at: DateTime.add(now, -10, :second),
        inserted_at: DateTime.add(now, -15, :second)
      ]
    )

    assert {:ok, 1} = ChallengeCleanup.cleanup_expired_batch(now, 60, 1)
    assert Repo.get(Challenge, old_step_up.id) == nil
    assert Repo.get(Challenge, login_challenge.id) != nil
    assert Repo.get(Challenge, recent_expired.id) != nil
    assert Enum.all?(active_step_ups, &(Repo.get(Challenge, &1.id) != nil))

    assert {:ok, 1} = ChallengeCleanup.cleanup_expired_batch(now, 60, 1)
    assert Repo.get(Challenge, login_challenge.id) == nil
    assert Repo.get(Challenge, recent_expired.id) != nil
    assert {:ok, 0} = ChallengeCleanup.cleanup_expired_batch(now, 60, 1)

    response = begin_step_up(token)
    assert response.status == 429
    assert get_in(json_response(response, 429), ["error", "code"]) == "rate_limited"
  end

  # 创建真实数据库用户，并启用 TOTP 后返回当前有效 AAL1 会话。
  defp enroll_and_login(user) do
    {:ok, initial_tokens} = Auth.login_plaintext(user.username, "Strong!123", true)
    assert {:ok, initial_claims} = Token.verify(initial_tokens.token, Token.access_type())

    {:ok, enrollment} =
      Mfa.begin_enrollment(
        user.user_id,
        user.username,
        initial_claims["client_id"],
        initial_claims["sid"]
      )

    assert {:ok, _verification} =
             Mfa.verify_enrollment(
               user.user_id,
               enrollment.challenge_id,
               initial_claims["client_id"],
               initial_claims["sid"],
               Totp.code(enrollment.secret, System.system_time(:second))
             )

    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123", true)
    assert {:ok, claims} = Token.verify(tokens.token, Token.access_type())
    {tokens.token, claims["sid"], enrollment.secret}
  end

  # 创建已有系统管理员角色绑定的独立测试用户。
  defp create_mfa_user do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        user_id: Identity.v7(),
        username: "mfa_rate_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        role_id: role.role_id,
        status: 1
      })
      |> Repo.insert!()

    Repo.insert!(%SysUserRole{user_id: user.user_id, role_id: role.role_id})
    user
  end

  # 每次使用新 Conn 调用真实 MFA HTTP 路由。
  defp begin_step_up(token) do
    build_conn()
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    |> post("/api/v1/auth/mfa/step-up", %{})
  end
end
