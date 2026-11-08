defmodule KeystonePhoenixWeb.PasswordSessionControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  setup do
    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        username: "password_session_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        status: 1
      })
      |> Ecto.Changeset.put_change(:is_admin, true)
      |> Repo.insert!()

    assert {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

    Repo.query!("""
    CREATE FUNCTION reject_password_update() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'simulated password persistence failure';
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER reject_password_update
    BEFORE UPDATE ON sys_user
    FOR EACH ROW
    WHEN (NEW.password IS DISTINCT FROM OLD.password)
    EXECUTE FUNCTION reject_password_update()
    """)

    {:ok, user: user, token: tokens.token}
  end

  test "returns service unavailable when an administrator password reset fails", %{
    conn: conn,
    user: user,
    token: token
  } do
    response =
      conn
      |> authorized(token)
      |> put("/system/users/#{user.user_id}/password", %{"password" => "Reset!456"})

    assert %{"code" => 50301} = json_response(response, 503)
    assert Auth.Session.active?(user.user_id, session_id(token))
  end

  test "returns service unavailable when a profile password change fails", %{
    conn: conn,
    user: user,
    token: token
  } do
    response =
      conn
      |> authorized(token)
      |> put("/system/user/profile/password", %{
        "oldPassword" => "Strong!123",
        "newPassword" => "Reset!456"
      })

    assert %{"code" => 50301} = json_response(response, 503)
    assert Auth.Session.active?(user.user_id, session_id(token))
  end

  defp authorized(conn, token),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")

  defp session_id(token) do
    {:ok, claims} =
      KeystonePhoenix.Auth.Token.verify(token, KeystonePhoenix.Auth.Token.access_type())

    claims["sid"]
  end
end
