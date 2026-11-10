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

  @tag :integration
  test "role details include the frontend selection lists", %{conn: conn} do
    role = insert_role()
    role = Repo.update!(Ecto.Changeset.change(role, dept_id_set: "11,12"))
    menu = insert_menu(role.role_id, "system:role:query")
    user = insert_user(role.role_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

    authorized_conn = put_req_header(conn, "authorization", "Bearer #{tokens.token}")

    response = get(authorized_conn, "/system/role/#{role.role_id}")
    assert %{"code" => 0, "data" => data} = json_response(response, 200)
    assert data["menuIds"] == [menu.menu_id]
    assert data["selectedMenuList"] == [menu.menu_id]
    assert data["selectedDeptList"] == [11, 12]
  end

  @tag :integration
  test "user import template requires the import permission", %{conn: conn} do
    role = insert_role()
    user = insert_user(role.role_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

    response =
      conn
      |> put_req_header("authorization", "Bearer #{tokens.token}")
      |> get("/system/users/excelTemplate")

    assert json_response(response, 403)["code"] == 40302
  end

  @tag :integration
  test "metadata write endpoints require an administrator", %{conn: conn} do
    role = insert_role()
    insert_menu(role.role_id, "system:role:add")
    insert_menu(role.role_id, "system:menu:add")
    insert_menu(role.role_id, "system:dept:add")
    user = insert_user(role.role_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    authorized_conn = put_req_header(conn, "authorization", "Bearer #{tokens.token}")

    assert json_response(
             post(authorized_conn, "/system/role", %{"roleName" => unique("role")}),
             403
           )[
             "code"
           ] == 40301

    assert json_response(
             post(authorized_conn, "/system/menus", %{"menuName" => unique("menu")}),
             403
           )[
             "code"
           ] == 40301

    assert json_response(
             post(authorized_conn, "/system/dept", %{"deptName" => unique("dept")}),
             403
           )[
             "code"
           ] == 40301
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
