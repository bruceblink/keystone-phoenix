defmodule KeystonePhoenixWeb.PermissionControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Post.SysPost
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}
  alias KeystonePhoenix.User.SysUser

  @tag :integration
  test "allows a role permission and rejects a missing permission", %{conn: conn} do
    role = insert_role()
    menu = insert_menu(role.role_id, "system:post:list")
    insert_menu(role.role_id, "system:post:query")
    insert_menu(role.role_id, "system:post:edit")
    assert menu.permission == "system:post:list"
    user = insert_user(role.role_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

    authorized_conn = put_req_header(conn, "authorization", "Bearer #{tokens.token}")
    assert %{"code" => 0} = json_response(get(authorized_conn, "/system/post/list"), 200)

    forbidden_conn = put_req_header(build_conn(), "authorization", "Bearer #{tokens.token}")
    response = post(forbidden_conn, "/system/post", %{"postCode" => "x", "postName" => "x"})
    assert json_response(response, 403)["code"] == 40302

    post_record =
      %SysPost{}
      |> SysPost.changeset(%{
        post_code: unique("post"),
        post_name: "旧岗位",
        post_sort: 1,
        status: 1
      })
      |> Repo.insert!()

    update_conn = put_req_header(build_conn(), "authorization", "Bearer #{tokens.token}")

    assert %{"code" => 0} =
             json_response(
               put(update_conn, "/system/post", %{
                 "postId" => post_record.post_id,
                 "postCode" => post_record.post_code,
                 "postName" => "新岗位",
                 "postSort" => 1,
                 "status" => 1
               }),
               200
             )

    logout_conn = put_req_header(build_conn(), "authorization", "Bearer #{tokens.token}")
    assert %{"code" => 0} = json_response(post(logout_conn, "/logout", %{}), 200)
    assert {:error, :invalid_token} = Auth.authenticate_access_token(tokens.token)
  end

  defp insert_role do
    %SysRole{}
    |> SysRole.changeset(%{
      role_name: "权限接口角色",
      role_key: unique("api_role"),
      role_sort: 1,
      data_scope: 1,
      status: 1
    })
    |> Repo.insert!()
  end

  defp insert_menu(role_id, permission) do
    menu =
      %SysMenu{}
      |> SysMenu.changeset(%{
        menu_name: permission,
        menu_type: 0,
        parent_id: 0,
        permission: permission,
        status: 1
      })
      |> Repo.insert!()

    Repo.insert!(%SysRoleMenu{role_id: role_id, menu_id: menu.menu_id})
    menu
  end

  defp insert_user(role_id) do
    username = unique("api_user")

    %SysUser{}
    |> SysUser.create_changeset(%{
      username: username,
      password: "Strong!123",
      role_id: role_id,
      status: 1
    })
    |> Repo.insert!()
  end

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end
