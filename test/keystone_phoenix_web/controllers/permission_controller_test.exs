defmodule KeystonePhoenixWeb.PermissionControllerTest do
  use KeystonePhoenixWeb.ConnCase, async: false

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Post.SysPost
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenixWeb.Plugs.Authenticate

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
  test "metadata write endpoints honor explicit permissions", %{conn: conn} do
    role = insert_role()
    insert_menu(role.role_id, "system:role:add")
    insert_menu(role.role_id, "system:menu:add")
    insert_menu(role.role_id, "system:dept:add")
    user = insert_user(role.role_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    authorized_conn = put_req_header(conn, "authorization", "Bearer #{tokens.token}")

    assert %{"code" => 0} =
             json_response(
               post(authorized_conn, "/system/role", %{
                 "roleName" => unique("role"),
                 "roleKey" => unique("role_key"),
                 "roleSort" => 1,
                 "status" => 1
               }),
               201
             )

    assert %{"code" => 0} =
             json_response(
               post(authorized_conn, "/system/menus", %{
                 "menuName" => unique("menu"),
                 "menuType" => 1,
                 "parentId" => 0,
                 "status" => 1
               }),
               201
             )

    assert %{"code" => 0} =
             json_response(
               post(authorized_conn, "/system/dept", %{
                 "deptName" => unique("dept"),
                 "parentId" => 0,
                 "orderNum" => 1,
                 "status" => 1
               }),
               201
             )
  end

  @tag :integration
  test "role permission metadata needs a separate delegated permission", %{conn: conn} do
    role = insert_role()
    target_role = insert_role()
    menu = insert_menu(role.role_id, "system:role:edit")
    user = insert_user(role.role_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    authorized_conn = put_req_header(conn, "authorization", "Bearer #{tokens.token}")

    assert json_response(
             put(authorized_conn, "/system/role", %{
               "roleId" => target_role.role_id,
               "roleName" => target_role.role_name,
               "roleKey" => target_role.role_key,
               "roleSort" => target_role.role_sort,
               "status" => 1,
               "menuIds" => to_string(menu.menu_id)
             }),
             403
           )["code"] == 40302

    insert_menu(role.role_id, "system:role:permission")
    {:ok, refreshed} = Auth.login_plaintext(user.username, "Strong!123", true)
    refreshed_conn = put_req_header(build_conn(), "authorization", "Bearer #{refreshed.token}")

    assert %{"code" => 0} =
             json_response(
               put(refreshed_conn, "/system/role", %{
                 "roleId" => target_role.role_id,
                 "roleName" => target_role.role_name,
                 "roleKey" => target_role.role_key,
                 "roleSort" => target_role.role_sort,
                 "status" => 1,
                 "menuIds" => to_string(menu.menu_id)
               }),
               200
             )

    assert Role.menu_ids_for_role(target_role.role_id) == [menu.menu_id]
  end

  @tag :integration
  test "dropdown and typed dictionary endpoints require explicit list permissions", %{
    conn: conn
  } do
    role = insert_role()
    user = insert_user(role.role_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    authorized_conn = put_req_header(conn, "authorization", "Bearer #{tokens.token}")

    assert json_response(get(authorized_conn, "/system/depts/dropdown"), 403)["code"] == 40302
    assert json_response(get(authorized_conn, "/system/menus/dropdown"), 403)["code"] == 40302

    assert json_response(get(authorized_conn, "/system/dict/data/type/common.status"), 403)[
             "code"
           ] == 40302
  end

  @tag :integration
  test "dropdown and typed dictionary endpoints honor their list permissions", %{conn: conn} do
    role = insert_role()
    insert_menu(role.role_id, "system:dept:list")
    insert_menu(role.role_id, "system:menu:list")
    insert_menu(role.role_id, "system:dict:list")
    user = insert_user(role.role_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")
    authorized_conn = put_req_header(conn, "authorization", "Bearer #{tokens.token}")

    assert %{"code" => 0} = json_response(get(authorized_conn, "/system/depts/dropdown"), 200)
    assert %{"code" => 0} = json_response(get(authorized_conn, "/system/menus/dropdown"), 200)

    assert %{"code" => 0} =
             json_response(get(authorized_conn, "/system/dict/data/type/common.status"), 200)
  end

  @tag :integration
  test "declared permission tables reject unmapped actions", %{conn: conn} do
    role = insert_role()
    user = insert_user(role.role_id)
    {:ok, tokens} = Auth.login_plaintext(user.username, "Strong!123")

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{tokens.token}")
      |> Map.update!(:private, &Map.put(&1, :phoenix_action, :unmapped_action))

    response = Authenticate.call(conn, permissions: %{list: "system:post:list"})

    assert response.halted
    assert json_response(response, 403)["code"] == 40302
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
