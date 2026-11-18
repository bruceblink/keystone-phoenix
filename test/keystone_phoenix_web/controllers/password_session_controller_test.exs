defmodule KeystonePhoenixWeb.PasswordSessionControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  setup_all do
    suffix = System.unique_integer([:positive])
    function_name = "reject_password_update_#{suffix}"
    trigger_name = "reject_password_update_#{suffix}"

    ddl("""
    CREATE FUNCTION #{function_name}() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'simulated password persistence failure';
    END;
    $$
    """)

    ddl("""
    CREATE TRIGGER #{trigger_name}
    BEFORE UPDATE ON sys_user
    FOR EACH ROW
    WHEN (NEW.password IS DISTINCT FROM OLD.password AND OLD.username LIKE 'password_session_%')
    EXECUTE FUNCTION #{function_name}()
    """)

    on_exit(fn ->
      ddl("DROP TRIGGER IF EXISTS #{trigger_name} ON sys_user")
      ddl("DROP FUNCTION IF EXISTS #{function_name}()")
    end)

    {:ok, function_name: function_name}
  end

  setup %{function_name: _function_name} do
    admin_role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        username: "password_session_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        role_id: admin_role.role_id,
        status: 1
      })
      |> Repo.insert!()

    {:ok, user: user, token: step_up_token(user)}
  end

  test "returns service unavailable when an administrator password reset fails", %{
    conn: conn,
    user: user,
    token: token
  } do
    response =
      conn
      |> authorized(token)
      |> put("/api/v1/users/#{user.user_id}/password", %{"password" => "Reset!456"})

    assert get_in(json_response(response, 503), ["error", "code"]) == "authorization_unavailable"
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
      |> put("/api/v1/profile/password", %{"password" => "Reset!456"})

    assert get_in(json_response(response, 503), ["error", "code"]) == "authorization_unavailable"
    assert Auth.Session.active?(user.user_id, session_id(token))
  end

  @tag :integration
  test "returns the dedicated code when the verified current password is reused", %{
    conn: conn,
    user: user,
    token: token
  } do
    original_hash = Repo.get!(SysUser, user.user_id).password

    # 旧密码校验通过后，新旧密码相同应返回专用业务码且保留当前会话。
    response =
      conn
      |> authorized(token)
      |> put("/api/v1/profile/password", %{
        "oldPassword" => "Strong!123",
        "newPassword" => "Strong!123"
      })

    assert get_in(json_response(response, 422), ["error", "code"]) ==
             "password_same_as_current"

    assert Repo.get!(SysUser, user.user_id).password == original_hash
    assert Auth.Session.active?(user.user_id, session_id(token))
  end

  @tag :integration
  test "password policy rejects administrator reset and profile changes without revoking the session",
       %{
         conn: conn,
         user: user,
         token: token
       } do
    original_hash = Repo.get!(SysUser, user.user_id).password

    reset =
      conn
      |> authorized(token)
      |> put("/api/v1/users/#{user.user_id}/password", %{"password" => "test-only-disallowed"})

    assert get_in(json_response(reset, 422), ["error", "code"]) == "validation_failed"
    assert Repo.get!(SysUser, user.user_id).password == original_hash
    assert Auth.Session.active?(user.user_id, session_id(token))

    profile =
      conn
      |> authorized(token)
      |> put("/api/v1/profile/password", %{"password" => "test-only-disallowed"})

    assert get_in(json_response(profile, 422), ["error", "code"]) == "validation_failed"
    assert Repo.get!(SysUser, user.user_id).password == original_hash
    assert Auth.Session.active?(user.user_id, session_id(token))
  end

  defp authorized(conn, token),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")

  defp session_id(token) do
    {:ok, claims} =
      KeystonePhoenix.Auth.Token.verify(token, KeystonePhoenix.Auth.Token.access_type())

    claims["sid"]
  end

  defp ddl(sql), do: Sandbox.unboxed_run(Repo, fn -> Repo.query!(sql) end)
end
