defmodule KeystonePhoenix.Auth.MfaTest do
  use KeystonePhoenix.DataCase, async: false

  import Ecto.Query

  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.Mfa.{Challenge, RecoveryCode, Totp}
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  setup do
    previous_key = Application.get_env(:keystone_phoenix, :mfa_master_key)
    previous_pepper = Application.get_env(:keystone_phoenix, :mfa_recovery_pepper)

    Application.put_env(
      :keystone_phoenix,
      :mfa_master_key,
      Base.encode64(:crypto.strong_rand_bytes(32))
    )

    Application.put_env(:keystone_phoenix, :mfa_recovery_pepper, "test-only-mfa-pepper")

    on_exit(fn ->
      Application.put_env(:keystone_phoenix, :mfa_master_key, previous_key)
      Application.put_env(:keystone_phoenix, :mfa_recovery_pepper, previous_pepper)
    end)

    :ok
  end

  test "matches the RFC 6238 SHA-1 vectors" do
    secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    assert Totp.code(secret, 59) == "287082"
    assert Totp.code(secret, 1_111_111_109) == "081804"
    assert Totp.code(secret, 1_111_111_111) == "050471"
    assert Totp.code(secret, 1_234_567_890) == "005924"
    assert Totp.code(secret, 2_000_000_000) == "279037"
    assert Totp.code(secret, 20_000_000_000) == "353130"
  end

  test "requires enrollment before enabling policy", %{} do
    user = create_user()

    assert {:error, :mfa_not_enrolled} = Mfa.set_required(user.user_id, true)
    assert {:ok, %{required: false, challenge: nil}} = Mfa.prepare_login(user.user_id)
  end

  test "enrollment returns one recovery batch and consumes its challenge once" do
    user = create_user()
    session_id = Identity.v7()

    assert {:ok, enrollment} =
             Mfa.begin_enrollment(user.user_id, user.username, "web", session_id)

    code = Totp.code(enrollment.secret, System.system_time(:second))

    assert {:ok, %{assurance: "AAL2", amr: "otp", recovery_codes: codes}} =
             Mfa.verify_enrollment(user.user_id, enrollment.challenge_id, "web", session_id, code)

    assert length(codes) == RecoveryCode.count()

    assert {:error, :invalid_challenge} =
             Mfa.verify_enrollment(user.user_id, enrollment.challenge_id, "web", session_id, code)

    assert {:ok, %{enabled: true, required: false}} = Mfa.status(user.user_id)
    assert {:ok, :ok} = Mfa.set_required(user.user_id, true)
    assert {:ok, %{required: true, challenge: challenge}} = Mfa.prepare_login(user.user_id, "web")
    [recovery_code | _] = codes

    assert {:ok, %{assurance: "AAL2", amr: "recovery"}} =
             Mfa.verify_login(user.user_id, challenge.id, "web", recovery_code)

    assert {:ok, %{challenge: next_challenge}} = Mfa.prepare_login(user.user_id, "web")

    assert {:error, :invalid_mfa_code} =
             Mfa.verify_login(user.user_id, next_challenge.id, "web", recovery_code)
  end

  test "expired challenge and consumed recovery code are rejected" do
    user = create_user()
    session_id = Identity.v7()

    assert {:ok, enrollment} =
             Mfa.begin_enrollment(user.user_id, user.username, "web", session_id)

    Repo.update_all(
      from(challenge in Challenge, where: challenge.id == ^enrollment.challenge_id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert {:error, :invalid_challenge} =
             Mfa.verify_enrollment(
               user.user_id,
               enrollment.challenge_id,
               "web",
               session_id,
               Totp.code(enrollment.secret, System.system_time(:second))
             )

    # 重新 enrollment 后验证登录挑战的过期边界。
    assert {:ok, second} = Mfa.begin_enrollment(user.user_id, user.username, "web", session_id)

    assert {:ok, %{recovery_codes: _}} =
             Mfa.verify_enrollment(
               user.user_id,
               second.challenge_id,
               "web",
               session_id,
               Totp.code(second.secret, System.system_time(:second))
             )

    assert {:ok, :ok} = Mfa.set_required(user.user_id, true)
    assert {:ok, %{challenge: login_challenge}} = Mfa.prepare_login(user.user_id, "web")

    Repo.update_all(
      from(challenge in Challenge, where: challenge.id == ^login_challenge.id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert {:error, :invalid_challenge} =
             Mfa.verify_login(
               user.user_id,
               login_challenge.id,
               "web",
               Totp.code(second.secret, System.system_time(:second))
             )
  end

  test "concurrent login verification allows one challenge consumer" do
    user = create_user()
    session_id = Identity.v7()

    assert {:ok, enrollment} =
             Mfa.begin_enrollment(user.user_id, user.username, "web", session_id)

    code = Totp.code(enrollment.secret, System.system_time(:second))

    assert {:ok, %{recovery_codes: recovery_codes}} =
             Mfa.verify_enrollment(user.user_id, enrollment.challenge_id, "web", session_id, code)

    assert {:ok, :ok} = Mfa.set_required(user.user_id, true)
    assert {:ok, %{challenge: challenge}} = Mfa.prepare_login(user.user_id, "web")
    [login_code | _] = recovery_codes

    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
          Mfa.verify_login(user.user_id, challenge.id, "web", login_code)
        end)
      end

    results = Enum.map(tasks, &Task.await(&1, 5_000))
    assert Enum.count(results, &match?({:ok, %{assurance: "AAL2"}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :invalid_challenge}, &1)) == 1
  end

  test "recovery code hashes use a deployment pepper" do
    batch = RecoveryCode.generate_batch()
    [code | _] = batch.codes
    hash = RecoveryCode.hash(code)

    assert RecoveryCode.matches?(code, hash)
    refute RecoveryCode.matches?(code, hash, "another-pepper-that-is-long")
    refute RecoveryCode.matches?("0000", hash)
  end

  defp create_user do
    %SysUser{}
    |> SysUser.create_changeset(%{
      username: "mfa_#{System.unique_integer([:positive])}",
      password: "Strong!123",
      status: 1
    })
    |> Repo.insert!()
  end
end
