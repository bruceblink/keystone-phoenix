defmodule KeystonePhoenixWeb.PasswordPolicyErrorCodeHttpTest do
  @moduledoc "以真实数据库 HTTP 请求检查密码策略错误码和资料更新语义。"

  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @current_password "Old!Password123"
  @replacement_password "Changed!Strong2026"
  @strict_policy %{
    min_length: 12,
    require_uppercase: true,
    require_lowercase: true,
    require_digit: true,
    require_special: true,
    disallowed: "forbidden123!"
  }

  setup do
    previous_policy = Application.get_env(:keystone_phoenix, :password_policy)
    admin_role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        username: "password_http_#{System.unique_integer([:positive])}",
        nickname: "原始资料",
        password: @current_password,
        role_id: admin_role.role_id,
        status: 1
      })
      |> Repo.insert!()

    token = step_up_token(user, @current_password)
    Application.put_env(:keystone_phoenix, :password_policy, @strict_policy)

    on_exit(fn ->
      if is_nil(previous_policy),
        do: Application.delete_env(:keystone_phoenix, :password_policy),
        else: Application.put_env(:keystone_phoenix, :password_policy, previous_policy)
    end)

    {:ok, user: user, token: token}
  end

  @tag :integration
  test "PUT user ignores optional blank passwords and changes a valid password without ending the session",
       %{
         conn: conn,
         user: user,
         token: token
       } do
    original_hash = Repo.get!(SysUser, user.user_id).password
    path = "/api/v1/users/#{user.user_id}"

    optional_values = [
      {"missing", %{}},
      {"null", %{"password" => nil}},
      {"empty", %{"password" => ""}},
      {"Java blank", %{"password" => "\t\u2003"}}
    ]

    for {label, password_attrs} <- optional_values do
      display_name = "保留密码 #{label}"

      response =
        conn
        |> authorized(token)
        |> put(path, Map.put(password_attrs, "displayName", display_name))

      assert json_response(response, 200)["data"]["displayName"] == display_name
      stored = Repo.get!(SysUser, user.user_id)
      assert stored.password == original_hash
      assert stored.nickname == display_name
      assert Auth.Session.active?(user.user_id, session_id(token))
    end

    before_failure = Repo.get!(SysUser, user.user_id)

    rejected =
      conn
      |> authorized(token)
      |> put(path, %{"displayName" => "失败时不得保存", "password" => "lowercase123!"})

    assert get_in(json_response(rejected, 422), ["error", "code"]) ==
             "password_missing_uppercase"

    stored_after_failure = Repo.get!(SysUser, user.user_id)
    assert stored_after_failure.password == original_hash
    assert stored_after_failure.nickname == before_failure.nickname
    assert Auth.Session.active?(user.user_id, session_id(token))

    updated =
      conn
      |> authorized(token)
      |> put(path, %{
        "displayName" => "资料与密码已更新",
        "password" => @replacement_password
      })

    assert json_response(updated, 200)["data"]["displayName"] == "资料与密码已更新"
    stored_after_update = Repo.get!(SysUser, user.user_id)
    assert Bcrypt.verify_pass(@replacement_password, stored_after_update.password)
    assert stored_after_update.nickname == "资料与密码已更新"
    assert Auth.Session.active?(user.user_id, session_id(token))

    profile = conn |> authorized(token) |> get("/api/v1/profile")
    assert json_response(profile, 200)["data"]["displayName"] == "资料与密码已更新"
  end

  @tag :integration
  test "user creation returns each password policy code in Native validation order", %{
    conn: conn,
    token: token
  } do
    cases = [
      {"missing", :missing, "password_required"},
      {"null", nil, "password_required"},
      {"empty", "", "password_required"},
      {"Java blank", "\t\u2003", "password_required"},
      {"too short", "Aa1!", "password_too_short"},
      {"disallowed", "FORBIDDEN123!", "password_disallowed"},
      {"contains username", "PolicyUser42!A", "password_contains_username"},
      {"missing uppercase", "lowercase123!", "password_missing_uppercase"},
      {"missing lowercase", "UPPERCASE123!", "password_missing_lowercase"},
      {"missing digit", "NoDigitsHere!!", "password_missing_digit"},
      {"missing special", "NoSpecial1234", "password_missing_special"}
    ]

    for {label, password, expected_code} <- cases do
      username = if label == "contains username", do: "PolicyUser42", else: "policy_http_#{label}"

      attrs = %{
        "username" => username,
        "displayName" => "策略错误码测试",
        "roleCodes" => []
      }

      attrs = if password == :missing, do: attrs, else: Map.put(attrs, "password", password)
      response = conn |> authorized(token) |> post("/api/v1/users", attrs)

      assert get_in(json_response(response, 422), ["error", "code"]) == expected_code
      assert Repo.get_by(SysUser, username: username) == nil
    end
  end

  @tag :integration
  test "user identity validation takes precedence over password policy on create", %{
    conn: conn,
    token: token
  } do
    identity_fields = ["username", "displayName"]
    invalid_values = [:missing, nil, "", "\t\u2003"]

    for {field, value} <-
          for(field <- identity_fields, value <- invalid_values, do: {field, value}) do
      valid_username = "identity_policy_#{System.unique_integer([:positive])}"

      attrs = %{
        "username" => valid_username,
        "displayName" => "有效展示名",
        "password" => "lowercase123!",
        "roleCodes" => []
      }

      attrs =
        case value do
          :missing -> Map.delete(attrs, field)
          _value -> Map.put(attrs, field, value)
        end

      response = conn |> authorized(token) |> post("/api/v1/users", attrs)

      assert get_in(json_response(response, 422), ["error", "code"]) == "validation_failed"
      assert Repo.get_by(SysUser, username: attrs["username"] || valid_username) == nil
    end
  end

  @tag :integration
  test "initial password rejects missing and blank new-password values with password_required", %{
    conn: conn,
    user: user,
    token: token
  } do
    original_hash = Repo.get!(SysUser, user.user_id).password
    base = %{"username" => user.username, "currentPassword" => @current_password}

    for params <- [
          base,
          Map.put(base, "newPassword", nil),
          Map.put(base, "newPassword", ""),
          Map.put(base, "newPassword", "\t\u2003")
        ] do
      response = post(conn, "/api/v1/auth/change-initial-password", params)

      assert get_in(json_response(response, 422), ["error", "code"]) == "password_required"
      assert Repo.get!(SysUser, user.user_id).password == original_hash
      assert Auth.Session.active?(user.user_id, session_id(token))
    end
  end

  # HTTP 请求沿用同一 MFA 升级会话，检查密码更新是否影响会话有效性。
  defp authorized(conn, token),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")

  defp session_id(token) do
    {:ok, claims} =
      KeystonePhoenix.Auth.Token.verify(token, KeystonePhoenix.Auth.Token.access_type())

    claims["sid"]
  end
end
