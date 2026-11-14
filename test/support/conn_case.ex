defmodule KeystonePhoenixWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use KeystonePhoenixWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint KeystonePhoenixWeb.Endpoint

      use KeystonePhoenixWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import KeystonePhoenixWeb.ConnCase
    end
  end

  setup tags do
    KeystonePhoenix.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "为 HTTP 测试用户完成一次 enrollment 和当前会话 step-up。"
  def step_up_token(user, password \\ "Strong!123") do
    {:ok, initial} = KeystonePhoenix.Auth.login_plaintext(user.username, password, true)

    {:ok, claims} =
      KeystonePhoenix.Auth.Token.verify(
        initial.token,
        KeystonePhoenix.Auth.Token.access_type()
      )

    {:ok, enrollment} =
      KeystonePhoenix.Auth.Mfa.begin_enrollment(
        user.user_id,
        user.username,
        claims["client_id"],
        claims["sid"]
      )

    secret = enrollment.secret
    now = System.system_time(:second)

    {:ok, _verification} =
      KeystonePhoenix.Auth.Mfa.verify_enrollment(
        user.user_id,
        enrollment.challenge_id,
        claims["client_id"],
        claims["sid"],
        KeystonePhoenix.Auth.Mfa.Totp.code(secret, now),
        nil
      )

    {:ok, fresh} = KeystonePhoenix.Auth.login_plaintext(user.username, password, true)

    {:ok, fresh_claims} =
      KeystonePhoenix.Auth.Token.verify(fresh.token, KeystonePhoenix.Auth.Token.access_type())

    {:ok, challenge} =
      KeystonePhoenix.Auth.Mfa.begin_step_up(
        user.user_id,
        fresh_claims["client_id"],
        fresh_claims["sid"]
      )

    {:ok, result} =
      KeystonePhoenix.Auth.complete_mfa_step_up(
        fresh.token,
        challenge.id,
        KeystonePhoenix.Auth.Mfa.Totp.code(
          secret,
          now + KeystonePhoenix.Auth.Mfa.Totp.step_seconds()
        ),
        nil
      )

    result.token
  end
end
