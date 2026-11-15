defmodule KeystonePhoenixWeb.ProfilePermissionTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  test "profile endpoints require the same user permissions as Native", %{conn: conn} do
    role =
      %SysRole{role_id: Identity.v7()}
      |> SysRole.changeset(%{
        role_name: "无个人资料权限角色",
        role_key: "profile_denied_#{System.unique_integer([:positive])}",
        role_sort: 1,
        data_scope: "ALL",
        status: 1
      })
      |> Repo.insert!()

    user =
      %SysUser{}
      |> SysUser.create_changeset(%{
        username: "profile_denied_#{System.unique_integer([:positive])}",
        password: "Strong!123",
        role_id: role.role_id,
        status: 1
      })
      |> Repo.insert!()

    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    authorized = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{tokens.token}")

    for response <- [
          get(authorized, "/api/v1/profile"),
          put(authorized, "/api/v1/profile", %{"nickname" => "无权限"}),
          put(authorized, "/api/v1/profile/avatar", %{"avatar" => "/profile/avatar/no.png"}),
          put(authorized, "/api/v1/profile/password", %{"password" => "Reset!456"})
        ] do
      assert response.status == 403
      assert get_in(json_response(response, 403), ["error", "code"]) == "permission_denied"
    end
  end
end
